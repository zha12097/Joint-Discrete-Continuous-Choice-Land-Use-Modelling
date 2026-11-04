# ==============================================================================
# Final-stage MNL under all four base alternatives  (manuscript Tables 4-5)
#
# Runs the multi-stage model, then re-estimates the final-stage MNL with
# Mixed-use, Retail, Industrial and Office as the base alternative. Also
# exports the annual year-dummy coefficients used for Figure A.3.
#
# Input : data/model_input.csv
#         data/development_probability.csv
# Output: outputs/final_MNL_four_base_alternatives/
# ==============================================================================

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

# Base alternative for Stage 1 and Stage 2. The final-stage MNL is then
# estimated under all four base alternatives.
base_alt <- "A_Mixed"

# Paths are relative to the repository root; run this script from there.
data_dir   <- "data"
input_file <- file.path(data_dir, "model_input.csv")               # parcel-year model input
prob_file  <- file.path(data_dir, "development_probability.csv")   # Tier 1 development probabilities
output_dir <- file.path("outputs", "final_MNL_four_base_alternatives")

random_seed <- 123


# -------------------------------------------------------------------
# 2. Helpers
# -------------------------------------------------------------------

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(
      path,
      recursive = TRUE
    )
  }
  
  path
}


drop_non_atomic_cols <- function(df) {
  df <- as_tibble(df)
  
  keep <- vapply(
    df,
    function(x) !(is.list(x) || is.matrix(x)),
    logical(1)
  )
  
  df[, keep, drop = FALSE]
}


safe_divide <- function(num, den) {
  ifelse(
    den > 0,
    num / den,
    0
  )
}


add_common_transforms <- function(df) {
  df$FS_1Y_log <- log(
    df$FS_1Y + 0.01
  )
  
  df$POPDEN2021_divided <-
    df$POPDEN2021 / 1e6
  
  df$FS_AB_log <- log(
    df$FS_AB + 0.01
  )
  
  df$BF_A_1km <-
    df$BF_A_1km / 1e4
  
  df$EPOI_1km <-
    df$EPOI_1km / 1e4
  
  df$ResAll_C_1km_log <- log(
    df$ResAll_C_1km + 0.01
  )
  
  df$Toronto <- ifelse(
    df$CDNAME == "Toronto",
    1,
    0
  )
  
  df
}


add_stage2_scaling <- function(df) {
  df$POPDEN2021_divided <-
    df$POPDEN2021 / 1e6
  
  df$EPOI_1km <-
    df$EPOI_1km / 1e4
  
  df
}


