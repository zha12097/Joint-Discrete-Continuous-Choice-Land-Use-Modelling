# ==============================================================================
# Generic expected-floorspace model                      (manuscript Table 3)
#
# Stage 1 MNL -> Dubin-McFadden bias factor -> Stage 2 OLS by sector ->
# Stage 3 MNL with a single generic FS_pred coefficient.
#
# Input : data/model_input.csv
# Output: outputs/generic_FS_model/
#
# Base_Alt can be set to "A_Mixed", "Retail", "Office" or "Industrial".
# ==============================================================================

library("mlogit")
library(tidyverse)
library(dplyr)
library(ggplot2)
library(readr)

# -------------------------------------------------------------------------
# 0. Configuration & Data Loading
# -------------------------------------------------------------------------

Base_Alt <- "Industrial"

# Paths are relative to the repository root; run this script from there.
data_dir   <- "data"
input_file <- file.path(data_dir, "model_input.csv")      # parcel-year model input
output_dir <- file.path("outputs", "generic_FS_model")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

sample_data <- read_csv(input_file)
sample_data$id <- as.integer(factor(sample_data$GTHA_ID))
sample_data$choiceid = as.integer(factor(10000 * sample_data$GTHA_ID + sample_data$Year))
sample_data$choice <- as.logical(sample_data$choice)

# Re-leveling
sample_data$Dev_Type <- as.factor(sample_data$Dev_Type)
sample_data$Dev_Type <- relevel(sample_data$Dev_Type, ref = Base_Alt)

##### Creating dataset for Stage 1
sample_data2 <- dfidx(sample_data, choice = 'choice', idx = list(c('choiceid', 'id'), 'Dev_Type'))

# Transformations
sample_data2$FS_1Y_log <- log(sample_data2$FS_1Y + 0.01)
sample_data2$POPDEN2021_divided <- sample_data2$POPDEN2021 / 1E6
sample_data2$FS_AB_log <- log(sample_data2$FS_AB + 0.01)
sample_data2$BF_A_1km <- sample_data2$BF_A_1km / 1E4
sample_data2$EPOI_1km <- sample_data2$EPOI_1km / 1E4
sample_data2$ResAll_C_1km_log <- log(sample_data2$ResAll_C_1km + 0.01)
sample_data2$Toronto <- ifelse(sample_data2$CDNAME == "Toronto", 1, 0)

# -------------------------------------------------------------------------
# Stage 1: Initial MNL
# -------------------------------------------------------------------------
sample_data2.mnl <- mlogit(choice ~
                             FS_1Y_log + FS_AB_log + Lease_Deal_CHG + Sale_List_CHG + SalePrice_CHG_CPI
                           | ResAll_C_1km_log + BF_A_1km + BUID_C_100m + BSTP_DIST + LU_COM + LU_IND + LU_RTL
                           + Air + Bramp + CaleMilton + CoreDurham + DT + Toronto_MidNorth + Missi + OakBurling + Out_York + Outlying_Durham + Toronto_East + Toronto_West + York_South
                           + Y_2015 + Y_2016 + Y_2017 + Y_2018 + Y_2019 + Y_2020 + Y_2021 + Y_2022
                           + log(ParcelArea) + BUID_A_100m + OS_A_1km + SLP_MEAN_1km + HWY_L_1km + TRAN_STP_C_100m + OFC_DIST
                           + log(RTL_DIST+0.01) + exp(WETL_DIST) + log(income_noLow_per+0.01) + POPDEN2021_divided^2 + NBSTP_DIST
                           | 0, sample_data2, R = 50, halton = NA, panel = FALSE)

summary(sample_data2.mnl)

# -------------------------------------------------------------------------
# Bias Correction
# -------------------------------------------------------------------------
predicted <- fitted(sample_data2.mnl, type = "probabilities")
predicted <- as_tibble(predicted) %>% mutate(choiceid = unique(sample_data2$idx$choiceid))

predicted_long <- predicted %>%
  pivot_longer(cols = c("Industrial", "Retail", "Office", "A_Mixed"),
               names_to = "Dev_Type", values_to = "predicted_prob")

