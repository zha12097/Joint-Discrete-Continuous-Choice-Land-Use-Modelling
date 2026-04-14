suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(spdep)
  library(readr)
})

options(width = 200)

# Disclosure: This script was cleaned and reorganised with assistance from
# ChatGPT (OpenAI) and Claude (Anthropic).
#
# This script performs Moran's I spatial autocorrelation tests on the
# residuals of both the OLS (floorspace) and MNL (type choice) models
# to verify the absence of spatial clustering in model errors.
#
# Reference: See Appendix of the associated paper (Geographical Analysis).

# ------------------------------------------------------------------------------
# Inputs
# ------------------------------------------------------------------------------

centroid_shp_path <- ".../parcel_centroids.shp"
output_dir <- "Output_Path"

distance_band_km <- 10
distance_band_m  <- distance_band_km * 1000

min_n_default <- 30
min_n_mixed   <- 10
n_perm <- 999
set.seed(123)

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

file_stub <- paste0("distband_", distance_band_km, "km_1nn_fallback")

# ------------------------------------------------------------------------------
# Required objects
# ------------------------------------------------------------------------------

required_objects <- c(
  "OLS.retail", "OLS.office", "OLS.industrial", "OLS.mixed",
  "retail_FS", "office_FS", "industrial_FS", "A_Mixed_FS",
  "sample_data2.MNL_Dual", "sample_data2_final_df"
)

missing_objects <- required_objects[!vapply(required_objects, exists, logical(1))]
if (length(missing_objects) > 0) {
  stop("Missing required objects: ", paste(missing_objects, collapse = ", "))
}

# ------------------------------------------------------------------------------
# Centroids
# ------------------------------------------------------------------------------

centroids_sf <- st_read(centroid_shp_path, quiet = TRUE)

if (!("GTHA_ID" %in% names(centroids_sf))) {
  stop("The centroid shapefile does not contain a 'GTHA_ID' field.")
}

centroids_sf <- centroids_sf %>%
  mutate(GTHA_ID = as.character(GTHA_ID)) %>%
  select(GTHA_ID, geometry)

if (is.na(st_crs(centroids_sf))) {
  warning("The centroid shapefile has no CRS. Distance calculations may be unreliable.")
} else if (st_is_longlat(centroids_sf)) {
  message("Centroids are in geographic coordinates. Reprojecting to EPSG:26917 for distance-based weights.")
  centroids_sf <- st_transform(centroids_sf, 26917)
}

# ------------------------------------------------------------------------------
# Attach OLS residuals
# ------------------------------------------------------------------------------

retail_FS$resid_ols     <- resid(OLS.retail)
office_FS$resid_ols     <- resid(OLS.office)
industrial_FS$resid_ols <- resid(OLS.industrial)
A_Mixed_FS$resid_ols    <- resid(OLS.mixed)

retail_FS$GTHA_ID     <- as.character(retail_FS$GTHA_ID)
office_FS$GTHA_ID     <- as.character(office_FS$GTHA_ID)
industrial_FS$GTHA_ID <- as.character(industrial_FS$GTHA_ID)
A_Mixed_FS$GTHA_ID    <- as.character(A_Mixed_FS$GTHA_ID)

# ------------------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------------------

join_centroids <- function(df, centroids) {
  df %>%
    inner_join(centroids, by = "GTHA_ID") %>%
    st_as_sf()
}

extract_point_coords <- function(x) {
  if (nrow(x) == 0) {
    return(list(data = x, coords = matrix(numeric(0), ncol = 2)))
  }
  
  geom <- st_geometry(x)
  keep <- !st_is_empty(geom)
  
  if (!all(keep)) {
    x <- x[keep, , drop = FALSE]
    geom <- st_geometry(x)
  }
  
  if (nrow(x) == 0) {
    return(list(data = x, coords = matrix(numeric(0), ncol = 2)))
  }
  
  coords <- suppressWarnings(st_coordinates(geom))
  
  valid_shape <- is.matrix(coords) &&
    ncol(coords) >= 2 &&
    nrow(coords) == length(geom)
  
  if (!valid_shape) {
    coords <- do.call(rbind, lapply(geom, function(g) {
      if (isTRUE(st_is_empty(g))) return(c(NA_real_, NA_real_))
      tmp <- suppressWarnings(st_coordinates(g))
      if (is.matrix(tmp) && nrow(tmp) >= 1) return(as.numeric(tmp[1, 1:2]))
      c(NA_real_, NA_real_)
    }))
  } else {
    coords <- coords[, 1:2, drop = FALSE]
  }
  
  coords <- as.matrix(coords)
  storage.mode(coords) <- "double"
  
  keep_xy <- is.finite(coords[, 1]) & is.finite(coords[, 2])
  
  list(
    data = x[keep_xy, , drop = FALSE],
    coords = coords[keep_xy, , drop = FALSE]
  )
}

