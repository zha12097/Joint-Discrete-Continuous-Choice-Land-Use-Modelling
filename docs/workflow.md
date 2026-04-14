# Detailed Workflow Documentation — Version 2 (High Data Quality)

> See the associated paper for the complete theoretical derivation. The spatial
> interaction model formulation is provided in the paper's Appendix.
> All computations described here are platform-agnostic.

## Key Difference from Version 1

Version 1 models only the **discrete choice** of "what type to build" using building counts as a proxy for supply. Version 2 models the **joint discrete-continuous choice** of "what type AND how much floorspace to build," using a multi-stage econometric framework that explicitly corrects for selectivity bias.

---

## Mathematical Foundations

### The Joint Discrete-Continuous Framework

The model links a Multinomial Logit (MNL) for the type choice with an OLS regression for the floorspace choice:

**MNL (type choice):**
```
P(k|i) = exp(V_k|i + γ_k · F_k|i^log) / Σ_k' exp(V_k'|i + γ_k · F_k'|i^log)
```

**OLS (floorspace choice):**
```
log(F_k|i) = β_k · X_k|i + η_k
```

Where:
- `P(k|i)` = probability of parcel i choosing development type k
- `V_k|i` = systematic utility excluding floorspace effects
- `F_k|i^log` = log-transformed expected floorspace
- `γ_k` = alternative-specific floorspace parameter
- `β_k` = OLS coefficient vector for type k
- `X_k|i` = explanatory variables for floorspace
- `η_k` = error term

### The 4-Stage Estimation Procedure

**Stage 1 — Initial MNL:**
Substitute the OLS into the MNL to get a reduced-form specification:
```
P(k|i) = exp(α · Z_k|i + θ_k · X_k|i) / Σ_k' exp(α · Z_k'|i + θ_k · X_k'|i)
```
where `θ_k = γ_k · β_k`. Estimate this MNL to obtain initial coefficients.

**Stage 2 — Choice Probabilities:**
Compute fitted choice probabilities `P_k` for all types at all locations from the Stage 1 model.

**Stage 3 — OLS with Selectivity Bias Correction:**
Estimate type-specific OLS regressions for log(floorspace):
```
log(F_k|i) = β_k · X_k|i + λ_k · E_k
```
where `E_k` is the selectivity bias correction term (Berkowitz et al., 1990):
```
E[η_k] = λ_k · { Σ_{k'≠k} [ P_k' · log(P_k') / (1 - P_k') ] + log(P_k) }
```
This term corrects for the fact that floorspace is only observed for the chosen alternative.

**Stage 4 — Final MNL:**
Use the predicted floorspace `F_k|i^log` from Stage 3 to re-estimate the full MNL, now including floorspace as an explanatory variable with alternative-specific parameters.

### Utility Decomposition

```
V_k|i = α¹ · Z_k|i¹ + α_k² · Z_i²
```
- `α¹` = generic parameters (same across all types): market variables
- `α_k²` = alternative-specific parameters (differ by type): urban form, context

### Key Methodological Finding

The floorspace parameter `γ` must be specified as **alternative-specific**, not generic. When specified as generic, floorspace appears insignificant due to heterogeneous preferences cancelling out. When alternative-specific, it reveals that Industrial prefers larger floorplates while Retail and Office face diminishing returns at scale.

---

## Variable Classification for mlogit

### Generic Coefficients (before first `|`)
Alternative-specific variables receiving the **same** coefficient across types:
`FS_1Y_log`, `FS_AB_log`, `Lease_Deal_CHG`, `Sale_List_CHG`, `SalePrice_CHG_CPI`

### Alternative-Specific Coefficients (between first and second `|`)
Individual-specific variables receiving **different** coefficients per type:
`FS_pred`, `ResAll_C_1km_log`, `BF_A_1km`, `BUID_C_100m`, `BSTP_DIST`, `LU_COM`, `LU_IND`, `LU_RTL`, regional dummies, year dummies, parcel area, infrastructure metrics, demographic variables

### Base Alternative Rotation
The model is estimated 4 times with each type as reference. Results must show diagonal symmetry in the coefficient heatmap (sign flips, magnitude preserved) to confirm structural robustness.

---

## Key Findings Summary (GTHA Case Study)

| Finding | Evidence |
|---|---|
| Floorspace parameter must be alternative-specific | Generic γ: insignificant; alternative-specific γ: significant |
| Industrial = supply maximizer | Positive, significant preference for larger floorplates |
| Retail & Office = risk managers | Negative floorspace utility (diminishing returns at scale) |
| Retail & Industrial are spatial rivals | Opposing preferences for transit access, LU composition |
| Office & Mixed are spatially flexible | Lighter coefficients, narrower dispersion |
| Market momentum > market levels | % change in sale price, lease deals significant; absolute levels not |
| Model fit: McFadden R² = 0.62 | Exceeds the 0.2 threshold for excellent fit |
| Spatial autocorrelation: absent | Moran's I ≈ 0, not significant for both OLS and MNL residuals |