sample_data2_tibble <- as_tibble(sample_data2) %>%
  mutate(choiceid = sample_data2$idx$choiceid, Dev_Type = sample_data2$idx$Dev_Type)

sample_data2_with_prob <- sample_data2_tibble %>%
  inner_join(predicted_long, by = c("choiceid" = "choiceid", "Dev_Type" = "Dev_Type")) %>%
  group_by(choiceid) %>%
  mutate(
    num_dev_types = n_distinct(Dev_Type),
    P_Retail = ifelse("Retail" %in% Dev_Type, predicted_prob[Dev_Type == "Retail"], 0),
    P_Office = ifelse("Office" %in% Dev_Type, predicted_prob[Dev_Type == "Office"], 0),
    P_Industrial = ifelse("Industrial" %in% Dev_Type, predicted_prob[Dev_Type == "Industrial"], 0),
    P_A_Mixed = ifelse("A_Mixed" %in% Dev_Type, predicted_prob[Dev_Type == "A_Mixed"], 0),
    Bias_Factor = case_when(
      num_dev_types == 4 & Dev_Type == "Retail" ~ (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Retail)) + (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Retail)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Retail)),
      num_dev_types == 4 & Dev_Type == "Office" ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Office)) + (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Office)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Office)),
      num_dev_types == 4 & Dev_Type == "Industrial" ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Industrial)) + (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Industrial)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Industrial)),
      num_dev_types == 4 & Dev_Type == "A_Mixed" ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_A_Mixed)) + (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_A_Mixed)) + (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_A_Mixed)),
      num_dev_types == 3 & Dev_Type == "Retail" & P_Office > 0 & P_Industrial > 0 ~ (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Retail)) + (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Retail)),
      num_dev_types == 3 & Dev_Type == "Retail" & P_Office > 0 & P_A_Mixed > 0 ~ (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Retail)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Retail)),
      num_dev_types == 3 & Dev_Type == "Retail" & P_Industrial > 0 & P_A_Mixed > 0 ~ (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Retail)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Retail)),
      num_dev_types == 3 & Dev_Type == "Office" & P_Retail > 0 & P_Industrial > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Office)) + (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Office)),
      num_dev_types == 3 & Dev_Type == "Office" & P_Retail > 0 & P_A_Mixed > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Office)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Office)),
      num_dev_types == 3 & Dev_Type == "Office" & P_Industrial > 0 & P_A_Mixed > 0 ~ (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Office)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Office)),
      num_dev_types == 3 & Dev_Type == "Industrial" & P_Retail > 0 & P_Office > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Industrial)) + (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Industrial)),
      num_dev_types == 3 & Dev_Type == "Industrial" & P_Retail > 0 & P_A_Mixed > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Industrial)) + (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Industrial)),
      num_dev_types == 3 & Dev_Type == "Industrial" & P_Office > 0 & P_A_Mixed > 0 ~ (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Industrial)) + (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Industrial)),
      num_dev_types == 3 & Dev_Type == "A_Mixed" & P_Retail > 0 & P_Office > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_A_Mixed)) + (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_A_Mixed)),
      num_dev_types == 3 & Dev_Type == "A_Mixed" & P_Retail > 0 & P_Industrial > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_A_Mixed)) + (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_A_Mixed)),
      num_dev_types == 3 & Dev_Type == "A_Mixed" & P_Office > 0 & P_Industrial > 0 ~ (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_A_Mixed)) + (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_A_Mixed)),
      num_dev_types == 2 & Dev_Type == "Retail" & P_Office > 0 ~ (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Retail)),
      num_dev_types == 2 & Dev_Type == "Retail" & P_Industrial > 0 ~ (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Retail)),
      num_dev_types == 2 & Dev_Type == "Retail" & P_A_Mixed > 0 ~ (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Retail)),
      num_dev_types == 2 & Dev_Type == "Office" & P_Retail > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Office)),
      num_dev_types == 2 & Dev_Type == "Office" & P_Industrial > 0 ~ (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_Office)),
      num_dev_types == 2 & Dev_Type == "Office" & P_A_Mixed > 0 ~ (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Office)),
      num_dev_types == 2 & Dev_Type == "Industrial" & P_Retail > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_Industrial)),
      num_dev_types == 2 & Dev_Type == "Industrial" & P_Office > 0 ~ (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_Industrial)),
      num_dev_types == 2 & Dev_Type == "Industrial" & P_A_Mixed > 0 ~ (((P_A_Mixed * log(P_A_Mixed)) / (1 - P_A_Mixed)) + log(P_Industrial)),
      num_dev_types == 2 & Dev_Type == "A_Mixed" & P_Retail > 0 ~ (((P_Retail * log(P_Retail)) / (1 - P_Retail)) + log(P_A_Mixed)),
      num_dev_types == 2 & Dev_Type == "A_Mixed" & P_Office > 0 ~ (((P_Office * log(P_Office)) / (1 - P_Office)) + log(P_A_Mixed)),
      num_dev_types == 2 & Dev_Type == "A_Mixed" & P_Industrial > 0 ~ (((P_Industrial * log(P_Industrial)) / (1 - P_Industrial)) + log(P_A_Mixed)),
      num_dev_types == 1 ~ 0,
      TRUE ~ NA_real_
    )
  ) %>% ungroup() %>% select(-num_dev_types, -P_Retail, -P_Office, -P_Industrial, -P_A_Mixed)