build_nb_with_fallback <- function(coords, dmax, region_id = NULL, symmetric = TRUE) {
  coords <- as.matrix(coords)
  storage.mode(coords) <- "double"
  n <- nrow(coords)
  
  if (n <= 1) {
    nb <- replicate(n, integer(0), simplify = FALSE)
    class(nb) <- "nb"
    if (!is.null(region_id)) attr(nb, "region.id") <- region_id
    
    return(list(
      nb = nb,
      isolates_before = n,
      isolates_after = n,
      isolate_share_before = ifelse(n == 0, NA_real_, 1),
      isolate_share_after = ifelse(n == 0, NA_real_, 1),
      links_before = 0L,
      links_after = 0L,
      n_components = NA_integer_
    ))
  }
  
  dmat <- as.matrix(dist(coords))
  diag(dmat) <- Inf
  
  nb_dist <- vector("list", n)
  for (i in seq_len(n)) {
    nb_dist[[i]] <- which(dmat[i, ] <= dmax)
  }
  
  class(nb_dist) <- "nb"
  if (!is.null(region_id)) attr(nb_dist, "region.id") <- region_id
  
  isolates <- which(lengths(nb_dist) == 0)
  
  nb_final <- nb_dist
  if (length(isolates) > 0) {
    for (i in isolates) {
      j <- which.min(dmat[i, ])
      if (length(j) == 1 && is.finite(dmat[i, j])) {
        nb_final[[i]] <- unique(c(nb_final[[i]], j))
        if (symmetric) {
          nb_final[[j]] <- unique(c(nb_final[[j]], i))
        }
      }
    }
  }
  
  class(nb_final) <- "nb"
  if (!is.null(region_id)) attr(nb_final, "region.id") <- region_id
  if (symmetric) nb_final <- make.sym.nb(nb_final)
  
  isolates_after <- sum(lengths(nb_final) == 0)
  
  list(
    nb = nb_final,
    isolates_before = length(isolates),
    isolates_after = isolates_after,
    isolate_share_before = length(isolates) / n,
    isolate_share_after = isolates_after / n,
    links_before = sum(lengths(nb_dist)),
    links_after = sum(lengths(nb_final)),
    n_components = tryCatch(n.comp.nb(nb_final)$nc, error = function(e) NA_integer_)
  )
}

