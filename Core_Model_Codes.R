# This script was cleaned and reorganized with assistance from ChatGPT; the modelling logic, model specification, and research workflow remain the author's.

suppressPackageStartupMessages({
  library(mlogit)
  library(dfidx)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(readr)
  library(tibble)
  library(purrr)
})

# -------------------------------------------------------------------
# 1. Settings
# -------------------------------------------------------------------

base_alt <- "A_Mixed"

# Adjust these paths to match your local project structure.
input_file  <- file.path("data", "InputData_1Y_2015To2023_withCDNames.csv")
prob_file   <- file.path("data", "Parcel_ID_Prob_Reference.csv")
output_dir  <- file.path("outputs", "simulation_results_with_develop_prob")
random_seed <- 123

# -------------------------------------------------------------------
# 2. Helpers
# -------------------------------------------------------------------

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  path
}

drop_non_atomic_cols <- function(df) {
  df <- as_tibble(df)
  keep <- vapply(df, function(x) !(is.list(x) || is.matrix(x)), logical(1))
  df[, keep, drop = FALSE]
}

safe_divide <- function(num, den) {
  ifelse(den > 0, num / den, 0)
}

add_common_transforms <- function(df) {
  df$FS_1Y_log <- log(df$FS_1Y + 0.01)
  df$POPDEN2021_divided <- df$POPDEN2021 / 1e6
  df$FS_AB_log <- log(df$FS_AB + 0.01)
  df$BF_A_1km <- df$BF_A_1km / 1e4
  df$EPOI_1km <- df$EPOI_1km / 1e4
  df$ResAll_C_1km_log <- log(df$ResAll_C_1km + 0.01)
  df$Toronto <- ifelse(df$CDNAME == "Toronto", 1, 0)
  df
}

add_stage2_scaling <- function(df) {
  df$POPDEN2021_divided <- df$POPDEN2021 / 1e6
  df$EPOI_1km <- df$EPOI_1km / 1e4
  df
}

aggregate_shares <- function(data, group_col = NULL, type_col, value_col) {
  if (is.null(group_col)) {
    out <- data %>%
      summarize(
        FS_Retail = sum(ifelse(.data[[type_col]] == "Retail", .data[[value_col]], 0), na.rm = TRUE),
        FS_Office = sum(ifelse(.data[[type_col]] == "Office", .data[[value_col]], 0), na.rm = TRUE),
        FS_Industrial = sum(ifelse(.data[[type_col]] == "Industrial", .data[[value_col]], 0), na.rm = TRUE),
        FS_Mixed = sum(ifelse(.data[[type_col]] == "A_Mixed", .data[[value_col]], 0), na.rm = TRUE)
      )
  } else {
    out <- data %>%
      group_by(across(all_of(group_col))) %>%
      summarize(
        FS_Retail = sum(ifelse(.data[[type_col]] == "Retail", .data[[value_col]], 0), na.rm = TRUE),
        FS_Office = sum(ifelse(.data[[type_col]] == "Office", .data[[value_col]], 0), na.rm = TRUE),
        FS_Industrial = sum(ifelse(.data[[type_col]] == "Industrial", .data[[value_col]], 0), na.rm = TRUE),
        FS_Mixed = sum(ifelse(.data[[type_col]] == "A_Mixed", .data[[value_col]], 0), na.rm = TRUE),
        .groups = "drop"
      )
  }
  
  out %>%
    mutate(
      Total = FS_Retail + FS_Office + FS_Industrial + FS_Mixed,
      Share_Retail = safe_divide(FS_Retail, Total),
      Share_Office = safe_divide(FS_Office, Total),
      Share_Industrial = safe_divide(FS_Industrial, Total),
      Share_Mixed = safe_divide(FS_Mixed, Total)
    )
}

plot_theme <- function(base_size = 12, base_family = "sans") {
  theme_bw(base_size = base_size, base_family = base_family) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5, margin = margin(b = 10)),
      plot.subtitle = element_text(hjust = 0.5, colour = "grey30", margin = margin(b = 10)),
      plot.caption = element_text(colour = "grey50", hjust = 1, margin = margin(t = 10)),
      legend.position = "bottom",
      legend.title = element_text(face = "bold"),
      axis.title = element_text(face = "bold"),
      axis.text = element_text(colour = "black"),
      strip.background = element_rect(fill = "#f0f0f0", colour = NA),
      strip.text = element_text(face = "bold"),
      panel.grid.minor = element_blank()
    )
}

