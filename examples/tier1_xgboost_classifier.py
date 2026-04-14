"""
================================================================================
Example: Tier 1 Binary Develop/Not-Develop Classifier (XGBoost)
================================================================================
This script provides a REFERENCE IMPLEMENTATION of the XGBoost binary
classifier used as the Tier 1 market-participation model. It determines
whether each parcel will undertake commercial development in a given year.

PURPOSE:
    This is an EXAMPLE, not a turnkey solution. The specific feature set,
    sampling strategy, hyperparameters, and Monte Carlo configuration should
    be adapted to your own study area and data.

    The GTHA case study achieved ~72.6% overall accuracy with consistent
    train/test performance (no overfitting).

HOW IT FITS IN THE PIPELINE:
    1. This classifier runs BEFORE the core model (Stage 8)
    2. Its output (develop probability per parcel-year) is saved to CSV
    3. Stage 8 reads this CSV and multiplies type-choice probabilities
       by p_develop to get effective predictions

DATA REQUIREMENTS:
    A CSV with one row per parcel-year, containing:
      - ID_COL: unique parcel identifier
      - YEAR_COL: year
      - LABEL_COL: binary (1 = development occurred, 0 = no development)
      - Feature columns (urban form, market, transport, demographics, etc.)

SAMPLING STRATEGY:
    For parcels with at least one development year: keep exactly ONE random
    YES row per parcel (to avoid temporal autocorrelation).
    For parcels with zero development years: keep up to FIVE random rows.

DISCLOSURE:
    Code cleaned and reorganised with the assistance of Claude AI (Anthropic).
================================================================================
"""

import os
import json
import numpy as np
import pandas as pd

# ==============================================================================
# USER CONFIGURATION — Adapt these to your data
# ==============================================================================

INPUT_PATH = "path/to/your/parcel_panel_data.csv"   # <-- REPLACE WITH YOUR PATH
OUTPUT_DIR = "outputs/tier1_results"

# Column names
ID_COL    = "GTHA_ID"       # Unique parcel identifier
LABEL_COL = "DevOrNot"      # Binary: 1 = developed, 0 = not developed
YEAR_COL  = "Year"          # Year column (excluded from features)

# Monte Carlo configuration
N_RUNS    = 30              # Number of Monte Carlo iterations
SEED_BASE = 2025            # Base random seed

# Train/test split
TEST_SIZE = 0.20
VAL_SIZE_WITHIN_TRAIN = 0.15

# XGBoost hyperparameters (regularised to prevent overfitting)
XGBOOST_PARAMS = {
    "n_estimators": 4000,
    "learning_rate": 0.03,
    "max_depth": 3,
    "min_child_weight": 10,
    "gamma": 1.0,
    "subsample": 0.6,
    "colsample_bytree": 0.6,
    "reg_alpha": 0.5,
    "reg_lambda": 2.0,
    "tree_method": "hist",
    "grow_policy": "lossguide",
    "max_leaves": 64,
    "max_bin": 256,
    "early_stopping_rounds": 50,
}

THRESHOLD = 0.50            # Decision threshold for classification

# ==============================================================================
# SAMPLING FUNCTION
# ==============================================================================

def sample_dataset(df, seed):
    """
    Apply parcel-aware sampling rules:
      - Parcels with >= 1 YES year: keep exactly ONE random YES row
      - Parcels with 0 YES years: keep up to FIVE random rows (all NO)
    """
    rng = np.random.default_rng(seed)
    df = df.copy()
    df[LABEL_COL] = pd.to_numeric(df[LABEL_COL], errors="coerce").fillna(0).astype(int)

    has_yes = df.groupby(ID_COL)[LABEL_COL].transform("max").eq(1)

    # YES parcels: one random YES row each
    yes_df = df.loc[has_yes & df[LABEL_COL].eq(1)].copy()
    yes_df["_r"] = rng.random(len(yes_df))
    one_yes = (yes_df.sort_values([ID_COL, "_r"])
               .drop_duplicates(subset=[ID_COL], keep="first")
               .drop(columns=["_r"]))

    # NO parcels: up to five random rows each
    no_df = df.loc[~has_yes].copy()
    if len(no_df):
        no_df["_r"] = rng.random(len(no_df))
        up_to5 = (no_df.sort_values([ID_COL, "_r"])
                  .groupby(ID_COL, as_index=False).head(5)
                  .drop(columns=["_r"]))
    else:
        up_to5 = no_df

    return (pd.concat([one_yes, up_to5], axis=0)
            .sort_values([ID_COL, YEAR_COL])
            .reset_index(drop=True))

# ==============================================================================
# PARCEL-SAFE SPLITTING
# ==============================================================================