run_moran_test <- function(values, lw, year_value, n_obs, meta = list(), n_perm = 999) {
  out <- tryCatch({
    mt <- moran.test(values, lw, zero.policy = TRUE)
    mc <- moran.mc(values, lw, nsim = n_perm, zero.policy = TRUE)
    
    data.frame(
      Year = year_value,
      n = n_obs,
      moran_i = unname(mt$estimate[["Moran I statistic"]]),
      p_asym = mt$p.value,
      p_perm = mc$p.value,
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    data.frame(
      Year = year_value,
      n = n_obs,
      moran_i = NA_real_,
      p_asym = NA_real_,
      p_perm = NA_real_,
      error_msg = e$message,
      stringsAsFactors = FALSE
    )
  })
  
  if (length(meta) > 0) {
    for (nm in names(meta)) out[[nm]] <- meta[[nm]]
  }
  
  out
}

prepare_year_data <- function(sf_data, year_value, resid_col, id_col = "GTHA_ID", year_col = "Year") {
  tmp <- sf_data %>%
    filter(.data[[year_col]] == year_value) %>%
    group_by(.data[[id_col]]) %>%
    summarise(
      Year = first(.data[[year_col]]),
      resid = mean(.data[[resid_col]], na.rm = TRUE),
      geometry = first(geometry),
      .groups = "drop"
    ) %>%
    st_as_sf() %>%
    mutate(resid = as.numeric(resid)) %>%
    filter(is.finite(resid))
  
  extract_point_coords(tmp)
}

prepare_pooled_data <- function(sf_data, resid_col, id_col = "GTHA_ID") {
  tmp <- sf_data %>%
    group_by(.data[[id_col]]) %>%
    summarise(
      resid = mean(.data[[resid_col]], na.rm = TRUE),
      geometry = first(geometry),
      .groups = "drop"
    ) %>%
    st_as_sf() %>%
    mutate(resid = as.numeric(resid)) %>%
    filter(is.finite(resid))
  
  extract_point_coords(tmp)
}

run_moran_suite <- function(sf_data,
                            sector_name,
                            resid_col,
                            dmax,
                            min_n,
                            n_perm,
                            id_col = "GTHA_ID",
                            year_col = "Year") {
  
  years <- sort(unique(sf_data[[year_col]]))
  results <- list()
  
  skip_log <- data.frame(
    Sector = character(),
    Residual = character(),
    Scope = character(),
    Year = integer(),
    Reason = character(),
    stringsAsFactors = FALSE
  )
  
  for (yy in years) {
    prep <- prepare_year_data(sf_data, yy, resid_col, id_col, year_col)
    tmp <- prep$data
    coords <- prep$coords
    
    if (nrow(tmp) < min_n) {
      skip_log <- rbind(skip_log, data.frame(
        Sector = sector_name,
        Residual = resid_col,
        Scope = "year",
        Year = yy,
        Reason = paste0("Too few observations after filtering (n < ", min_n, ")."),
        stringsAsFactors = FALSE
      ))
      next
    }
    
    if (sd(tmp$resid) == 0) {
      skip_log <- rbind(skip_log, data.frame(
        Sector = sector_name,
        Residual = resid_col,
        Scope = "year",
        Year = yy,
        Reason = "Residuals have zero variance.",
        stringsAsFactors = FALSE
      ))
      next
    }
    
    nb_info <- build_nb_with_fallback(
      coords = coords,
      dmax = dmax,
      region_id = tmp[[id_col]],
      symmetric = TRUE
    )
    
    if (sum(lengths(nb_info$nb)) == 0) {
      skip_log <- rbind(skip_log, data.frame(
        Sector = sector_name,
        Residual = resid_col,
        Scope = "year",
        Year = yy,
        Reason = "No neighbour links were created.",
        stringsAsFactors = FALSE
      ))
      next
    }
    
    lw <- nb2listw(nb_info$nb, style = "W", zero.policy = TRUE)
    
    results[[length(results) + 1]] <- run_moran_test(
      values = tmp$resid,
      lw = lw,
      year_value = yy,
      n_obs = nrow(tmp),
      meta = list(
        distance_band_km = dmax / 1000,
        distance_band_m = dmax,
        isolates_before = nb_info$isolates_before,
        isolates_after = nb_info$isolates_after,
        isolate_share_before = nb_info$isolate_share_before,
        isolate_share_after = nb_info$isolate_share_after,
        links_before = nb_info$links_before,
        links_after = nb_info$links_after,
        n_components = nb_info$n_components
      ),
      n_perm = n_perm
    )
  }
  
  prep_pool <- prepare_pooled_data(sf_data, resid_col, id_col)
  pooled <- prep_pool$data
  pooled_coords <- prep_pool$coords
  
  if (nrow(pooled) < min_n) {
    skip_log <- rbind(skip_log, data.frame(
      Sector = sector_name,
      Residual = resid_col,
      Scope = "pooled",
      Year = NA_integer_,
      Reason = paste0("Too few observations after filtering (n < ", min_n, ")."),
      stringsAsFactors = FALSE
    ))
  } else if (sd(pooled$resid) == 0) {
    skip_log <- rbind(skip_log, data.frame(
      Sector = sector_name,
      Residual = resid_col,
      Scope = "pooled",
      Year = NA_integer_,
      Reason = "Residuals have zero variance.",
      stringsAsFactors = FALSE
    ))
  } else {
    nb_info <- build_nb_with_fallback(
      coords = pooled_coords,
      dmax = dmax,
      region_id = pooled[[id_col]],
      symmetric = TRUE
    )
    
    if (sum(lengths(nb_info$nb)) == 0) {
      skip_log <- rbind(skip_log, data.frame(
        Sector = sector_name,
        Residual = resid_col,
        Scope = "pooled",
        Year = NA_integer_,
        Reason = "No neighbour links were created.",
        stringsAsFactors = FALSE
      ))
    } else {
      lw <- nb2listw(nb_info$nb, style = "W", zero.policy = TRUE)
      
      pooled_result <- run_moran_test(
        values = pooled$resid,
        lw = lw,
        year_value = NA_integer_,
        n_obs = nrow(pooled),
        meta = list(
          distance_band_km = dmax / 1000,
          distance_band_m = dmax,
          isolates_before = nb_info$isolates_before,
          isolates_after = nb_info$isolates_after,
          isolate_share_before = nb_info$isolate_share_before,
          isolate_share_after = nb_info$isolate_share_after,
          links_before = nb_info$links_before,
          links_after = nb_info$links_after,
          n_components = nb_info$n_components
        ),
        n_perm = n_perm
      )
      
      results[[length(results) + 1]] <- pooled_result
    }
  }
  
  result_tbl <- bind_rows(results) %>%
    mutate(
      Sector = sector_name,
      Residual = resid_col,
      Scope = ifelse(is.na(Year), "pooled", "year")
    ) %>%
    relocate(Sector, Residual, Scope, Year, n)
  
  list(results = result_tbl, skip_log = skip_log)
}

summarise_isolates <- function(x) {
  x %>%
    group_by(Sector, Scope) %>%
    summarise(
      rows = n(),
      mean_isolate_share_before = mean(isolate_share_before, na.rm = TRUE),
      mean_isolate_share_after = mean(isolate_share_after, na.rm = TRUE),
      max_isolate_share_before = max(isolate_share_before, na.rm = TRUE),
      max_isolate_share_after = max(isolate_share_after, na.rm = TRUE),
      .groups = "drop"
    )
}

# ------------------------------------------------------------------------------
# OLS residual diagnostics
# ------------------------------------------------------------------------------

sf_retail     <- join_centroids(retail_FS, centroids_sf)
sf_office     <- join_centroids(office_FS, centroids_sf)
sf_industrial <- join_centroids(industrial_FS, centroids_sf)
sf_mixed      <- join_centroids(A_Mixed_FS, centroids_sf)

ols_runs <- list(
  Retail = run_moran_suite(sf_retail, "OLS_Retail", "resid_ols", distance_band_m, min_n_default, n_perm),
  Office = run_moran_suite(sf_office, "OLS_Office", "resid_ols", distance_band_m, min_n_default, n_perm),
  Industrial = run_moran_suite(sf_industrial, "OLS_Industrial", "resid_ols", distance_band_m, min_n_default, n_perm),
  A_Mixed = run_moran_suite(sf_mixed, "OLS_A_Mixed", "resid_ols", distance_band_m, min_n_mixed, n_perm)
)

ols_results <- bind_rows(lapply(ols_runs, `[[`, "results"))
ols_skip_log <- bind_rows(lapply(ols_runs, `[[`, "skip_log"))
ols_isolate_summary <- summarise_isolates(ols_results)

cat("\nOLS Moran's I results\n")
print(ols_results)

cat("\nOLS skip log\n")
print(ols_skip_log)

cat("\nOLS isolate summary\n")
print(ols_isolate_summary)

# ------------------------------------------------------------------------------
# MNL generalised residual diagnostics
# ------------------------------------------------------------------------------

choice_meta <- sample_data2_final_df %>%
  select(choiceid, GTHA_ID, Year, choice, Dev_Type) %>%
  mutate(
    choiceid = as.integer(choiceid),
    GTHA_ID = as.character(GTHA_ID)
  )

chosen_alt_df <- choice_meta %>%
  filter(choice == TRUE) %>%
  select(choiceid, GTHA_ID, Year, chosen_alt = Dev_Type) %>%
  distinct(choiceid, .keep_all = TRUE)

probs <- fitted(sample_data2.MNL_Dual, type = "probabilities")
alts <- colnames(probs)

choice_ids <- unique(as.integer(sample_data2_final_df$choiceid))
if (length(choice_ids) != nrow(probs)) {
  if (!is.null(rownames(probs))) {
    choice_ids <- as.integer(rownames(probs))
  } else {
    stop("Could not align fitted probabilities with choice IDs.")
  }
}

chosen_vec <- chosen_alt_df$chosen_alt[match(choice_ids, chosen_alt_df$choiceid)]
if (any(is.na(chosen_vec))) {
  stop("Some choice IDs do not have an observed chosen alternative.")
}

Y <- matrix(0, nrow = length(choice_ids), ncol = length(alts))
colnames(Y) <- alts

for (j in seq_along(alts)) {
  Y[, j] <- as.integer(chosen_vec == alts[j])
}

generalised_residuals <- Y - probs
colnames(generalised_residuals) <- paste0("gr_", alts)

mnl_resid_df <- data.frame(
  choiceid = as.integer(choice_ids),
  generalised_residuals,
  stringsAsFactors = FALSE
) %>%
  left_join(
    chosen_alt_df %>% select(choiceid, GTHA_ID, Year),
    by = "choiceid"
  )

sf_mnl <- mnl_resid_df %>%
  inner_join(centroids_sf, by = "GTHA_ID") %>%
  st_as_sf()

mnl_runs <- lapply(alts, function(alt) {
  run_moran_suite(
    sf_data = sf_mnl,
    sector_name = paste0("MNL_", alt),
    resid_col = paste0("gr_", alt),
    dmax = distance_band_m,
    min_n = min_n_default,
    n_perm = n_perm
  )
})
names(mnl_runs) <- alts

mnl_results <- bind_rows(lapply(mnl_runs, `[[`, "results"))
mnl_skip_log <- bind_rows(lapply(mnl_runs, `[[`, "skip_log"))
mnl_isolate_summary <- summarise_isolates(mnl_results)

cat("\nMNL generalised residual Moran's I results\n")
print(mnl_results)

cat("\nMNL skip log\n")
print(mnl_skip_log)

cat("\nMNL isolate summary\n")
print(mnl_isolate_summary)

# ------------------------------------------------------------------------------
# Export
# ------------------------------------------------------------------------------

write_csv(
  ols_results,
  file.path(output_dir, paste0("ols_moran_year_and_pooled_", file_stub, ".csv"))
)

write_csv(
  ols_skip_log,
  file.path(output_dir, paste0("ols_skip_log_", file_stub, ".csv"))
)

write_csv(
  ols_isolate_summary,
  file.path(output_dir, paste0("ols_isolate_summary_", file_stub, ".csv"))
)

write_csv(
  mnl_results,
  file.path(output_dir, paste0("mnl_generalised_residual_moran_year_and_pooled_", file_stub, ".csv"))
)

write_csv(
  mnl_skip_log,
  file.path(output_dir, paste0("mnl_generalised_residual_skip_log_", file_stub, ".csv"))
)

write_csv(
  mnl_isolate_summary,
  file.path(output_dir, paste0("mnl_generalised_residual_isolate_summary_", file_stub, ".csv"))
)

capture.output(
  {
    cat("OLS Moran's I results\n")
    print(ols_results)
    
    cat("\nOLS skip log\n")
    print(ols_skip_log)
    
    cat("\nOLS isolate summary\n")
    print(ols_isolate_summary)
    
    cat("\nMNL generalised residual Moran's I results\n")
    print(mnl_results)
    
    cat("\nMNL skip log\n")
    print(mnl_skip_log)
    
    cat("\nMNL isolate summary\n")
    print(mnl_isolate_summary)
  },
  file = file.path(output_dir, paste0("spatial_autocorrelation_summary_", file_stub, ".txt"))
)

message("Spatial autocorrelation outputs saved to: ", output_dir)