dev_type_colors <- c(
  "Retail" = "#66c2a5",
  "Office" = "#fc8d62",
  "Industrial" = "#8da0cb",
  "Mixed-Use" = "#e78ac3"
)

compute_bias_factor_group <- function(df) {
  available_types <- as.character(df$Dev_Type)
  prob_lookup <- setNames(df$predicted_prob, available_types)
  
  df %>%
    mutate(
      Bias_Factor = vapply(
        available_types,
        function(current_type) {
          other_types <- setdiff(available_types, current_type)
          
          if (length(other_types) == 0) {
            return(0)
          }
          
          current_prob <- prob_lookup[[current_type]]
          other_probs <- prob_lookup[other_types]
          
          sum((other_probs * log(other_probs)) / (1 - other_probs) + log(current_prob))
        },
        numeric(1)
      )
    )
}

fit_stage2_model <- function(df) {
  lm(
    log(Dev_FS) ~
      Cap_Rate_CHG +
      log(ParcelArea) +
      BUID_A_100m +
      OS_A_1km +
      SLP_MEAN_1km +
      HWY_L_1km +
      TRAN_STP_C_100m +
      MJLC_RDS_L_100m +
      OFC_DIST +
      WETL_DIST +
      income_noLow_per +
      POPDEN2021_divided +
      Bias_Factor,
    data = df
  )
}

add_fs_predictions <- function(df, model) {
  df$FS_pred <- predict(model, newdata = df)
  df
}

process_spatial_cumulative <- function(
    obs_df,
    pred_df,
    geo_col,
    out_dir,
    prefix,
    plot_h = 10,
    plot_w = 12,
    n_cols = 3
) {
  obs_annual <- obs_df %>%
    filter(choice == TRUE) %>%
    group_by(across(all_of(c(geo_col, "Year")))) %>%
    summarize(
      FS_Retail = sum(ifelse(Dev_Type == "Retail", Dev_FS_log, 0), na.rm = TRUE),
      FS_Office = sum(ifelse(Dev_Type == "Office", Dev_FS_log, 0), na.rm = TRUE),
      FS_Ind = sum(ifelse(Dev_Type == "Industrial", Dev_FS_log, 0), na.rm = TRUE),
      FS_Mixed = sum(ifelse(Dev_Type == "A_Mixed", Dev_FS_log, 0), na.rm = TRUE),
      .groups = "drop"
    )
  
  pred_annual <- pred_df %>%
    group_by(across(all_of(c(geo_col, "Year")))) %>%
    summarize(
      FS_Retail = sum(ifelse(Simulated_Dev_Type == "Retail", FS_pred_effective, 0), na.rm = TRUE),
      FS_Office = sum(ifelse(Simulated_Dev_Type == "Office", FS_pred_effective, 0), na.rm = TRUE),
      FS_Ind = sum(ifelse(Simulated_Dev_Type == "Industrial", FS_pred_effective, 0), na.rm = TRUE),
      FS_Mixed = sum(ifelse(Simulated_Dev_Type == "A_Mixed", FS_pred_effective, 0), na.rm = TRUE),
      .groups = "drop"
    )
  
  all_years <- sort(unique(obs_df$Year))
  all_geos <- sort(unique(obs_df[[geo_col]]))
  grid <- expand.grid(geo_tmp = all_geos, Year = all_years, stringsAsFactors = FALSE)
  colnames(grid)[1] <- geo_col
  
  obs_annual <- grid %>%
    left_join(obs_annual, by = c(geo_col, "Year")) %>%
    replace(is.na(.), 0)
  
  pred_annual <- grid %>%
    left_join(pred_annual, by = c(geo_col, "Year")) %>%
    replace(is.na(.), 0)
  
  calc_cumulative_shares <- function(df, label) {
    df %>%
      group_by(across(all_of(geo_col))) %>%
      arrange(Year, .by_group = TRUE) %>%
      mutate(
        Cum_Retail = cumsum(FS_Retail),
        Cum_Office = cumsum(FS_Office),
        Cum_Ind = cumsum(FS_Ind),
        Cum_Mixed = cumsum(FS_Mixed),
        Cum_Total = Cum_Retail + Cum_Office + Cum_Ind + Cum_Mixed,
        Share_Retail = safe_divide(Cum_Retail, Cum_Total),
        Share_Office = safe_divide(Cum_Office, Cum_Total),
        Share_Industrial = safe_divide(Cum_Ind, Cum_Total),
        Share_Mixed_Use = safe_divide(Cum_Mixed, Cum_Total),
        Type = label
      ) %>%
      select(all_of(geo_col), Year, Type, starts_with("Share_"))
  }
  
  obs_cum <- calc_cumulative_shares(obs_annual, "Observed Data")
  pred_cum <- calc_cumulative_shares(pred_annual, "Model Prediction")
  
  combined <- bind_rows(obs_cum, pred_cum)
  
  export_table <- combined %>%
    pivot_wider(names_from = Type, values_from = starts_with("Share_"))
  
  write_csv(export_table, file.path(out_dir, paste0(prefix, "_Cumulative.csv")))
  
  plot_data <- combined %>%
    pivot_longer(
      cols = starts_with("Share_"),
      names_to = "Dev_Type",
      values_to = "Share"
    ) %>%
    mutate(
      Dev_Type = gsub("Share_", "", Dev_Type),
      Dev_Type = gsub("_", "-", Dev_Type),
      Dev_Type = factor(Dev_Type, levels = c("Retail", "Office", "Industrial", "Mixed-Use"))
    )
  
  p <- ggplot(plot_data, aes(x = Year, y = Share, colour = Dev_Type, linetype = Type)) +
    geom_line(linewidth = 1, alpha = 0.9) +
    facet_wrap(as.formula(paste("~", geo_col)), ncol = n_cols, scales = "fixed") +
    scale_color_manual(values = dev_type_colors, name = "Development Type") +
    scale_linetype_manual(
      values = c("Observed Data" = "solid", "Model Prediction" = "dashed"),
      name = "Data Source"
    ) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_x_continuous(breaks = c(2015, 2019, 2023)) +
    labs(
      title = paste0("Cumulative Market Share by ", prefix),
      subtitle = "Observed and predicted trends, 2015-2023",
      x = "Year",
      y = "Cumulative Market Share"
    ) +
    plot_theme()
  
  ggsave(
    filename = file.path(out_dir, paste0(prefix, "_Cumulative_Trend.png")),
    plot = p,
    width = plot_w,
    height = plot_h,
    limitsize = FALSE
  )
}