# -------------------------------------------------------------------------
# Stage 2: Regression (OLS)
# -------------------------------------------------------------------------
retail_FS <- sample_data2_with_prob %>% filter(Dev_Type == "Retail" & Dev_FS > 0)
office_FS <- sample_data2_with_prob %>% filter(Dev_Type == "Office" & Dev_FS > 0)
industrial_FS <- sample_data2_with_prob %>% filter(Dev_Type == "Industrial" & Dev_FS > 0)
A_Mixed_FS <- sample_data2_with_prob %>% filter(Dev_Type == "A_Mixed" & Dev_FS > 0)

retail_FS$POPDEN2021_divided <- retail_FS$POPDEN2021 / 1E6
office_FS$POPDEN2021_divided <- office_FS$POPDEN2021 / 1E6
industrial_FS$POPDEN2021_divided <- industrial_FS$POPDEN2021 / 1E6
A_Mixed_FS$POPDEN2021_divided <- A_Mixed_FS$POPDEN2021 / 1E6
retail_FS$EPOI_1km <- retail_FS$EPOI_1km / 1E4
office_FS$EPOI_1km <- office_FS$EPOI_1km / 1E4
industrial_FS$EPOI_1km <- industrial_FS$EPOI_1km / 1E4
A_Mixed_FS$EPOI_1km <- A_Mixed_FS$EPOI_1km / 1E4

OLS.retail <- lm(log(Dev_FS) ~ Cap_Rate_CHG + log(ParcelArea) + BUID_A_100m + OS_A_1km + SLP_MEAN_1km + HWY_L_1km + TRAN_STP_C_100m + MJLC_RDS_L_100m + OFC_DIST + WETL_DIST + income_noLow_per + POPDEN2021_divided + Bias_Factor, data = retail_FS)
OLS.office <- lm(log(Dev_FS) ~ Cap_Rate_CHG + log(ParcelArea) + BUID_A_100m + OS_A_1km + SLP_MEAN_1km + HWY_L_1km + MJLC_RDS_L_100m + TRAN_STP_C_100m + OFC_DIST + WETL_DIST + income_noLow_per + POPDEN2021_divided + Bias_Factor, data = office_FS)
OLS.industrial <- lm(log(Dev_FS) ~ Cap_Rate_CHG + log(ParcelArea) + BUID_A_100m + OS_A_1km + SLP_MEAN_1km + HWY_L_1km + TRAN_STP_C_100m + MJLC_RDS_L_100m + OFC_DIST + WETL_DIST + income_noLow_per + POPDEN2021_divided + Bias_Factor, data = industrial_FS)
OLS.mixed <- lm(log(Dev_FS) ~ Cap_Rate_CHG + log(ParcelArea) + BUID_A_100m + OS_A_1km + SLP_MEAN_1km + HWY_L_1km + MJLC_RDS_L_100m + TRAN_STP_C_100m + OFC_DIST + WETL_DIST + income_noLow_per + POPDEN2021_divided + Bias_Factor, data = A_Mixed_FS)

