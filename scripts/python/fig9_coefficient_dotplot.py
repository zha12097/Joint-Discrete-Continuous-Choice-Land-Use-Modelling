"""Figure 9: dot plots of selected final-stage MNL coefficients by base alternative.
Run from the repository root:  python scripts/python/fig9_coefficient_dotplot.py
"""
from pathlib import Path

import matplotlib.lines as mlines
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
# 2. PLOTTING THE DOT PLOTS
# ==============================================================================

fig, axes = plt.subplots(4, 2, figsize=(18, 22))
axes = axes.flatten()

# Markers and Colors
markers = {"Significant": 'o', "Not Significant": 'X'}
palette = sns.color_palette('deep', n_colors=4)
color_dict = dict(zip(['Mixed', 'Retail', 'Industrial', 'Office'], palette))

for i, (var_name, content) in enumerate(variables.items()):
    ax = axes[i]
    
    # Rows = target alternatives, columns = base alternatives
    df = pd.DataFrame(content['data'], index=base_order).T
    df = df.reindex(index=target_order, columns=base_order)
    
    df_sig = pd.DataFrame(content['sig'], index=base_order).T
    df_sig = df_sig.reindex(index=target_order, columns=base_order)
    
    # Melt
    df_long = df.reset_index().melt(id_vars='index', var_name='Base', value_name='Estimate')
    df_long.columns = ['Target', 'Base', 'Estimate']
    
    df_sig_long = df_sig.reset_index().melt(id_vars='index', var_name='Base', value_name='SigBool')
    df_sig_long.columns = ['Target', 'Base', 'SigBool']
    
    # Merge
    df_plot = pd.merge(df_long, df_sig_long, on=['Target', 'Base']).dropna()
    df_plot['Significance'] = df_plot['SigBool'].map({True: "Significant", False: "Not Significant"})

    # Plotting
    sns.scatterplot(
        data=df_plot, x='Estimate', y='Target', 
        hue='Base', style='Significance',
        markers=markers, palette=color_dict, 
        s=180, edgecolor='black', linewidth=1.2, ax=ax, legend=False
    )
    
    # Styling
    ax.axvline(x=0, color='black', linestyle='--', linewidth=1.2, alpha=0.5)
    ax.grid(axis='x', linestyle=':', alpha=0.7)
    ax.grid(axis='y', visible=False)
    
    # Axis Limits
    max_val = df_plot['Estimate'].abs().max()
    limit = max(max_val * 1.2, 0.1) 
    ax.set_xlim(-limit, limit)
    
    ax.set_title(var_name, fontsize=14, weight='bold', pad=6)
    ax.set_xlabel('Parameter Estimate', fontsize=11)
    ax.set_ylabel('', fontsize=12)
    ax.tick_params(axis='y', labelsize=13, labelcolor='black')
    ax.tick_params(axis='x', labelsize=11)

# --- DUAL LEGEND SETUP ---
base_handles = [mlines.Line2D([], [], color=c, marker='s', linestyle='None', 
                markersize=12, markeredgecolor='black', label=l) 
                for l, c in color_dict.items()]

fig.legend(handles=base_handles, 
           title="Base Alternative (Color)", title_fontsize=13,
           loc='lower center', bbox_to_anchor=(0.35, 0.92), 
           ncol=4, fontsize=12, frameon=False)

sig_handles = [
    mlines.Line2D([], [], color='black', marker='o', linestyle='None', 
                  markersize=12, markerfacecolor='gray', markeredgecolor='black', 
                  label='Significant (p <= 0.05 or 0.1)'),
    mlines.Line2D([], [], color='black', marker='X', linestyle='None', 
                  markersize=12, markerfacecolor='gray', markeredgecolor='black', 
                  label='Not Significant')
]

fig.legend(handles=sig_handles, 
           title="Significance (Shape)", title_fontsize=13,
           loc='lower center', bbox_to_anchor=(0.75, 0.92), 
           ncol=2, fontsize=12, frameon=False)

# Layout
plt.subplots_adjust(top=0.90, hspace=0.35, wspace=0.2) 
plt.suptitle("Comparative Parameter Estimates: Magnitude, Direction, and Significance", 
             fontsize=20, weight='bold', y=0.98)

# Export
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
output_path = OUTPUT_DIR / "Figure9_coefficient_dotplot.png"
plt.savefig(output_path, dpi=300, bbox_inches='tight')
print(f"Dot Plot saved to: {output_path}")

plt.show()