output_dir <- ensure_dir(output_dir)

# -------------------------------------------------------------------
# 3. Read and prepare input data
# -------------------------------------------------------------------

sample_data <- read_csv(input_file, show_col_types = FALSE)

sample_data$id <- as.integer(factor(sample_data$GTHA_ID))
sample_data$choiceid <- as.integer(factor(10000 * sample_data$GTHA_ID + sample_data$Year))
sample_data$choice <- as.logical(sample_data$choice)
sample_data$Dev_Type <- as.factor(sample_data$Dev_Type)
sample_data$Dev_Type <- relevel(sample_data$Dev_Type, ref = base_alt)

prob_ref <- read_csv(prob_file, show_col_types = FALSE) %>%
  transmute(
    GTHA_ID = as.character(GTHA_ID),
    Year = as.integer(Year),
    p_develop = as.numeric(proba_yearly)
  ) %>%
  group_by(GTHA_ID, Year) %>%
  summarize(p_develop = mean(p_develop, na.rm = TRUE), .groups = "drop") %>%
  mutate(p_develop = pmin(pmax(p_develop, 0), 1))

choice_meta <- sample_data %>%
  transmute(
    choiceid = as.integer(choiceid),
    GTHA_ID = as.character(GTHA_ID),
    Year = as.integer(Year),
    CDNAME,
    CSDNAME,
    MarketName
  ) %>%
  distinct() %>%
  left_join(prob_ref, by = c("GTHA_ID", "Year")) %>%
  mutate(p_develop = ifelse(is.na(p_develop), 1, p_develop))

# -------------------------------------------------------------------
# 4. Stage 1: initial MNL
# -------------------------------------------------------------------

sample_data_stage1 <- dfidx(
  sample_data,
  choice = "choice",
  idx = list(c("choiceid", "id"), "Dev_Type")
)

sample_data_stage1 <- add_common_transforms(sample_data_stage1)