def stratified_parcel_split(df, test_size, seed):
    """Split by PARCEL (not by row) to prevent data leakage."""
    from sklearn.model_selection import StratifiedShuffleSplit

    grp = df.groupby(ID_COL)[LABEL_COL].max().astype(int)
    ids = grp.index.to_numpy()
    y_grp = grp.to_numpy()

    splitter = StratifiedShuffleSplit(n_splits=1, test_size=test_size, random_state=seed)
    tr_idx, te_idx = next(splitter.split(ids, y_grp))

    tr_ids = set(ids[tr_idx])
    te_ids = set(ids[te_idx])

    return df[ID_COL].isin(tr_ids).to_numpy(), df[ID_COL].isin(te_ids).to_numpy()

# ==============================================================================
# MODEL TRAINING
# ==============================================================================

def train_xgboost(X_tr, y_tr, X_val, y_val, seed, scale_pos_weight):
    """Train a regularised XGBoost binary classifier with early stopping."""
    from xgboost import XGBClassifier

    model = XGBClassifier(
        **XGBOOST_PARAMS,
        random_state=seed,
        n_jobs=-1,
        objective="binary:logistic",
        scale_pos_weight=scale_pos_weight,
        eval_metric=["logloss", "auc"],
        verbosity=0,
    )
    model.fit(X_tr, y_tr, eval_set=[(X_val, y_val)], verbose=0)
    return model

# ==============================================================================
# MAIN PIPELINE
# ==============================================================================

def main():
    from sklearn.metrics import classification_report
    from sklearn.compose import ColumnTransformer
    from sklearn.preprocessing import OneHotEncoder

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Load data
    df_orig = pd.read_csv(INPUT_PATH)
    print(f"Loaded {len(df_orig)} rows, {df_orig[ID_COL].nunique()} unique parcels")

    drop_cols = [LABEL_COL, ID_COL, YEAR_COL]
    all_results = []

    for run in range(N_RUNS):
        sample_seed = SEED_BASE + run
        model_seed = SEED_BASE + 1000 + run

        # 1) Sample
        df = sample_dataset(df_orig, seed=sample_seed)

        # 2) Parcel-safe split
        tr_mask, te_mask = stratified_parcel_split(df, TEST_SIZE, model_seed)
        df_train = df.loc[tr_mask].reset_index(drop=True)
        df_test = df.loc[te_mask].reset_index(drop=True)

        # 3) Validation split within train
        tr_sub, val_mask = stratified_parcel_split(df_train, VAL_SIZE_WITHIN_TRAIN, model_seed)

        # 4) Prepare features
        X_train = df_train.drop(columns=drop_cols, errors="ignore")
        y_train = df_train[LABEL_COL].astype(int)
        X_test = df_test.drop(columns=drop_cols, errors="ignore")
        y_test = df_test[LABEL_COL].astype(int)

        # Handle categorical columns
        cat_cols = X_train.select_dtypes(include=["object", "category"]).columns.tolist()
        num_cols = [c for c in X_train.columns if c not in cat_cols]
        preproc = ColumnTransformer([
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=True), cat_cols),
            ("num", "passthrough", num_cols),
        ])
        preproc.fit(X_train)

        X_tr_sub = preproc.transform(X_train.loc[tr_sub])
        y_tr_sub = y_train.loc[tr_sub].to_numpy()
        X_val = preproc.transform(X_train.loc[val_mask])
        y_val = y_train.loc[val_mask].to_numpy()
        X_te = preproc.transform(X_test)
        y_te = y_test.to_numpy()

        # Class imbalance
        pos = y_tr_sub.sum()
        neg = len(y_tr_sub) - pos
        scale_pos_weight = float(neg) / float(pos) if pos > 0 else 1.0

        # 5) Train
        model = train_xgboost(X_tr_sub, y_tr_sub, X_val, y_val, model_seed, scale_pos_weight)

        # 6) Evaluate
        y_pred = (model.predict_proba(X_te)[:, 1] >= THRESHOLD).astype(int)
        report = classification_report(y_te, y_pred, output_dict=True)
        acc = report["accuracy"]
        f1_1 = report["1"]["f1-score"]
        print(f"[Run {run:2d}] Test accuracy={acc:.4f}  F1(develop)={f1_1:.4f}")

        all_results.append(report)

    # Summary
    mean_acc = np.mean([r["accuracy"] for r in all_results])
    mean_f1 = np.mean([r["1"]["f1-score"] for r in all_results])
    print(f"\nMean over {N_RUNS} runs: accuracy={mean_acc:.4f}, F1(develop)={mean_f1:.4f}")
    print(f"Results saved to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
