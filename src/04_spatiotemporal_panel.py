"""
================================================================================
Stage 4: Spatio-Temporal Panel Construction — Version 2 (High Data Quality)
================================================================================
PSEUDO-CODE — documents how the parcel × year panel is assembled using
FLOORSPACE as the continuous supply measure.

Purpose:
    Expand the static parcel inventory into a longitudinal panel dataset where
    each row represents one parcel in one year, annotated with BOTH the
    development type (discrete) AND the total floorspace built (continuous).

    VERSION 2 DIFFERENCE: Instead of binary choice indicators only, each
    observation records the sum of new floorspace by LU type. The dependent
    variable for the OLS component is log(floorspace).

Reference:
    See Section 3 of the associated paper (Geographical Analysis).
    This stage can be implemented in any data manipulation tool.
================================================================================
"""


def run(config):

    # ══════════════════════════════════════════════════════════════════════
    # STEP 1: DEFINE "PROJECTS" WITH FLOORSPACE
    # ══════════════════════════════════════════════════════════════════════
    #
    # Unlike Version 1 (which groups buildings into projects by count),
    # Version 2 groups buildings AND sums their floorspace.
    #
    # For each parcel × year:
    #   - Sum floorspace by LU type
    #   - Classify the project:
    #     If only one commercial type has floorspace > 0 → single-use project
    #     If multiple commercial types have floorspace > 0 → Mixed-Use project
    #     If no commercial floorspace → not an active observation (handled by Tier 1)
    #
    # The total floorspace for the project is stored as Dev_FS.
    # Its log-transformed version (Dev_FS_log) becomes the continuous
    # dependent variable for the OLS regression in Stage 3 of the core model.

    # projects = (
    #     buildings
    #     .groupby(["parcel_id", "year_built", "lu_type"])
    #     .agg(floorspace=("floorspace_sqft", "sum"))
    #     .reset_index()
    # )
    #
    # def classify_and_sum(parcel_year_group):
    #     commercial = parcel_year_group[parcel_year_group["lu_type"].isin(
    #         ["Retail", "Industrial", "Office"])]
    #     if len(commercial) == 0:
    #         return {"type": None, "floorspace": 0}
    #     elif len(commercial["lu_type"].unique()) == 1:
    #         return {"type": commercial["lu_type"].iloc[0],
    #                 "floorspace": commercial["floorspace"].sum()}
    #     else:
    #         return {"type": "A_Mixed",
    #                 "floorspace": commercial["floorspace"].sum()}

    # ══════════════════════════════════════════════════════════════════════
    # STEP 2: EXPAND TO LONG FORMAT (PARCEL × YEAR × ALTERNATIVE)
    # ══════════════════════════════════════════════════════════════════════
    #
    # CRITICAL DIFFERENCE from Version 1:
    #   - The choice set has 4 alternatives: Retail, Industrial, Office, A_Mixed
    #   - There is NO "No Development" (A_N_O) alternative — that decision
    #     is handled by the separate Tier 1 binary classifier
    #   - Only parcels that ACTUALLY DEVELOPED appear in the estimation sample
    #   - Dev_FS (floorspace) is recorded for each alternative
    #     (positive for the chosen type, zero for unchosen types)
    #
    # The structurally missing floorspace for unchosen alternatives is the
    # root cause of selectivity bias — corrected in Stage 3 of the core model.

    # ══════════════════════════════════════════════════════════════════════
    # STEP 3: COMPUTE CUMULATIVE FLOORSPACE STOCK
    # ══════════════════════════════════════════════════════════════════════
    #
    # For each parcel, compute:
    #   FS_AB : Total commercial floorspace built on/near this parcel
    #           BEFORE the study period (pre-2015 baseline stock)
    #   FS_1Y : Floorspace of same-type projects built within 1km
    #           in the preceding year (lagged supply variable)
    #
    # These are log-transformed: FS_AB_log = log(FS_AB + 0.01)
    #                            FS_1Y_log = log(FS_1Y + 0.01)

    # ══════════════════════════════════════════════════════════════════════
    # STEP 4: ATTACH TIER 1 DEVELOP PROBABILITIES
    # ══════════════════════════════════════════════════════════════════════
    #
    # The Tier 1 XGBoost classifier (see examples/tier1_xgboost_classifier.py)
    # produces a probability of development for each parcel-year.
    # This is stored as p_develop and merged into the panel.
    #
    # In the simulation phase (Stage 8), the final predicted probability
    # for each type is: P(type k) × p_develop
    # This ensures that the type-choice simulation respects the binary
    # market participation decision.

    # panel = panel.merge(tier1_probs, on=["parcel_id", "year"])

    # ══════════════════════════════════════════════════════════════════════
    # STEP 5: EXPORT
    # ══════════════════════════════════════════════════════════════════════

    # panel.to_csv(config["paths"]["model_input"], index=False)

    pass