stage1_formula <- choice ~
  FS_1Y_log + FS_AB_log + Lease_Deal_CHG + Sale_List_CHG + SalePrice_CHG_CPI |
  ResAll_C_1km_log + BF_A_1km + BUID_C_100m + BSTP_DIST + LU_COM + LU_IND + LU_RTL +
  Air + Bramp + CaleMilton + CoreDurham + DT + Toronto_MidNorth + Missi + OakBurling +
  Out_York + Outlying_Durham + Toronto_East + Toronto_West + York_South +
  Y_2015 + Y_2016 + Y_2017 + Y_2018 + Y_2019 + Y_2020 + Y_2021 + Y_2022 +
  log(ParcelArea) + BUID_A_100m + OS_A_1km + SLP_MEAN_1km + HWY_L_1km +
  TRAN_STP_C_100m + OFC_DIST + log(RTL_DIST + 0.01) + exp(WETL_DIST) +
  log(income_noLow_per + 0.01) + POPDEN2021_divided^2 + NBSTP_DIST |
  0

stage1_mnl <- mlogit(
  formula = stage1_formula,
  data = sample_data_stage1,
  R = 50,
  halton = NA,
  panel = FALSE
)

capture.output(
  summary(stage1_mnl),
  file = file.path(output_dir, "Stage1_MNL_Summary.txt")
)

# -------------------------------------------------------------------
# 5. Bias factor
# -------------------------------------------------------------------

stage1_probabilities <- fitted(stage1_mnl, type = "probabilities") %>%
  as_tibble() %>%
  mutate(choiceid = unique(sample_data_stage1$idx$choiceid))

stage1_probabilities_long <- stage1_probabilities %>%
  pivot_longer(
    cols = c("Industrial", "Retail", "Office", "A_Mixed"),
    names_to = "Dev_Type",
    values_to = "predicted_prob"
  )

sample_data_stage1_tbl <- as_tibble(sample_data_stage1) %>%
  mutate(
    choiceid = sample_data_stage1$idx$choiceid,
    Dev_Type = sample_data_stage1$idx$Dev_Type
  )

sample_data_with_bias <- sample_data_stage1_tbl %>%
  inner_join(stage1_probabilities_long, by = c("choiceid", "Dev_Type")) %>%
  group_split(choiceid) %>%
  map_dfr(compute_bias_factor_group)

write_csv(
  drop_non_atomic_cols(sample_data_with_bias),
  file.path(output_dir, "Stage1_with_BiasFactor_long.csv")
)

# -------------------------------------------------------------------
# 6. Stage 2: floorspace regressions
# -------------------------------------------------------------------

fs_training_data <- list(
  retail = sample_data_with_bias %>% filter(Dev_Type == "Retail", Dev_FS > 0),
  office = sample_data_with_bias %>% filter(Dev_Type == "Office", Dev_FS > 0),
  industrial = sample_data_with_bias %>% filter(Dev_Type == "Industrial", Dev_FS > 0),
  mixed = sample_data_with_bias %>% filter(Dev_Type == "A_Mixed", Dev_FS > 0)
) %>%
  map(add_stage2_scaling)

fs_models <- fs_training_data %>%
  map(fit_stage2_model)

capture.output(
  summary(fs_models$retail),
  file = file.path(output_dir, "Stage2_OLS_Retail_Summary.txt")
)
capture.output(
  summary(fs_models$office),
  file = file.path(output_dir, "Stage2_OLS_Office_Summary.txt")
)
capture.output(
  summary(fs_models$industrial),
  file = file.path(output_dir, "Stage2_OLS_Industrial_Summary.txt")
)
capture.output(
  summary(fs_models$mixed),
  file = file.path(output_dir, "Stage2_OLS_Mixed_Summary.txt")
)

fs_prediction_input <- list(
  retail = sample_data_with_bias %>% filter(Dev_Type == "Retail"),
  office = sample_data_with_bias %>% filter(Dev_Type == "Office"),
  industrial = sample_data_with_bias %>% filter(Dev_Type == "Industrial"),
  mixed = sample_data_with_bias %>% filter(Dev_Type == "A_Mixed")
)

fs_prediction_tables <- list(
  retail = add_fs_predictions(fs_prediction_input$retail, fs_models$retail),
  office = add_fs_predictions(fs_prediction_input$office, fs_models$office),
  industrial = add_fs_predictions(fs_prediction_input$industrial, fs_models$industrial),
  mixed = add_fs_predictions(fs_prediction_input$mixed, fs_models$mixed)
)

