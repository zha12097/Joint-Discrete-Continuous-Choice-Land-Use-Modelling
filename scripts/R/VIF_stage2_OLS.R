# ==============================================================================
# VIF checks for the Stage 2 floorspace regressions             (Appendix Table A.2)
#
# Runs main_model_and_simulation.R up to the Stage 2 OLS models and computes
# variance inflation factors.
#
# Input : data/model_input.csv, data/development_probability.csv (via the main model)
# Output: outputs/VIF_stage2_OLS/
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(car)
})

# Paths are relative to the repository root; run this script from there.
main_model_script <- file.path("scripts", "R", "main_model_and_simulation.R")
output_dir        <- file.path("outputs", "VIF_stage2_OLS")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Run the main model until the Stage 2 OLS models exist
model_env <- new.env(parent = globalenv())
for (expr in parse(main_model_script, keep.source = FALSE)) {
  eval(expr, envir = model_env)
  if (exists("fs_models", envir = model_env, inherits = FALSE)) break
}

ols_models <- list(
  Retail     = model_env$fs_models$retail,
  Office     = model_env$fs_models$office,
  Industrial = model_env$fs_models$industrial,
  Mixed      = model_env$fs_models$mixed
)

vif_tables <- lapply(names(ols_models), function(label) {
  vif_tbl <- enframe(vif(ols_models[[label]]), name = "Variable", value = "VIF") %>%
    filter(Variable != "Bias_Factor")
  write_csv(vif_tbl, file.path(output_dir, paste0("VIF_", label, ".csv")))
  vif_tbl %>% rename(!!label := VIF)
})

# Combined table: one column per development type
vif_combined <- Reduce(function(x, y) full_join(x, y, by = "Variable"), vif_tables)
write_csv(vif_combined, file.path(output_dir, "VIF_all_types.csv"))

print(vif_combined, n = Inf)
