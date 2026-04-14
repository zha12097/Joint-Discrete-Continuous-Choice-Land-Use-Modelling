"""
================================================================================
Example: Alternative-Specific Parameter Visualisation
================================================================================
This script produces heatmap and dot-plot visualisations of the alternative-
specific parameter estimates from the base-alternative rotation analysis.

PURPOSE:
    Visualise how estimated coefficients change when the base (reference)
    alternative is rotated. The heatmap should exhibit perfect diagonal
    symmetry (sign flips, magnitude preserved), confirming structural
    robustness of the MNL model.

HOW TO USE:
    1. Run the core model (src/08_core_model.R) with all 4 base alternatives
    2. Extract the alternative-specific coefficients from each specification
    3. Enter the coefficients and significance indicators in the DATA section
    4. Run this script to generate the heatmap and dot-plot figures

READING THE HEATMAP:
    - Rows = "Target Alternative" (the type whose coefficient is estimated)
    - Columns = "Base Alternative" (the reference category)
    - Cell value = estimated coefficient β
    - *** = significant at 95% CI
    - Diagonal = NaN (a type cannot be compared to itself)
    - Symmetry check: cell (i,j) should equal -cell (j,i)

DISCLOSURE:
    Code cleaned and reorganised with the assistance of Claude AI (Anthropic).
================================================================================
"""

import matplotlib.pyplot as plt
import matplotlib.lines as mlines
import seaborn as sns
import pandas as pd
import numpy as np
import os

# ==============================================================================
# USER CONFIGURATION
# ==============================================================================

OUTPUT_DIR = "outputs/alternative_specific_analysis"  # <-- REPLACE WITH YOUR PATH

# Order of alternatives (must match your model output)
TARGET_ORDER = ["Mixed", "Retail", "Industrial", "Office"]
BASE_ORDER   = ["Mixed", "Retail", "Industrial", "Office"]

# ==============================================================================
# DATA ENTRY — Replace with your model results
# ==============================================================================
# For each variable, provide:
#   "data": dict of {target: [coeff when base=Mixed, base=Retail, base=Ind, base=Office]}
#   "sig":  dict of {target: [True/False for significance at each base]}
#
# The example below shows the GTHA case study results.

variables = {
    "Expected Floorspace": {
        "data": {
            "Mixed":      [np.nan,  0.144, -0.077,  0.127],
            "Retail":     [-0.613, np.nan, -0.797, -0.233],
            "Industrial": [ 0.219,  0.395, np.nan,  0.378],
            "Office":     [-0.291, -0.102, -0.375, np.nan],
        },
        "sig": {
            "Mixed":      [False, False, False, False],
            "Retail":     [True,  False, True,  False],
            "Industrial": [False, True,  False, True],
            "Office":     [True,  False, True,  False],
        },
    },
    "# Residential Addresses": {
        "data": {
            "Mixed":      [np.nan, -0.223, -0.052, -0.270],
            "Retail":     [ 0.212, np.nan,  0.158, -0.053],
            "Industrial": [ 0.061, -0.152, np.nan, -0.199],
            "Office":     [ 0.269,  0.037,  0.220, np.nan],
        },
        "sig": {
            "Mixed":      [False, True,  False, True],
            "Retail":     [True,  False, False, False],
            "Industrial": [False, False, False, True],
            "Office":     [True,  False, True,  False],
        },
    },
    "Distance to Nearest Bus Stop": {
        "data": {
            "Mixed":      [np.nan,  0.847, -0.954, -0.171],
            "Retail":     [-0.776, np.nan, -1.719, -0.978],
            "Industrial": [ 0.848,  1.672, np.nan,  0.649],
            "Office":     [ 0.218,  1.045, -0.725, np.nan],
        },
        "sig": {
            "Mixed":      [False, True,  True,  False],
            "Retail":     [True,  False, True,  True],
            "Industrial": [True,  True,  False, False],
            "Office":     [False, True,  True,  False],
        },
    },
    "Industrial Dominated Zone": {
        "data": {
            "Mixed":      [np.nan,  0.936, -0.632,  0.086],
            "Retail":     [-0.920, np.nan, -1.535, -0.836],
            "Industrial": [ 0.663,  1.581, np.nan,  0.741],
            "Office":     [-0.088,  0.844, -0.716, np.nan],
        },
        "sig": {
            "Mixed":      [False, True,  True,  False],
            "Retail":     [True,  False, True,  True],
            "Industrial": [True,  True,  False, True],
            "Office":     [False, True,  True,  False],
        },
    },
}
# Add more variables as needed from your model results.

# ==============================================================================
# FIGURE 1: HEATMAP
# ==============================================================================

n_vars = len(variables)
n_cols = 2
n_rows = (n_vars + 1) // n_cols

fig, axes = plt.subplots(n_rows, n_cols, figsize=(16, 5 * n_rows))
axes = axes.flatten()