fs_predictions <- bind_rows(
  fs_prediction_tables$retail,
  fs_prediction_tables$office,
  fs_prediction_tables$industrial,
  fs_prediction_tables$mixed
)

# -------------------------------------------------------------------
# 7. Stage 3: dual MNL
# -------------------------------------------------------------------

sample_data_stage3_df <- sample_data %>%
  inner_join(
    fs_predictions %>% select(GTHA_ID, Year, Dev_Type, FS_pred),
    by = c("GTHA_ID", "Year", "Dev_Type")
  ) %>%
  mutate(
    GTHA_ID = as.character(GTHA_ID),
    Year = as.integer(Year)
  ) %>%
  left_join(prob_ref, by = c("GTHA_ID", "Year")) %>%
  mutate(p_develop = ifelse(is.na(p_develop), 1, p_develop))

sample_data_stage3_df <- add_common_transforms(sample_data_stage3_df)
sample_data_stage3_df$Dev_Type <- as.factor(sample_data_stage3_df$Dev_Type)
sample_data_stage3_df$Dev_Type <- relevel(sample_data_stage3_df$Dev_Type, ref = base_alt)

sample_data_stage3 <- dfidx(
  sample_data_stage3_df,
  choice = "choice",
  idx = list(c("choiceid", "id"), "Dev_Type")
)

stage3_formula <- choice ~
  FS_1Y_log + FS_AB_log + Lease_Deal_CHG + Sale_List_CHG + SalePrice_CHG_CPI |
  FS_pred + ResAll_C_1km_log + BF_A_1km + BUID_C_100m + BSTP_DIST + LU_COM + LU_IND + LU_RTL +
  Air + Bramp + CaleMilton + CoreDurham + DT + Toronto_MidNorth + Missi + OakBurling +
  Out_York + Outlying_Durham + Toronto_East + Toronto_West + York_South +
  Y_2015 + Y_2016 + Y_2017 + Y_2018 + Y_2019 + Y_2020 + Y_2021 + Y_2022 |
  0

stage3_mnl <- mlogit(
  formula = stage3_formula,
  data = sample_data_stage3,
  R = 50,
  halton = NA,
  panel = FALSE
)

capture.output(
  summary(stage3_mnl),
  file = file.path(output_dir, "Stage3_MNL_Dual_Summary.txt")
)

# -------------------------------------------------------------------
# 8. Monte Carlo simulation
# -------------------------------------------------------------------

prob_matrix <- fitted(stage3_mnl, type = "probabilities")
alt_names <- colnames(prob_matrix)

choiceid_vec <- unique(sample_data_stage3$idx$choiceid)

if (length(choiceid_vec) != nrow(prob_matrix)) {
  if (!is.null(rownames(prob_matrix))) {
    choiceid_vec <- as.integer(rownames(prob_matrix))
  } else {
    stop("Could not align choice IDs with the probability matrix.")
  }
}

p_lookup <- setNames(choice_meta$p_develop, choice_meta$choiceid)
p_develop_vec <- as.numeric(p_lookup[as.character(choiceid_vec)])
p_develop_vec[is.na(p_develop_vec)] <- 1

set.seed(random_seed)
develop_flag <- runif(length(choiceid_vec)) <= p_develop_vec

draw_dev_type <- function(prob_row) {
  which(runif(1) <= cumsum(prob_row))[1]
}

simulated_idx <- rep(NA_integer_, length(choiceid_vec))
simulated_idx[develop_flag] <- apply(
  prob_matrix[develop_flag, , drop = FALSE],
  1,
  draw_dev_type
)

simulated_dev_type <- rep("NoDev", length(choiceid_vec))
simulated_dev_type[develop_flag] <- alt_names[simulated_idx[develop_flag]]

prediction_df <- tibble(
  choiceid = as.integer(choiceid_vec),
  Develop = develop_flag,
  Simulated_Dev_Type = simulated_dev_type,
  p_develop = p_develop_vec
)

developed_pred <- prediction_df %>%
  filter(Develop) %>%
  inner_join(
    sample_data_stage3_df %>%
      select(choiceid, GTHA_ID, Year, CDNAME, CSDNAME, MarketName, Dev_Type, FS_pred),
    by = c("choiceid" = "choiceid", "Simulated_Dev_Type" = "Dev_Type")
  ) %>%
  mutate(FS_pred_effective = FS_pred)

