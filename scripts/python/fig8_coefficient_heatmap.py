"""Figure 8: heatmaps of selected final-stage MNL coefficients by base alternative.
Run from the repository root:  python scripts/python/fig8_coefficient_heatmap.py
"""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns


# Input : final-stage MNL coefficients (manuscript Table 5), entered below
# Output: outputs/figures/
REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "outputs" / "figures"

# ==============================================================================
# 1. DATA ENTRY (manuscript Table 5)
# ==============================================================================

# Order for Rows (Targets) and Columns (Bases)
target_order = ['Mixed', 'Retail', 'Industrial', 'Office']
base_order = ['Mixed', 'Retail', 'Industrial', 'Office']

variables = {
    "Expected Floorspace": {
        "data": {
            'Mixed': [np.nan, 0.144, -0.077, 0.127],
            'Retail': [-0.613, np.nan, -0.797, -0.233],
            'Industrial': [0.219, 0.395, np.nan, 0.378],
            'Office': [-0.291, -0.102, -0.375, np.nan]
        },
        "sig": {
            'Mixed': [False, False, False, False],
            'Retail': [True, False, True, False],
            'Industrial': [False, True, False, True],
            'Office': [True, False, True, False]
        }
    },
    "# Residential Addresses": {
        "data": {
            'Mixed': [np.nan, -0.223, -0.052, -0.270],
            'Retail': [0.212, np.nan, 0.158, -0.053],
            'Industrial': [0.061, -0.152, np.nan, -0.199],
            'Office': [0.269, 0.037, 0.220, np.nan]
        },
        "sig": {
            'Mixed': [False, True, False, True],
            'Retail': [True, False, False, False],
            'Industrial': [False, False, False, True],
            'Office': [True, False, True, False]
        }
    },
    "Density of Developed Lands": {
        "data": {
            'Mixed': [np.nan, -0.010, -0.014, -0.017],
            'Retail': [0.011, np.nan, -0.003, -0.006],
            'Industrial': [0.013, 0.003, np.nan, -0.004],
            'Office': [0.017, 0.008, 0.002, np.nan]
        },
        "sig": {
            'Mixed': [False, False, True, True],
            'Retail': [False, False, False, False],
            'Industrial': [True, False, False, False],
            'Office': [True, False, False, False]
        }
    },
    "# Buildings of All Type (100m)": {
        "data": {
            'Mixed': [np.nan, -0.018, -0.010, -0.006],
            'Retail': [0.016, np.nan, 0.006, 0.012],
            'Industrial': [0.010, -0.005, np.nan, 0.006],
            'Office': [0.003, -0.012, -0.009, np.nan]
        },
        "sig": {
            'Mixed': [False, True, False, False],
            'Retail': [True, False, False, True],
            'Industrial': [False, False, False, False],
            'Office': [False, True, False, False]
        }
    },
    "Distance to Nearest Bus Stop": {
        "data": {
            'Mixed': [np.nan, 0.847, -0.954, -0.171],
            'Retail': [-0.776, np.nan, -1.719, -0.978],
            'Industrial': [0.848, 1.672, np.nan, 0.649],
            'Office': [0.218, 1.045, -0.725, np.nan]
        },
        "sig": {
            'Mixed': [False, True, True, False],
            'Retail': [True, False, True, True],
            'Industrial': [True, True, False, False],
            'Office': [False, True, True, False]
        }
    },
    "Commercial Dominated Zone": {
        "data": {
            'Mixed': [np.nan, 0.524, 1.318, 0.053],
            'Retail': [-0.503, np.nan, 0.801, -0.445],
            'Industrial': [-1.255, -0.711, np.nan, -1.189],
            'Office': [-0.017, 0.492, 1.304, np.nan]
        },
        "sig": {
            'Mixed': [False, False, True, False],
            'Retail': [False, False, False, False],
            'Industrial': [True, False, False, True],
            'Office': [False, False, True, False]
        }
    },
    "Industrial Dominated Zone": {
        "data": {
            'Mixed': [np.nan, 0.936, -0.632, 0.086],
            'Retail': [-0.920, np.nan, -1.535, -0.836],
            'Industrial': [0.663, 1.581, np.nan, 0.741],
            'Office': [-0.088, 0.844, -0.716, np.nan]
        },
        "sig": {
            'Mixed': [False, True, True, False],
            'Retail': [True, False, True, True],
            'Industrial': [True, True, False, True],
            'Office': [False, True, True, False]
        }
    },
    "Retail Dominated Zone": {
        "data": {
            'Mixed': [np.nan, -1.263, 0.496, -0.042],
            'Retail': [1.282, np.nan, 1.769, 1.260],
            'Industrial': [-0.433, -1.669, np.nan, -0.447],
            'Office': [0.028, -1.218, 0.506, np.nan]
        },
        "sig": {
            'Mixed': [False, True, False, False],
            'Retail': [True, False, True, True],
            'Industrial': [False, True, False, False],
            'Office': [False, True, False, False]
        }
    }
}

# ==============================================================================
# 2. PLOTTING THE HEATMAPS
# ==============================================================================

fig, axes = plt.subplots(4, 2, figsize=(16, 20))
axes = axes.flatten()

for i, (var_name, content) in enumerate(variables.items()):
    ax = axes[i]
    
    # Rows = target alternatives, columns = base alternatives
    df = pd.DataFrame(content['data'], index=base_order)
    
    df = df.T
    
    df = df.reindex(index=target_order, columns=base_order)
    
    # Significance flags in the same layout
    df_sig = pd.DataFrame(content['sig'], index=base_order).T
    df_sig = df_sig.reindex(index=target_order, columns=base_order)
    
    stars_text = df_sig.replace({True: '***', False: ''})

    # Scale normalization
    max_val = df.abs().max().max()

    # Draw Heatmap
    sns.heatmap(df, annot=False, cmap='RdBu_r', center=0, 
                vmin=-max_val, vmax=max_val,
                linewidths=1, linecolor='white', ax=ax,
                cbar_kws={'label': 'β', 'shrink': 0.8})
    
    # Add Text Annotations
    for y in range(df.shape[0]):
        for x in range(df.shape[1]):
            val = df.iloc[y, x]
            star = stars_text.iloc[y, x]
            if not np.isnan(val):
                text_color = 'white' if abs(val) > max_val * 0.6 else 'black'
                ax.text(x + 0.5, y + 0.5, f"{val}\n{star}", 
                        horizontalalignment='center', verticalalignment='center',
                        color=text_color, weight='bold', fontsize=11)
    
    # Styling
    ax.set_title(var_name, fontsize=14, weight='bold', pad=8)
    ax.set_xlabel('Base Alternative', fontsize=11)
    ax.set_ylabel('Target Alternative', fontsize=11)
    ax.set_yticklabels(ax.get_yticklabels(), rotation=0, weight='bold', fontsize=11)
    ax.set_xticklabels(ax.get_xticklabels(), weight='bold', fontsize=11)

# Layout Adjustment
plt.subplots_adjust(top=0.90, hspace=0.3, wspace=0.25)
plt.suptitle("The Symmetry of Land Use Preferences: Impact of Base Alternative Selection", 
             fontsize=20, weight='bold', y=0.97)

# Export
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
output_path = OUTPUT_DIR / "Figure8_coefficient_heatmap.png"
plt.savefig(output_path, dpi=300, bbox_inches='tight')
print(f"Heatmap saved to: {output_path}")

plt.show()