for i, (var_name, content) in enumerate(variables.items()):
    ax = axes[i]

    # Build and transpose so rows=targets, cols=bases
    df = pd.DataFrame(content["data"], index=BASE_ORDER).T
    df = df.reindex(index=TARGET_ORDER, columns=BASE_ORDER)

    df_sig = pd.DataFrame(content["sig"], index=BASE_ORDER).T
    df_sig = df_sig.reindex(index=TARGET_ORDER, columns=BASE_ORDER)
    stars = df_sig.replace({True: "***", False: ""})

    max_val = df.abs().max().max()

    sns.heatmap(df, annot=False, cmap="RdBu_r", center=0,
                vmin=-max_val, vmax=max_val,
                linewidths=1, linecolor="white", ax=ax,
                cbar_kws={"label": "β", "shrink": 0.8})

    # Annotate cells
    for y in range(df.shape[0]):
        for x in range(df.shape[1]):
            val = df.iloc[y, x]
            star = stars.iloc[y, x]
            if not np.isnan(val):
                color = "white" if abs(val) > max_val * 0.6 else "black"
                ax.text(x + 0.5, y + 0.5, f"{val:.3f}\n{star}",
                        ha="center", va="center", color=color,
                        weight="bold", fontsize=10)

    ax.set_title(var_name, fontsize=13, weight="bold", pad=8)
    ax.set_xlabel("Base Alternative", fontsize=10)
    ax.set_ylabel("Target Alternative", fontsize=10)

# Hide unused axes
for j in range(i + 1, len(axes)):
    axes[j].set_visible(False)

plt.suptitle("Symmetry of Land Use Preferences: Impact of Base Alternative Selection",
             fontsize=18, weight="bold", y=1.01)
plt.tight_layout()

os.makedirs(OUTPUT_DIR, exist_ok=True)
plt.savefig(os.path.join(OUTPUT_DIR, "heatmap_base_rotation.png"), dpi=300, bbox_inches="tight")
print(f"Heatmap saved to {OUTPUT_DIR}")
plt.show()

# ==============================================================================
# FIGURE 2: DOT PLOT
# ==============================================================================

palette = sns.color_palette("deep", n_colors=4)
color_dict = dict(zip(BASE_ORDER, palette))
markers = {"Significant": "o", "Not Significant": "X"}

fig, axes = plt.subplots(n_rows, n_cols, figsize=(18, 5.5 * n_rows))
axes = axes.flatten()

for i, (var_name, content) in enumerate(variables.items()):
    ax = axes[i]

    df = pd.DataFrame(content["data"], index=BASE_ORDER).T
    df = df.reindex(index=TARGET_ORDER, columns=BASE_ORDER)
    df_sig = pd.DataFrame(content["sig"], index=BASE_ORDER).T
    df_sig = df_sig.reindex(index=TARGET_ORDER, columns=BASE_ORDER)

    df_long = df.reset_index().melt(id_vars="index", var_name="Base", value_name="Estimate")
    df_long.columns = ["Target", "Base", "Estimate"]
    df_sig_long = df_sig.reset_index().melt(id_vars="index", var_name="Base", value_name="SigBool")
    df_sig_long.columns = ["Target", "Base", "SigBool"]

    df_plot = pd.merge(df_long, df_sig_long, on=["Target", "Base"]).dropna()
    df_plot["Significance"] = df_plot["SigBool"].map({True: "Significant", False: "Not Significant"})

    sns.scatterplot(data=df_plot, x="Estimate", y="Target",
                    hue="Base", style="Significance",
                    markers=markers, palette=color_dict,
                    s=180, edgecolor="black", linewidth=1.2,
                    ax=ax, legend=False)

    ax.axvline(x=0, color="black", linestyle="--", linewidth=1.2, alpha=0.5)
    ax.grid(axis="x", linestyle=":", alpha=0.7)
    max_val = df_plot["Estimate"].abs().max()
    ax.set_xlim(-max(max_val * 1.2, 0.1), max(max_val * 1.2, 0.1))
    ax.set_title(var_name, fontsize=13, weight="bold", pad=6)
    ax.set_xlabel("Parameter Estimate", fontsize=10)
    ax.set_ylabel("")

for j in range(i + 1, len(axes)):
    axes[j].set_visible(False)

# Legends
base_handles = [mlines.Line2D([], [], color=c, marker="s", linestyle="None",
                markersize=12, markeredgecolor="black", label=l)
                for l, c in color_dict.items()]
fig.legend(handles=base_handles, title="Base Alternative (Color)",
           loc="lower center", bbox_to_anchor=(0.35, 0.93),
           ncol=4, fontsize=11, frameon=False)

sig_handles = [
    mlines.Line2D([], [], color="gray", marker="o", linestyle="None",
                  markersize=12, markeredgecolor="black", label="Significant (p ≤ 0.1)"),
    mlines.Line2D([], [], color="gray", marker="X", linestyle="None",
                  markersize=12, markeredgecolor="black", label="Not Significant"),
]
fig.legend(handles=sig_handles, title="Significance (Shape)",
           loc="lower center", bbox_to_anchor=(0.75, 0.93),
           ncol=2, fontsize=11, frameon=False)

plt.suptitle("Comparative Parameter Estimates: Magnitude, Direction, and Significance",
             fontsize=18, weight="bold", y=1.01)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, "dotplot_base_rotation.png"), dpi=300, bbox_inches="tight")
print(f"Dot plot saved to {OUTPUT_DIR}")
plt.show()