nodev_pred <- prediction_df %>%
  filter(!Develop) %>%
  select(choiceid, p_develop) %>%
  left_join(
    choice_meta %>% select(choiceid, GTHA_ID, Year, CDNAME, CSDNAME, MarketName),
    by = "choiceid"
  ) %>%
  transmute(
    choiceid,
    GTHA_ID,
    Year,
    CDNAME,
    CSDNAME,
    MarketName,
    Simulated_Dev_Type = "NoDev",
    FS_pred = 0,
    FS_pred_effective = 0,
    p_develop
  )

prediction_full_df <- bind_rows(
  developed_pred %>%
    select(
      choiceid,
      GTHA_ID,
      Year,
      CDNAME,
      CSDNAME,
      MarketName,
      Simulated_Dev_Type,
      FS_pred,
      FS_pred_effective,
      p_develop
    ),
  nodev_pred
)

write_csv(
  prediction_full_df,
  file.path(output_dir, "Simulation_PredictionFull_with_DevelopFlag.csv")
)

# -------------------------------------------------------------------
# 9. Observed data
# -------------------------------------------------------------------

observed_df <- sample_data %>%
  mutate(Dev_FS_log = log(Dev_FS + 1))

# -------------------------------------------------------------------
# 10. Validation outputs
# -------------------------------------------------------------------

dir_gtha <- ensure_dir(file.path(output_dir, "1_GTHA_Total"))
dir_region <- ensure_dir(file.path(output_dir, "2_By_Region"))
dir_municipality <- ensure_dir(file.path(output_dir, "3_By_Municipality"))
dir_year <- ensure_dir(file.path(output_dir, "4_By_Year"))
dir_market <- ensure_dir(file.path(output_dir, "5_By_Market"))

# GTHA total
obs_gtha <- aggregate_shares(observed_df %>% filter(choice == TRUE), type_col = "Dev_Type", value_col = "Dev_FS_log")
pred_gtha <- aggregate_shares(prediction_full_df, type_col = "Simulated_Dev_Type", value_col = "FS_pred_effective")

comparison_gtha <- bind_cols(
  obs_gtha %>% rename_with(~ paste0("Obs_", .), everything()),
  pred_gtha %>% rename_with(~ paste0("Pred_", .), everything())
) %>%
  select(matches("Share"))

write_csv(comparison_gtha, file.path(dir_gtha, "Comparison_GTHA_Total.csv"))

plot_data_gtha <- comparison_gtha %>%
  pivot_longer(
    everything(),
    names_to = c("Type", "Dev_Type"),
    names_sep = "_Share_"
  ) %>%
  mutate(
    Type = ifelse(Type == "Obs", "Observed Data", "Model Prediction"),
    Dev_Type = ifelse(Dev_Type == "Mixed", "Mixed-Use", Dev_Type)
  )

p_gtha <- ggplot(plot_data_gtha, aes(x = Dev_Type, y = value, fill = Dev_Type, alpha = Type)) +
  geom_bar(
    stat = "identity",
    position = position_dodge(width = 0.8),
    width = 0.7,
    colour = "black",
    linewidth = 0.3
  ) +
  scale_fill_manual(values = dev_type_colors, name = "Development Type") +
  scale_alpha_manual(values = c("Observed Data" = 1, "Model Prediction" = 0.5), name = "Data Source") +
  scale_y_continuous(labels = scales::percent, expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Total Market Share Validation: GTHA (2015-2023)",
    subtitle = "Cumulative market share, weighted by floorspace",
    x = NULL,
    y = "Cumulative Market Share"
  ) +
  plot_theme() +
  theme(panel.grid.major.x = element_blank())

ggsave(file.path(dir_gtha, "Plot_GTHA_Bar.png"), p_gtha, width = 8, height = 6)

# By region (CD)
obs_cd <- aggregate_shares(
  observed_df %>% filter(choice == TRUE),
  group_col = "CDNAME",
  type_col = "Dev_Type",
  value_col = "Dev_FS_log"
)
pred_cd <- aggregate_shares(
  prediction_full_df,
  group_col = "CDNAME",
  type_col = "Simulated_Dev_Type",
  value_col = "FS_pred_effective"
)

