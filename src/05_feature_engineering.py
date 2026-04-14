"""
================================================================================
Stage 5: Feature Engineering — Version 2 (High Data Quality)
================================================================================
PSEUDO-CODE — documents the generation of all candidate explanatory variables,
using FLOORSPACE as the supply measure instead of building counts.

Purpose:
    Derive the full matrix of candidate attributes. The critical difference
    from Version 1 is that all supply-related attributes are re-computed
    using continuous floorspace volumes rather than discrete building counts.

    VERSION 2 DIFFERENCE: Variables like "lagged supply" and "cumulative
    stock" now reflect sqft of built space, not number of buildings.
    This ensures dimensional consistency with the OLS dependent variable.

Reference:
    See Section 3, Table 2 of the associated paper (Geographical Analysis).
    All spatial computations are platform-agnostic.
================================================================================
"""


def run(config):

    # ══════════════════════════════════════════════════════════════════════
    # SUPPLY VARIABLES — NOW FLOORSPACE-BASED
    # ══════════════════════════════════════════════════════════════════════
    #
    # Version 1 used:  C_1Y = count of buildings of type j built last year
    # Version 2 uses:  FS_1Y = total floorspace (sqft) of type j built last year
    #
    # Both are log-transformed: FS_1Y_log = log(FS_1Y + 0.01)
    #
    # Similarly:
    #   FS_AB     = cumulative floorspace stock built before 2015
    #   FS_AB_log = log(FS_AB + 0.01)
    #
    # These enter the MNL as GENERIC coefficients (same across all types).

    # ══════════════════════════════════════════════════════════════════════
    # OLS-SPECIFIC VARIABLES (Stage 3 of the core model)
    # ══════════════════════════════════════════════════════════════════════
    #
    # The OLS regression for floorspace uses a distinct set of variables
    # (X_k|i in Equation 6.2) including:
    #
    #   Cap_Rate_CHG          : % change in capitalisation rate (market signal)
    #   ParcelArea            : Parcel area (log-transformed)
    #   BUID_A_100m           : Building footprint area within 100m
    #   OS_A_1km              : Open space area within 1km
    #   SLP_MEAN_1km          : Mean terrain slope within 1km
    #   HWY_L_1km             : Highway length within 1km
    #   TRAN_STP_C_100m       : Transit stop count within 100m
    #   MJLC_RDS_L_100m       : Major road length within 100m
    #   OFC_DIST              : Distance to nearest office cluster
    #   WETL_DIST             : Distance to nearest wetland
    #   income_noLow_per      : % of households not classified as low income
    #   POPDEN2021            : Population density (rescaled: /1e6)
    #   Bias_Factor           : Selectivity bias correction term (from Stage 2)
    #
    # Note: The Bias_Factor is NOT computed here — it is derived from the
    # Stage 1 MNL choice probabilities inside src/08_core_model.R.

    # ══════════════════════════════════════════════════════════════════════
    # MNL-SPECIFIC VARIABLES (shared with Version 1, plus floorspace)
    # ══════════════════════════════════════════════════════════════════════
    #
    # Generic (alternative-varying):
    #   FS_1Y_log, FS_AB_log, Lease_Deal_CHG, Sale_List_CHG, SalePrice_CHG_CPI
    #
    # Alternative-specific (location-varying):
    #   FS_pred               : Predicted floorspace from Stage 3 (V2 ONLY)
    #   ResAll_C_1km_log      : Residential building count within 1km (log)
    #   BF_A_1km              : Building footprint area within 1km (/1e4)
    #   BUID_C_100m           : Building count within 100m
    #   BSTP_DIST             : Distance to nearest bus stop
    #   LU_COM, LU_IND, LU_RTL: Dominant LU zone indicators
    #   Regional dummies, Year dummies
    #   ParcelArea, BUID_A_100m, OS_A_1km, SLP_MEAN_1km, HWY_L_1km,
    #   TRAN_STP_C_100m, OFC_DIST, RTL_DIST, WETL_DIST,
    #   income_noLow_per, POPDEN2021, NBSTP_DIST

    # ══════════════════════════════════════════════════════════════════════
    # RESCALING
    # ══════════════════════════════════════════════════════════════════════
    #
    #   BF_A_1km         /= 1e4
    #   EPOI_1km         /= 1e4
    #   POPDEN2021       /= 1e6
    #   ResAll_C_1km     → log(ResAll_C_1km + 0.01)

    pass
