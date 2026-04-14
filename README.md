# Parcel-Level Land Use Supply Microsimulation Framework (High Data Quality Version)

A modular, replicable framework for jointly modelling the **type** and **floorspace** of commercial land use supply at the **parcel level** in large metropolitan regions. Developed and validated in Canada's Greater Toronto and Hamilton Area (GTHA), but designed for transferability to any jurisdiction with formal zoning systems.

> **Paper citation:** Zhang, J., Miller, E.J. *Rethinking the Discrete-Continuous Choice Problem by Uncovering Asymmetry in High-Resolution Urban Modelling.* Submitted to *Geographical Analysis*.
>
> **Thesis citation:** Zhang, J. (2026). *Decoding Urban Evolution: A Parcel-Level Blueprint for the ILUTE 2.0 Land Use Module.* Doctoral thesis, University of Toronto. ProQuest Dissertations Publishing.

---

## Overview

This repository implements the **High Data Quality (Version 2)** of the conceptual framework described in the associated paper. Unlike the companion [Version 1 (Low Data Quality)](https://github.com/zha12097/Chapter5-Supplymentary-Files.git) repository, which models only the discrete choice of "what type to build," this version tackles the full **joint discrete-continuous choice (DCC) problem**: simultaneously determining the **building type** (Retail, Industrial, Office, Mixed) and the **floorspace quantity** (continuous, in sqft).

### What Makes Version 2 Different from Version 1?

| Dimension | Version 1 (Low Data Quality) | Version 2 (High Data Quality) |
|---|---|---|
| **Supply measure** | Building counts (proxy) | Continuous floorspace (sqft) |
| **Econometric core** | Panel-data mixed logit (single-stage) | Multi-stage MNL + OLS with selectivity bias correction (4 stages) |
| **Choice set** | 5 alternatives (incl. "No Development") | 4 active alternatives (develop/not-develop handled by Tier 1 classifier) |
| **Tier 1 decision** | Embedded as "A_N_O" alternative | Separate XGBoost binary classifier |
| **Selectivity bias** | Not applicable | Explicitly corrected via Berkowitz et al. (1990) bias factor (Ε_k) |
| **Base alternative rotation** | Not applicable (A_N_O is reference) | Model estimated 4× with each type as reference for robustness |

### Core Design Principles

| Principle | Description |
|---|---|
| **Spatial Fidelity** | Land parcels as the fundamental simulation unit (~1.4 M in the GTHA) |
| **Policy Awareness** | Real zoning by-law permissions constrain each parcel's feasible choice set |
| **Behavioural Integrity** | Joint discrete-continuous econometric model decodes developer decision-making |
| **Selectivity Bias Correction** | Accounts for structurally missing floorspace data on unchosen alternatives |

### Platform Agnosticism

**Every stage in this framework is platform-agnostic.** The pseudo-code modules are written in a Python-like style for readability, but each stage can be implemented in any language, GIS platform, or toolchain. In the GTHA case study:

- **Spatial data processing** (Stages 1–5) was performed in **ArcGIS Pro**, **GeoPandas**, and **GeoPy**
- **Tier 1 classification** was implemented in **XGBoost** (Python)
- **Saturation classification** (Stage 6) was implemented in **TensorFlow/Keras** (Python)
- **Market disaggregation** (Stage 7) was conducted in **ArcGIS Pro** using the Field Calculator and spatial joins
- **Core econometric estimation** (Stage 8) was executed in **R** using the `mlogit` package
- **Spatial autocorrelation tests** (Stage 9) were executed in **R** using the `spdep` package

Equivalent results can be achieved using QGIS, PostGIS, Stata, Julia, MATLAB, or any other tools.

---

## Repository Structure

```
├── README.md                              # This file
├── LICENSE
├── config/
│   └── config.yaml                        # All user-configurable parameters
├── src/
│   ├── 00_pipeline_runner.py              # Master orchestrator (pseudo-code)
│   ├── 01_data_acquisition.py             # Stage 1: Raw data collection
│   ├── 02_zoning_landscape.py             # Stage 2: Digital zoning landscape
│   ├── 03_data_cleaning.py                # Stage 3: Cleaning and geocoding
│   ├── 04_spatiotemporal_panel.py         # Stage 4: Panel database (floorspace-based)
│   ├── 05_feature_engineering.py          # Stage 5: Attribute generation (floorspace-based)
│   ├── 06_availability_filtering.py       # Stage 6: Regulatory + saturation filters
│   ├── 07_market_disaggregation.py        # Stage 7: Spatial interaction downscaling
│   ├── 08_core_model.R                    # Stage 8: 4-stage MNL+OLS joint estimation (EXECUTABLE)
│   ├── 09_spatial_autocorrelation.R       # Stage 9: Moran's I residual tests (EXECUTABLE)
│   └── 10_validation.py                   # Stage 10: Simulation and validation
├── examples/
│   ├── tier1_xgboost_classifier.py        # Example: XGBoost binary develop/not-develop classifier
│   └── alternative_specific_analysis.py   # Example: Heatmap/dot-plot visualisation of results
├── data/
│   └── parcel_centroids/                  # Parcel centroid shapefile for spatial autocorrelation
├── docs/
│   └── workflow.md                        # Mathematical formulation and workflow documentation
└── requirements.txt                       # Python/R dependencies
```

### What Is Real Code vs. Pseudo-Code?

| Script | Status | Language |
|---|---|---|
| `src/08_core_model.R` | **Executable** — the 4-stage MNL+OLS joint estimation engine with simulation | R |
| `src/09_spatial_autocorrelation.R` | **Executable** — Moran's I tests on model residuals | R |
| `examples/tier1_xgboost_classifier.py` | **Example** — reference implementation for Tier 1 binary classifier; adapt to your data | Python |
| `examples/alternative_specific_analysis.py` | **Example** — visualisation of alternative-specific parameter estimates | Python |
| All other `src/*.py` files | **Pseudo-code** — detailed blueprints documenting each stage's logic | Python-like |

---

## Pipeline Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    STAGE 1: DATA ACQUISITION                        │
│  Collect: parcels, buildings+floorspace, market data, POIs, etc.    │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                STAGE 2: DIGITAL ZONING LANDSCAPE                    │
│  Extract ZBL permissions → Unified taxonomy → ML imputation         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│              STAGE 3: DATA CLEANING & GEOCODING                     │
│  Validate geometries → Geocode addresses → Assign to parcels        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│       STAGE 4: SPATIO-TEMPORAL PANEL (FLOORSPACE-BASED)             │
│  Expand parcels × years → Sum floorspace → Define project units     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│          STAGE 5: FEATURE ENGINEERING (FLOORSPACE-BASED)            │
│  Floorspace lags → Cumulative stock → Market signals → Site metrics │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│              STAGE 6: AVAILABILITY FILTERING                        │
│  Zoning filter → Saturation classifier → Active agent pool          │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│            STAGE 7: MARKET DATA DISAGGREGATION                      │
│  Spatial interaction model: meso-level → parcel-level market vars    │
│  (See Appendix of the paper for the mathematical formulation)       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│    TIER 1: BINARY DEVELOP / NOT-DEVELOP CLASSIFIER                  │
│  XGBoost: determines which parcels are active in each timestep      │
│  (See examples/tier1_xgboost_classifier.py)                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│     STAGE 8: 4-STAGE MNL+OLS JOINT ESTIMATION  [EXECUTABLE]        │
│  Stage 1: Initial MNL → Stage 2: Choice probabilities →             │
│  Stage 3: OLS with selectivity bias correction →                    │
│  Stage 4: Final MNL with predicted floorspace                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│     STAGE 9: SPATIAL AUTOCORRELATION TESTS  [EXECUTABLE]            │
│  Moran's I on OLS + MNL residuals using parcel centroids            │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│             STAGE 10: VALIDATION & SIMULATION                       │
│  McFadden R² → Market share trajectories → Monte Carlo simulation   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Requirements

> **Note:** Primary datasets used in the GTHA case study are proprietary and cannot be redistributed. Please contact the corresponding author for data access. Other data sources are detailed in the paper's Table 2 and are mostly accessible to researchers registered within public universities in Ontario, Canada.

### Minimum Inputs

| Dataset | Key Fields | Source (GTHA example) |
|---|---|---|
| Land parcels | geometry, unique ID, area | Provincial assessment parcels |
| Building inventory | address, year built, LU type, **floorspace (sqft)**, lifecycle status | CoStar Group or municipal rolls |
| Zoning by-laws | zone code, permitted uses per parcel | Municipal open data / ZBL documents |
| Market indicators | rent, sale price, cap rate, vacancy, operating cost | CoStar Group or equivalent |
| Points of interest | type, coordinates | DMTI Spatial / OpenStreetMap |
| Transport network | roads, bus stops, rail stations, routes | Municipal open data / GTFS |
| Census variables | population, employment, income, vehicle ownership | Statistics Canada / national census |
| Satellite imagery | high-resolution, multi-year | Google Earth / Esri World Imagery |

The critical difference from Version 1 is the **floorspace** field in the building inventory — this is what enables the joint discrete-continuous model.

---

## Quick Start

### 1. Review the configuration
```bash
# Edit config/config.yaml to set paths, study area bounds,
# temporal range, buffer distances, and model parameters.
```

### 2. Implement the data pipeline
```
# Each stage is documented as a standalone, annotated pseudo-code module.
# These are NOT directly executable — they serve as detailed blueprints.
# Implement each stage using your preferred tools (Python, R, ArcGIS, QGIS, etc.)
```

### 3. Run the Tier 1 classifier
```
# Adapt examples/tier1_xgboost_classifier.py for your data.
# This produces the develop/not-develop probabilities needed by Stage 8.
```

### 4. Run the joint estimation model (executable R code)
```r
# In R (requires: mlogit, dfidx, dplyr, tidyr, ggplot2, readr, tibble, purrr)
Rscript src/08_core_model.R
```

### 5. Run spatial autocorrelation tests (executable R code)
```r
# In R (requires: sf, spdep, dplyr, readr)
# Note: requires Stage 8 outputs to be in the R environment
Rscript src/09_spatial_autocorrelation.R
```

### 6. Validate
```
# Follow the logic in src/10_validation.py using your preferred tools.
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgements

This framework was developed as part of a doctoral dissertation at the University of Toronto. The authors gratefully acknowledge CoStar Group for providing proprietary commercial real estate data, DMTI Spatial for business establishment records, and the municipalities of the GTHA for sharing zoning by-law data.

---

## Disclosure

Code in this repository was cleaned and reorganised with the assistance of Claude AI (Anthropic) and ChatGPT (OpenAI).
