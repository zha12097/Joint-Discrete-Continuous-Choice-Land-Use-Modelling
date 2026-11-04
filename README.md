# Rethinking the Discrete-Continuous Choice Problem by Uncovering Asymmetry in High-Resolution Urban Modelling

Code and data for:

> Zhang, J., & Miller, E. J. *Rethinking the Discrete-Continuous Choice Problem by Uncovering Asymmetry in High-Resolution Urban Modelling.* Submitted to *Geographical Analysis*.

## Data (`data/`)

| File | Description |
|---|---|
| `development_probability.csv` | Tier 1 (XGBoost) development probability per parcel-year: `GTHA_ID`, `Year`, `proba_yearly` |
| `parcel_centroids/` | Parcel centroid shapefile (`GTHA_ID`) used for the spatial autocorrelation tests |
| `model_input_example.csv` | **Synthetic** example showing the format of the model input (parcel-year, 2015–2023). `GTHA_ID`, `Year`, year dummies, `CPI`, `CDNAME`, `CSDNAME`, `POPDEN2021` and `income_noLow_per` come from public sources; the other columns are randomly generated, and parcel-years are drawn at random. Columns derived from CoStar data (development outcomes, floorspace, market conditions, market areas and distances to commercial clusters) are omitted. The full data may be requested from the authors, but access depends on the data provider's approval. |

## Scripts (`scripts/`)

| Script | Description |
|---|---|
| `R/generic_FS_model.R` | Multi-stage model with a generic expected-floorspace parameter |
| `R/final_MNL_four_base_alternatives.R` | Final-stage MNL estimated under each of the four base alternatives |
| `R/main_model_and_simulation.R` | Main multi-stage MNL–OLS model and Monte Carlo simulation of development outcomes |
| `R/VIF_stage2_OLS.R` | Multicollinearity (VIF) checks for the floorspace regressions |
| `R/spatial_autocorrelation_tests.R` | Moran's I tests on the OLS and MNL residuals |
| `R/zoning_split_and_bootstrap.R` | Zoning-group diagnostics and cluster bootstrap standard errors |
| `python/fig8_coefficient_heatmap.py` | Heatmap of coefficients across base alternatives |
| `python/fig9_coefficient_dotplot.py` | Dot plot of coefficients across base alternatives |
| `python/figA3_annual_temporal_indicators.py` | Heatmap of annual year-dummy coefficients across base alternatives |

## License

MIT

## Acknowledgement

Claude Opus 5.5 (Anthropic) was used to tidy and restructure the code in this repository. The models, analyses and results are the authors' own.