comparison_cd <- obs_cd %>%
  rename_with(~ paste0("Obs_", .), -CDNAME) %>%
  left_join(pred_cd %>% rename_with(~ paste0("Pred_", .), -CDNAME), by = "CDNAME") %>%
  select(CDNAME, matches("Share"))

write_csv(comparison_cd, file.path(dir_region, "Comparison_By_Region.csv"))

plot_data_cd <- comparison_cd %>%
  pivot_longer(
    cols = -CDNAME,
    names_to = c("Type", "Dev_Type"),
    names_sep = "_Share_"
  ) %>%
  mutate(
    Type = ifelse(Type == "Obs", "Observed Data", "Model Prediction"),
    Dev_Type = ifelse(Dev_Type == "Mixed", "Mixed-Use", Dev_Type)
  )

p_cd <- ggplot(plot_data_cd, aes(x = Dev_Type, y = value, fill = Dev_Type, alpha = Type)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7) +
  facet_wrap(~ CDNAME, scales = "free_y") +
  scale_fill_manual(values = dev_type_colors, name = "Development Type") +
  scale_alpha_manual(values = c("Observed Data" = 1, "Model Prediction" = 0.5), name = "Data Source") +
  scale_y_continuous(labels = scales::percent, n.breaks = 4) +
  labs(
    title = "Regional Market Share Validation",
    subtitle = "Cumulative market share by census division",
    x = NULL,
    y = "Cumulative Market Share"
  ) +
  plot_theme() +
  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

ggsave(file.path(dir_region, "Plot_Region_FacetBar.png"), p_cd, width = 12, height = 8)

process_spatial_cumulative(
  observed_df = observed_df,
  pred_df = prediction_full_df,
  geo_col = "CDNAME",
  out_dir = dir_region,
  prefix = "Region",
  plot_h = 10
)

# By municipality (CSD)
obs_csd <- aggregate_shares(
  observed_df %>% filter(choice == TRUE),
  group_col = "CSDNAME",
  type_col = "Dev_Type",
  value_col = "Dev_FS_log"
)
pred_csd <- aggregate_shares(
  prediction_full_df,
  group_col = "CSDNAME",
  type_col = "Simulated_Dev_Type",
  value_col = "FS_pred_effective"
)

comparison_csd <- obs_csd %>%
  rename_with(~ paste0("Obs_", .), -CSDNAME) %>%
  left_join(pred_csd %>% rename_with(~ paste0("Pred_", .), -CSDNAME), by = "CSDNAME") %>%
  select(CSDNAME, matches("Share"))

write_csv(comparison_csd, file.path(dir_municipality, "Comparison_By_Municipality.csv"))

plot_data_csd <- comparison_csd %>%
  pivot_longer(
    cols = -CSDNAME,
    names_to = c("Type", "Dev_Type"),
    names_sep = "_Share_"
  ) %>%
  mutate(
    Type = ifelse(Type == "Obs", "Observed Data", "Model Prediction"),
    Dev_Type = ifelse(Dev_Type == "Mixed", "Mixed-Use", Dev_Type)
  )

p_csd <- ggplot(plot_data_csd, aes(x = Dev_Type, y = value, fill = Dev_Type, alpha = Type)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7) +
  facet_wrap(~ CSDNAME, ncol = 5, scales = "free_y") +
  scale_fill_manual(values = dev_type_colors, name = "Development Type") +
  scale_alpha_manual(values = c("Observed Data" = 1, "Model Prediction" = 0.5), name = "Data Source") +
  scale_y_continuous(labels = scales::percent, n.breaks = 3) +
  labs(
    title = "Municipal Market Share Validation",
    subtitle = "Cumulative market share by census subdivision",
    x = NULL,
    y = "Cumulative Market Share"
  ) +
  plot_theme(base_size = 10) +
  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

ggsave(
  file.path(dir_municipality, "Plot_CSD_FacetBar.png"),
  p_csd,
  width = 15,
  height = 20,
  limitsize = FALSE
)

process_spatial_cumulative(
  observed_df = observed_df,
  pred_df = prediction_full_df,
  geo_col = "CSDNAME",
  out_dir = dir_municipality,
  prefix = "Municipality",
  plot_h = 25,
  plot_w = 20,
  n_cols = 5
)

# By year
obs_year <- aggregate_shares(
  observed_df %>% filter(choice == TRUE),
  group_col = "Year",
  type_col = "Dev_Type",
  value_col = "Dev_FS_log"
)
pred_year <- aggregate_shares(
  prediction_full_df,
  group_col = "Year",
  type_col = "Simulated_Dev_Type",
  value_col = "FS_pred_effective"
)