# -------------------------------------------------------------------------
# Prediction Logic
# -------------------------------------------------------------------------
retail_input_for_regression <- sample_data2_with_prob %>% filter(Dev_Type == "Retail")
office_input_for_regression <- sample_data2_with_prob %>% filter(Dev_Type == "Office")
industrial_input_for_regression <- sample_data2_with_prob %>% filter(Dev_Type == "Industrial")
mixed_input_for_regression <- sample_data2_with_prob %>% filter(Dev_Type == "A_Mixed")

retail_input_for_regression$FS_pred <- predict(OLS.retail, newdata = retail_input_for_regression)
office_input_for_regression$FS_pred <- predict(OLS.office, newdata = office_input_for_regression)
industrial_input_for_regression$FS_pred <- predict(OLS.industrial, newdata = industrial_input_for_regression)
mixed_input_for_regression$FS_pred <- predict(OLS.mixed, newdata = mixed_input_for_regression)

to_predict_combined <- bind_rows(retail_input_for_regression, office_input_for_regression, industrial_input_for_regression, mixed_input_for_regression)

# -------------------------------------------------------------------------
# Re-construct Data for Stage 3
# -------------------------------------------------------------------------
sample_data2_final_df <- sample_data %>%
  inner_join(to_predict_combined %>% select(GTHA_ID, Year, Dev_Type, FS_pred), by = c("GTHA_ID", "Year", "Dev_Type"))

sample_data2_final_df$FS_1Y_log <- log(sample_data2_final_df$FS_1Y + 0.01)
sample_data2_final_df$POPDEN2021_divided <- sample_data2_final_df$POPDEN2021 / 1E6
sample_data2_final_df$FS_AB_log <- log(sample_data2_final_df$FS_AB + 0.01)
sample_data2_final_df$BF_A_1km <- sample_data2_final_df$BF_A_1km / 1E4
sample_data2_final_df$EPOI_1km <- sample_data2_final_df$EPOI_1km / 1E4
sample_data2_final_df$ResAll_C_1km_log <- log(sample_data2_final_df$ResAll_C_1km + 0.01)
sample_data2_final_df$Toronto <- ifelse(sample_data2_final_df$CDNAME == "Toronto", 1, 0)

sample_data2_final_df$Dev_Type <- as.factor(sample_data2_final_df$Dev_Type)
sample_data2_final_df$Dev_Type <- relevel(sample_data2_final_df$Dev_Type, ref = Base_Alt)

sample_data2_final <- dfidx(sample_data2_final_df, choice = 'choice', idx = list(c('choiceid', 'id'), 'Dev_Type'))

# -------------------------------------------------------------------------
# Stage 3: Final MNL (Dual)
# -------------------------------------------------------------------------
sample_data2.MNL_Dual <- mlogit(choice ~
                                  FS_1Y_log + FS_AB_log + Lease_Deal_CHG + Sale_List_CHG + SalePrice_CHG_CPI + FS_pred
                                | ResAll_C_1km_log + BF_A_1km + BUID_C_100m + BSTP_DIST + LU_COM + LU_IND + LU_RTL
                                + Air + Bramp + CaleMilton + CoreDurham + DT + Toronto_MidNorth + Missi + OakBurling + Out_York + Outlying_Durham + Toronto_East + Toronto_West + York_South
                                + Y_2015 + Y_2016 + Y_2017 + Y_2018 + Y_2019 + Y_2020 + Y_2021 + Y_2022
                                | 0, sample_data2_final,
                                R = 50, halton = NA, panel = FALSE)

summary(sample_data2.MNL_Dual)

# Save the model summary (Table 3)
capture.output(
  summary(sample_data2.MNL_Dual),
  file = file.path(output_dir, "stage3_MNL_summary.txt")
)