aggregate_shares <- function(
    data,
    group_col = NULL,
    type_col,
    value_col
) {
  
  if (is.null(group_col)) {
    
    out <- data %>%
      summarize(
        FS_Retail = sum(
          ifelse(
            .data[[type_col]] == "Retail",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        FS_Office = sum(
          ifelse(
            .data[[type_col]] == "Office",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        FS_Industrial = sum(
          ifelse(
            .data[[type_col]] == "Industrial",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        FS_Mixed = sum(
          ifelse(
            .data[[type_col]] == "A_Mixed",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        )
      )
    
  } else {
    
    out <- data %>%
      group_by(
        across(
          all_of(group_col)
        )
      ) %>%
      summarize(
        FS_Retail = sum(
          ifelse(
            .data[[type_col]] == "Retail",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        FS_Office = sum(
          ifelse(
            .data[[type_col]] == "Office",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        FS_Industrial = sum(
          ifelse(
            .data[[type_col]] == "Industrial",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        FS_Mixed = sum(
          ifelse(
            .data[[type_col]] == "A_Mixed",
            .data[[value_col]],
            0
          ),
          na.rm = TRUE
        ),
        
        .groups = "drop"
      )
  }
  
  out %>%
    mutate(
      Total =
        FS_Retail +
        FS_Office +
        FS_Industrial +
        FS_Mixed,
      
      Share_Retail =
        safe_divide(
          FS_Retail,
          Total
        ),
      
      Share_Office =
        safe_divide(
          FS_Office,
          Total
        ),
      
      Share_Industrial =
        safe_divide(
          FS_Industrial,
          Total
        ),
      
      Share_Mixed =
        safe_divide(
          FS_Mixed,
          Total
        )
    )
}


plot_theme <- function(
    base_size = 12,
    base_family = "sans"
) {
  
  theme_bw(
    base_size = base_size,
    base_family = base_family
  ) +
    theme(
      plot.title = element_text(
        face = "bold",
        hjust = 0.5,
        margin = margin(b = 10)
      ),
      
      plot.subtitle = element_text(
        hjust = 0.5,
        colour = "grey30",
        margin = margin(b = 10)
      ),
      
      plot.caption = element_text(
        colour = "grey50",
        hjust = 1,
        margin = margin(t = 10)
      ),
      
      legend.position = "bottom",
      
      legend.title = element_text(
        face = "bold"
      ),
      
      axis.title = element_text(
        face = "bold"
      ),
      
      axis.text = element_text(
        colour = "black"
      ),
      
      strip.background = element_rect(
        fill = "#f0f0f0",
        colour = NA
      ),
      
      strip.text = element_text(
        face = "bold"
      ),
      
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
  available_types <-
    as.character(
      df$Dev_Type
    )
  
  prob_lookup <- setNames(
    df$predicted_prob,
    available_types
  )
  
  df %>%
    mutate(
      Bias_Factor = vapply(
        available_types,
        
        function(current_type) {
          other_types <- setdiff(
            available_types,
            current_type
          )
          
          if (length(other_types) == 0) {
            return(0)
          }
          
          current_prob <-
            prob_lookup[[current_type]]
          
          other_probs <-
            prob_lookup[other_types]
          
          sum(
            (
              other_probs *
                log(other_probs)
            ) /
              (
                1 - other_probs
              ) +
              log(current_prob)
          )
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


add_fs_predictions <- function(
    df,
    model
) {
  df$FS_pred <- predict(
    model,
    newdata = df
  )
  
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
    filter(
      choice == TRUE
    ) %>%
    group_by(
      across(
        all_of(
          c(
            geo_col,
            "Year"
          )
        )
      )
    ) %>%
    summarize(
      FS_Retail = sum(
        ifelse(
          Dev_Type == "Retail",
          Dev_FS_log,
          0
        ),
        na.rm = TRUE
      ),
      
      FS_Office = sum(
        ifelse(
          Dev_Type == "Office",
          Dev_FS_log,
          0
        ),
        na.rm = TRUE
      ),
      
      FS_Ind = sum(
        ifelse(
          Dev_Type == "Industrial",
          Dev_FS_log,
          0
        ),
        na.rm = TRUE
      ),
      
      FS_Mixed = sum(
        ifelse(
          Dev_Type == "A_Mixed",
          Dev_FS_log,
          0
        ),
        na.rm = TRUE
      ),
      
      .groups = "drop"
    )
  
  
  pred_annual <- pred_df %>%
    group_by(
      across(
        all_of(
          c(
            geo_col,
            "Year"
          )
        )
      )
    ) %>%
    summarize(
      FS_Retail = sum(
        ifelse(
          Simulated_Dev_Type == "Retail",
          FS_pred_effective,
          0
        ),
        na.rm = TRUE
      ),
      
      FS_Office = sum(
        ifelse(
          Simulated_Dev_Type == "Office",
          FS_pred_effective,
          0
        ),
        na.rm = TRUE
      ),
      
      FS_Ind = sum(
        ifelse(
          Simulated_Dev_Type == "Industrial",
          FS_pred_effective,
          0
        ),
        na.rm = TRUE
      ),
      
      FS_Mixed = sum(
        ifelse(
          Simulated_Dev_Type == "A_Mixed",
          FS_pred_effective,
          0
        ),
        na.rm = TRUE
      ),
      
      .groups = "drop"
    )
  
  
  all_years <-
    sort(
      unique(
        obs_df$Year
      )
    )
  
  all_geos <-
    sort(
      unique(
        obs_df[[geo_col]]
      )
    )
  
  grid <- expand.grid(
    geo_tmp = all_geos,
    Year = all_years,
    stringsAsFactors = FALSE
  )
  
  colnames(grid)[1] <- geo_col
  
  
  obs_annual <- grid %>%
    left_join(
      obs_annual,
      by = c(
        geo_col,
        "Year"
      )
    ) %>%
    replace(
      is.na(.),
      0
    )
  
  
  pred_annual <- grid %>%
    left_join(
      pred_annual,
      by = c(
        geo_col,
        "Year"
      )
    ) %>%
    replace(
      is.na(.),
      0
    )
  
  
  calc_cumulative_shares <- function(
    df,
    label
  ) {
    
    df %>%
      group_by(
        across(
          all_of(geo_col)
        )
      ) %>%
      arrange(
        Year,
        .by_group = TRUE
      ) %>%
      mutate(
        Cum_Retail =
          cumsum(FS_Retail),
        
        Cum_Office =
          cumsum(FS_Office),
        
        Cum_Ind =
          cumsum(FS_Ind),
        
        Cum_Mixed =
          cumsum(FS_Mixed),
        
        Cum_Total =
          Cum_Retail +
          Cum_Office +
          Cum_Ind +
          Cum_Mixed,
        
        Share_Retail =
          safe_divide(
            Cum_Retail,
            Cum_Total
          ),
        
        Share_Office =
          safe_divide(
            Cum_Office,
            Cum_Total
          ),
        
        Share_Industrial =
          safe_divide(
            Cum_Ind,
            Cum_Total
          ),
        
        Share_Mixed_Use =
          safe_divide(
            Cum_Mixed,
            Cum_Total
          ),
        
        Type = label
      ) %>%
      select(
        all_of(geo_col),
        Year,
        Type,
        starts_with("Share_")
      )
  }
  
  
  obs_cum <- calc_cumulative_shares(
    obs_annual,
    "Observed Data"
  )
  
  pred_cum <- calc_cumulative_shares(
    pred_annual,
    "Model Prediction"
  )
  
  
  combined <- bind_rows(
    obs_cum,
    pred_cum
  )
  
  
  export_table <- combined %>%
    pivot_wider(
      names_from = Type,
      values_from = starts_with("Share_")
    )
  
  
  write_csv(
    export_table,
    file.path(
      out_dir,
      paste0(
        prefix,
        "_Cumulative.csv"
      )
    )
  )
  
  
  plot_data <- combined %>%
    pivot_longer(
      cols = starts_with("Share_"),
      names_to = "Dev_Type",
      values_to = "Share"
    ) %>%
    mutate(
      Dev_Type = gsub(
        "Share_",
        "",
        Dev_Type
      ),
      
      Dev_Type = gsub(
        "_",
        "-",
        Dev_Type
      ),
      
      Dev_Type = factor(
        Dev_Type,
        levels = c(
          "Retail",
          "Office",
          "Industrial",
          "Mixed-Use"
        )
      )
    )
  
  
  p <- ggplot(
    plot_data,
    aes(
      x = Year,
      y = Share,
      colour = Dev_Type,
      linetype = Type
    )
  ) +
    geom_line(
      linewidth = 1,
      alpha = 0.9
    ) +
    facet_wrap(
      as.formula(
        paste(
          "~",
          geo_col
        )
      ),
      ncol = n_cols,
      scales = "fixed"
    ) +
    scale_color_manual(
      values = dev_type_colors,
      name = "Development Type"
    ) +
    scale_linetype_manual(
      values = c(
        "Observed Data" = "solid",
        "Model Prediction" = "dashed"
      ),
      name = "Data Source"
    ) +
    scale_y_continuous(
      labels = scales::percent_format(
        accuracy = 1
      )
    ) +
    scale_x_continuous(
      breaks = c(
        2015,
        2019,
        2023
      )
    ) +
    labs(
      title = paste0(
        "Cumulative Market Share by ",
        prefix
      ),
      subtitle = "Observed and predicted trends, 2015-2023",
      x = "Year",
      y = "Cumulative Market Share"
    ) +
    plot_theme()
  
  
  ggsave(
    filename = file.path(
      out_dir,
      paste0(
        prefix,
        "_Cumulative_Trend.png"
      )
    ),
    plot = p,
    width = plot_w,
    height = plot_h,
    limitsize = FALSE
  )
}


output_dir <- ensure_dir(
  output_dir
)


# -------------------------------------------------------------------
# 3. Read and prepare input data
# -------------------------------------------------------------------

sample_data <- read_csv(
  input_file,
  show_col_types = FALSE
)


sample_data$id <- as.integer(
  factor(
    sample_data$GTHA_ID
  )
)


sample_data$choiceid <- as.integer(
  factor(
    10000 *
      sample_data$GTHA_ID +
      sample_data$Year
  )
)


sample_data$choice <-
  as.logical(
    sample_data$choice
  )


sample_data$Dev_Type <-
  as.factor(
    sample_data$Dev_Type
  )


sample_data$Dev_Type <- relevel(
  sample_data$Dev_Type,
  ref = base_alt
)


prob_ref <- read_csv(
  prob_file,
  show_col_types = FALSE
) %>%
  transmute(
    GTHA_ID =
      as.character(GTHA_ID),
    
    Year =
      as.integer(Year),
    
    p_develop =
      as.numeric(proba_yearly)
  ) %>%
  group_by(
    GTHA_ID,
    Year
  ) %>%
  summarize(
    p_develop =
      mean(
        p_develop,
        na.rm = TRUE
      ),
    
    .groups = "drop"
  ) %>%
  mutate(
    p_develop =
      pmin(
        pmax(
          p_develop,
          0
        ),
        1
      )
  )


choice_meta <- sample_data %>%
  transmute(
    choiceid =
      as.integer(choiceid),
    
    GTHA_ID =
      as.character(GTHA_ID),
    
    Year =
      as.integer(Year),
    
    CDNAME,
    CSDNAME,
    MarketName
  ) %>%
  distinct() %>%
  left_join(
    prob_ref,
    by = c(
      "GTHA_ID",
      "Year"
    )
  ) %>%
  mutate(
    p_develop =
      ifelse(
        is.na(p_develop),
        1,
        p_develop
      )
  )


# -------------------------------------------------------------------
# 4. Stage 1: initial MNL
# -------------------------------------------------------------------

sample_data_stage1 <- dfidx(
  sample_data,
  choice = "choice",
  idx = list(
    c(
      "choiceid",
      "id"
    ),
    "Dev_Type"
  )
)


sample_data_stage1 <-
  add_common_transforms(
    sample_data_stage1
  )


stage1_formula <- choice ~
  FS_1Y_log +
  FS_AB_log +
  Lease_Deal_CHG +
  Sale_List_CHG +
  SalePrice_CHG_CPI |
  
  ResAll_C_1km_log +
  BF_A_1km +
  BUID_C_100m +
  BSTP_DIST +
  LU_COM +
  LU_IND +
  LU_RTL +
  Air +
  Bramp +
  CaleMilton +
  CoreDurham +
  DT +
  Toronto_MidNorth +
  Missi +
  OakBurling +
  Out_York +
  Outlying_Durham +
  Toronto_East +
  Toronto_West +
  York_South +
  Y_2015 +
  Y_2016 +
  Y_2017 +
  Y_2018 +
  Y_2019 +
  Y_2020 +
  Y_2021 +
  Y_2022 +
  log(ParcelArea) +
  BUID_A_100m +
  OS_A_1km +
  SLP_MEAN_1km +
  HWY_L_1km +
  TRAN_STP_C_100m +
  OFC_DIST +
  log(RTL_DIST + 0.01) +
  exp(WETL_DIST) +
  log(income_noLow_per + 0.01) +
  POPDEN2021_divided^2 +
  NBSTP_DIST |
  
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
  file = file.path(
    output_dir,
    "Stage1_MNL_Summary.txt"
  )
)


# -------------------------------------------------------------------
# 5. Bias factor
# -------------------------------------------------------------------

stage1_probabilities <- fitted(
  stage1_mnl,
  type = "probabilities"
) %>%
  as_tibble() %>%
  mutate(
    choiceid =
      unique(
        sample_data_stage1$idx$choiceid
      )
  )


stage1_probabilities_long <-
  stage1_probabilities %>%
  pivot_longer(
    cols = c(
      "Industrial",
      "Retail",
      "Office",
      "A_Mixed"
    ),
    names_to = "Dev_Type",
    values_to = "predicted_prob"
  )


sample_data_stage1_tbl <-
  as_tibble(
    sample_data_stage1
  ) %>%
  mutate(
    choiceid =
      sample_data_stage1$idx$choiceid,
    
    Dev_Type =
      sample_data_stage1$idx$Dev_Type
  )


sample_data_with_bias <-
  sample_data_stage1_tbl %>%
  inner_join(
    stage1_probabilities_long,
    by = c(
      "choiceid",
      "Dev_Type"
    )
  ) %>%
  group_split(
    choiceid
  ) %>%
  map_dfr(
    compute_bias_factor_group
  )


write_csv(
  drop_non_atomic_cols(
    sample_data_with_bias
  ),
  file.path(
    output_dir,
    "Stage1_with_BiasFactor_long.csv"
  )
)


# -------------------------------------------------------------------
# 6. Stage 2: floorspace regressions
# -------------------------------------------------------------------

fs_training_data <- list(
  
  retail =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "Retail",
      Dev_FS > 0
    ),
  
  office =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "Office",
      Dev_FS > 0
    ),
  
  industrial =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "Industrial",
      Dev_FS > 0
    ),
  
  mixed =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "A_Mixed",
      Dev_FS > 0
    )
  
) %>%
  map(
    add_stage2_scaling
  )


fs_models <- fs_training_data %>%
  map(
    fit_stage2_model
  )


capture.output(
  summary(
    fs_models$retail
  ),
  file = file.path(
    output_dir,
    "Stage2_OLS_Retail_Summary.txt"
  )
)


capture.output(
  summary(
    fs_models$office
  ),
  file = file.path(
    output_dir,
    "Stage2_OLS_Office_Summary.txt"
  )
)


capture.output(
  summary(
    fs_models$industrial
  ),
  file = file.path(
    output_dir,
    "Stage2_OLS_Industrial_Summary.txt"
  )
)


capture.output(
  summary(
    fs_models$mixed
  ),
  file = file.path(
    output_dir,
    "Stage2_OLS_Mixed_Summary.txt"
  )
)


fs_prediction_input <- list(
  
  retail =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "Retail"
    ),
  
  office =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "Office"
    ),
  
  industrial =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "Industrial"
    ),
  
  mixed =
    sample_data_with_bias %>%
    filter(
      Dev_Type == "A_Mixed"
    )
)


fs_prediction_tables <- list(
  
  retail =
    add_fs_predictions(
      fs_prediction_input$retail,
      fs_models$retail
    ),
  
  office =
    add_fs_predictions(
      fs_prediction_input$office,
      fs_models$office
    ),
  
  industrial =
    add_fs_predictions(
      fs_prediction_input$industrial,
      fs_models$industrial
    ),
  
  mixed =
    add_fs_predictions(
      fs_prediction_input$mixed,
      fs_models$mixed
    )
)


fs_predictions <- bind_rows(
  fs_prediction_tables$retail,
  fs_prediction_tables$office,
  fs_prediction_tables$industrial,
  fs_prediction_tables$mixed
)


# -------------------------------------------------------------------
# 7. Final-stage MNL: prepare common data
# -------------------------------------------------------------------

sample_data_stage3_df <- sample_data %>%
  inner_join(
    fs_predictions %>%
      select(
        GTHA_ID,
        Year,
        Dev_Type,
        FS_pred
      ),
    by = c(
      "GTHA_ID",
      "Year",
      "Dev_Type"
    )
  ) %>%
  mutate(
    GTHA_ID =
      as.character(
        GTHA_ID
      ),
    
    Year =
      as.integer(
        Year
      )
  ) %>%
  left_join(
    prob_ref,
    by = c(
      "GTHA_ID",
      "Year"
    )
  ) %>%
  mutate(
    p_develop =
      ifelse(
        is.na(p_develop),
        1,
        p_develop
      )
  )


sample_data_stage3_df <-
  add_common_transforms(
    sample_data_stage3_df
  )


# -------------------------------------------------------------------
# 7.1 Final-stage MNL formula
# -------------------------------------------------------------------

stage3_formula <- choice ~
  
  FS_1Y_log +
  FS_AB_log +
  Lease_Deal_CHG +
  Sale_List_CHG +
  SalePrice_CHG_CPI |
  
  FS_pred +
  ResAll_C_1km_log +
  BF_A_1km +
  BUID_C_100m +
  BSTP_DIST +
  LU_COM +
  LU_IND +
  LU_RTL +
  Air +
  Bramp +
  CaleMilton +
  CoreDurham +
  DT +
  Toronto_MidNorth +
  Missi +
  OakBurling +
  Out_York +
  Outlying_Durham +
  Toronto_East +
  Toronto_West +
  York_South +
  Y_2015 +
  Y_2016 +
  Y_2017 +
  Y_2018 +
  Y_2019 +
  Y_2020 +
  Y_2021 +
  Y_2022 |
  
  0


# -------------------------------------------------------------------
# 7.2 Final-stage MNL: all four base alternatives
# -------------------------------------------------------------------

final_base_alternatives <- c(
  "A_Mixed",
  "Retail",
  "Industrial",
  "Office"
)


final_base_labels <- c(
  "A_Mixed" = "Mixed-Use",
  "Retail" = "Retail",
  "Industrial" = "Industrial",
  "Office" = "Office"
)


# Store all four fitted models
stage3_mnl_models <- list()


for (current_base in final_base_alternatives) {
  
  # ---------------------------------------------------------------
  # Create fresh copy for each base alternative
  # ---------------------------------------------------------------
  
  current_stage3_df <-
    sample_data_stage3_df
  
  
  current_stage3_df$Dev_Type <- factor(
    current_stage3_df$Dev_Type,
    levels = c(
      "A_Mixed",
      "Industrial",
      "Office",
      "Retail"
    )
  )
  
  
  current_stage3_df$Dev_Type <- relevel(
    current_stage3_df$Dev_Type,
    ref = current_base
  )
  
  
  # ---------------------------------------------------------------
  # Convert to dfidx
  # ---------------------------------------------------------------
  
  current_stage3 <- dfidx(
    current_stage3_df,
    choice = "choice",
    idx = list(
      c(
        "choiceid",
        "id"
      ),
      "Dev_Type"
    )
  )
  
  
  # ---------------------------------------------------------------
  # Estimate final-stage MNL
  # ---------------------------------------------------------------
  
  current_model <- mlogit(
    formula = stage3_formula,
    data = current_stage3,
    R = 50,
    halton = NA,
    panel = FALSE
  )
  
  
  # ---------------------------------------------------------------
  # Store model
  # ---------------------------------------------------------------
  
  stage3_mnl_models[[current_base]] <-
    current_model
  
  
  # ---------------------------------------------------------------
  # PRINT COMPLETE SUMMARY TO R CONSOLE
  # ---------------------------------------------------------------
  
  cat("\n\n")
  
  cat(
    "====================================================================\n"
  )
  
  cat(
    "====================================================================\n"
  )
  
  cat(
    "FINAL-STAGE MNL\n"
  )
  
  cat(
    "BASE ALTERNATIVE: ",
    final_base_labels[[current_base]],
    "\n",
    sep = ""
  )
  
  cat(
    "====================================================================\n"
  )
  
  cat(
    "====================================================================\n\n"
  )
  
  
  print(
    summary(
      current_model
    )
  )
  
  
  cat("\n")
  
  cat(
    "END OF MODEL: ",
    final_base_labels[[current_base]],
    " BASE\n",
    sep = ""
  )
  
  cat(
    "====================================================================\n\n"
  )
  
  
  # ---------------------------------------------------------------
  # Also save complete summary as TXT
  # ---------------------------------------------------------------
  
  output_name <- paste0(
    "FinalStage_MNL_Base_",
    gsub(
      "-",
      "_",
      final_base_labels[[current_base]]
    ),
    "_Summary.txt"
  )
  
  
  capture.output(
    summary(
      current_model
    ),
    file = file.path(
      output_dir,
      output_name
    )
  )
}


# -------------------------------------------------------------------
# 7.3 Individual model objects
# -------------------------------------------------------------------

stage3_mnl_mixed <-
  stage3_mnl_models[["A_Mixed"]]


stage3_mnl_retail <-
  stage3_mnl_models[["Retail"]]


stage3_mnl_industrial <-
  stage3_mnl_models[["Industrial"]]


stage3_mnl_office <-
  stage3_mnl_models[["Office"]]


# -------------------------------------------------------------------
# 7.4 Mixed-use-base model as the default final-stage MNL
# -------------------------------------------------------------------

stage3_mnl <-
  stage3_mnl_mixed


sample_data_stage3_df$Dev_Type <- factor(
  sample_data_stage3_df$Dev_Type,
  levels = c(
    "A_Mixed",
    "Industrial",
    "Office",
    "Retail"
  )
)


sample_data_stage3_df$Dev_Type <- relevel(
  sample_data_stage3_df$Dev_Type,
  ref = "A_Mixed"
)


sample_data_stage3 <- dfidx(
  sample_data_stage3_df,
  choice = "choice",
  idx = list(
    c(
      "choiceid",
      "id"
    ),
    "Dev_Type"
  )
)


# -------------------------------------------------------------------
# 7.5 Confirmation
# -------------------------------------------------------------------

cat("\n\n")

cat(
  "####################################################################\n"
)

cat(
  "ALL FOUR FINAL-STAGE MNL MODELS HAVE BEEN ESTIMATED.\n"
)

cat(
  "####################################################################\n\n"
)

cat(
  "Available model objects:\n\n"
)

cat(
  "1. stage3_mnl_mixed\n"
)

cat(
  "2. stage3_mnl_retail\n"
)

cat(
  "3. stage3_mnl_industrial\n"
)

cat(
  "4. stage3_mnl_office\n\n"
)

cat(
  "stage3_mnl is the Mixed-use-base model.\n\n"
)

# ===================================================================
# 7.6 Export annual temporal indicators for visualization
# ===================================================================
#
# Exports the annual MNL results to
#   outputs/final_MNL_four_base_alternatives/annual_temporal_indicators.csv
# which scripts/python/figA3_annual_temporal_indicators.py reads to draw Figure A.3.
# ===================================================================

extract_annual_results <- function(
    model,
    panel,
    base_label
) {
  
  # ---------------------------------------------------------------
  # Extract coefficient table
  # ---------------------------------------------------------------
  
  coef_table <- as.data.frame(
    summary(model)$CoefTable
  )
  
  coef_table$Term <- rownames(
    coef_table
  )
  
  rownames(coef_table) <- NULL
  
  
  # ---------------------------------------------------------------
  # Rename coefficient-table columns BEFORE filtering
  # ---------------------------------------------------------------
  
  names(coef_table)[1:4] <- c(
    "Estimate",
    "Std_Error",
    "z_value",
    "p_value"
  )
  
  
  # ---------------------------------------------------------------
  # Keep only annual indicators
  # ---------------------------------------------------------------
  
  annual_results <- coef_table %>%
    filter(
      grepl(
        "^Y_(2015|2016|2017|2018|2019|2020|2021|2022):",
        Term
      )
    ) %>%
    mutate(
      
      Year = as.integer(
        sub(
          "^Y_([0-9]{4}):.*$",
          "\\1",
          Term
        )
      ),
      
      Target = sub(
        "^Y_[0-9]{4}:",
        "",
        Term
      ),
      
      Target = ifelse(
        Target == "A_Mixed",
        "Mixed-use",
        Target
      ),
      
      Panel = panel,
      
      Base = base_label,
      
      Estimate = as.numeric(
        Estimate
      ),
      
      Std_Error = as.numeric(
        Std_Error
      ),
      
      z_value = as.numeric(
        z_value
      ),
      
      p_value = as.numeric(
        p_value
      ),
      
      # Significance convention used in the manuscript
      Significance = case_when(
        p_value < 0.05 ~ "***",
        p_value < 0.10 ~ "*",
        TRUE ~ ""
      )
    ) %>%
    select(
      Panel,
      Base,
      Year,
      Target,
      Estimate,
      Std_Error,
      z_value,
      p_value,
      Significance
    ) %>%
    arrange(
      Year,
      Target
    )
  
  annual_results
}


# -------------------------------------------------------------------
# Combine the four base-alternative specifications
# -------------------------------------------------------------------

annual_results_all <- bind_rows(
  
  extract_annual_results(
    stage3_mnl_mixed,
    "A",
    "Mixed-use"
  ),
  
  extract_annual_results(
    stage3_mnl_retail,
    "B",
    "Retail"
  ),
  
  extract_annual_results(
    stage3_mnl_industrial,
    "C",
    "Industrial"
  ),
  
  extract_annual_results(
    stage3_mnl_office,
    "D",
    "Office"
  )
)


# -------------------------------------------------------------------
# Add full panel titles
# -------------------------------------------------------------------

annual_results_all <- annual_results_all %>%
  mutate(
    
    Panel_Title = case_when(
      
      Panel == "A" ~
        "Panel A. Base Alternative = Mixed-use",
      
      Panel == "B" ~
        "Panel B. Base Alternative = Retail",
      
      Panel == "C" ~
        "Panel C. Base Alternative = Industrial",
      
      Panel == "D" ~
        "Panel D. Base Alternative = Office"
    )
  ) %>%
  select(
    Panel,
    Panel_Title,
    Base,
    Year,
    Target,
    Estimate,
    Std_Error,
    z_value,
    p_value,
    Significance
  )


# -------------------------------------------------------------------
# Check expected number of rows
# -------------------------------------------------------------------

cat(
  "\nNumber of exported annual coefficients:",
  nrow(annual_results_all),
  "\n"
)

cat(
  "Expected number of rows: 96 (4 models × 8 years × 3 targets)\n\n"
)


if (nrow(annual_results_all) != 96) {
  
  stop(
    paste0(
      "Unexpected number of annual coefficients: ",
      nrow(annual_results_all),
      ". Expected 96."
    )
  )
}


# -------------------------------------------------------------------
# Create output directory if needed
# -------------------------------------------------------------------

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


# -------------------------------------------------------------------
# Export CSV
# -------------------------------------------------------------------

annual_results_file <- normalizePath(
  file.path(
    output_dir,
    "annual_temporal_indicators.csv"
  ),
  winslash = "/",
  mustWork = FALSE
)


write_csv(
  annual_results_all,
  annual_results_file
)


annual_results_file <- normalizePath(
  annual_results_file,
  winslash = "/",
  mustWork = TRUE
)


cat(
  "Annual temporal indicators exported successfully:\n",
  annual_results_file,
  "\n\n"
)


# -------------------------------------------------------------------
# Optional console preview
# -------------------------------------------------------------------

print(
  as_tibble(
    annual_results_all
  ),
  n = Inf
)