comparison_year <- obs_year %>%
  rename_with(~ paste0("Obs_", .), -Year) %>%
  left_join(pred_year %>% rename_with(~ paste0("Pred_", .), -Year), by = "Year") %>%
  select(Year, matches("Share"))

write_csv(comparison_year, file.path(dir_year, "Comparison_By_Year_Annual.csv"))

plot_data_year <- comparison_year %>%
  pivot_longer(
    cols = -Year,
    names_to = c("Type", "Dev_Type"),
    names_sep = "_Share_"
  ) %>%
  mutate(
    Type = ifelse(Type == "Obs", "Observed Data", "Model Prediction"),
    Dev_Type = ifelse(Dev_Type == "Mixed", "Mixed-Use", Dev_Type)
  )

p_year <- ggplot(plot_data_year, aes(x = Year, y = value, colour = Dev_Type, linetype = Type)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2, alpha = 0.7) +
  scale_color_manual(values = dev_type_colors, name = "Development Type") +
  scale_linetype_manual(
    values = c("Observed Data" = "solid", "Model Prediction" = "dashed"),
    name = "Data Source"
  ) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_continuous(breaks = 2015:2023) +
  labs(
    title = "Annual Market Share Trends",
    subtitle = "Observed and predicted annual market shares",
    x = "Year",
    y = "Annual Market Share"
  ) +
  plot_theme()

ggsave(file.path(dir_year, "Plot_Year_Annual.png"), p_year, width = 10, height = 7)

obs_gtha_cum <- observed_df %>% mutate(Region = "GTHA Total")
pred_gtha_cum <- prediction_full_df %>% mutate(Region = "GTHA Total")

process_spatial_cumulative(
  obs_df = obs_gtha_cum,
  pred_df = pred_gtha_cum,
  geo_col = "Region",
  out_dir = dir_year,
  prefix = "GTHA_Total",
  plot_h = 6
)

# By market
obs_market <- aggregate_shares(
  observed_df %>% filter(choice == TRUE),
  group_col = "MarketName",
  type_col = "Dev_Type",
  value_col = "Dev_FS_log"
)
pred_market <- aggregate_shares(
  prediction_full_df,
  group_col = "MarketName",
  type_col = "Simulated_Dev_Type",
  value_col = "FS_pred_effective"
)

comparison_market <- obs_market %>%
  rename_with(~ paste0("Obs_", .), -MarketName) %>%
  left_join(pred_market %>% rename_with(~ paste0("Pred_", .), -MarketName), by = "MarketName") %>%
  select(MarketName, matches("Share"))

write_csv(comparison_market, file.path(dir_market, "Comparison_By_Market.csv"))

plot_data_market <- comparison_market %>%
  pivot_longer(
    cols = -MarketName,
    names_to = c("Type", "Dev_Type"),
    names_sep = "_Share_"
  ) %>%
  mutate(
    Type = ifelse(Type == "Obs", "Observed Data", "Model Prediction"),
    Dev_Type = ifelse(Dev_Type == "Mixed", "Mixed-Use", Dev_Type)
  )

p_market <- ggplot(plot_data_market, aes(x = Dev_Type, y = value, fill = Dev_Type, alpha = Type)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7) +
  facet_wrap(~ MarketName, ncol = 5, scales = "free_y") +
  scale_fill_manual(values = dev_type_colors, name = "Development Type") +
  scale_alpha_manual(values = c("Observed Data" = 1, "Model Prediction" = 0.5), name = "Data Source") +
  scale_y_continuous(labels = scales::percent, n.breaks = 3) +
  labs(
    title = "Market Area Validation",
    subtitle = "Cumulative market share by market area",
    x = NULL,
    y = "Cumulative Market Share"
  ) +
  plot_theme(base_size = 10) +
  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

ggsave(
  file.path(dir_market, "Plot_Market_FacetBar.png"),
  p_market,
  width = 15,
  height = 20,
  limitsize = FALSE
)

process_spatial_cumulative(
  observed_df = observed_df,
  pred_df = prediction_full_df,
  geo_col = "MarketName",
  out_dir = dir_market,
  prefix = "Market",
  plot_h = 25
)

message("Done. Outputs were written to: ", output_dir)
