"""Figure A.3: annual temporal indicators of the final-stage MNL under four base alternatives."""
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm
from matplotlib.patches import Rectangle


# ===================================================================
# 1. LOCATE THE CSV EXPORTED BY R
# ===================================================================
# Input : outputs/final_MNL_four_base_alternatives/annual_temporal_indicators.csv
#         (written by scripts/R/final_MNL_four_base_alternatives.R)
# Output: outputs/figures/
# Run:    python scripts/python/figA3_annual_temporal_indicators.py

REPO_ROOT = Path(__file__).resolve().parents[2]

INPUT_FILE = (
    REPO_ROOT
    / "outputs"
    / "final_MNL_four_base_alternatives"
    / "annual_temporal_indicators.csv"
)

if not INPUT_FILE.exists():
    raise FileNotFoundError(
        f"Could not find {INPUT_FILE}. "
        "Run scripts/R/final_MNL_four_base_alternatives.R first."
    )

OUTPUT_DIR = REPO_ROOT / "outputs" / "figures"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_PNG = OUTPUT_DIR / "FigureA3_annual_temporal_indicators.png"
OUTPUT_PDF = OUTPUT_DIR / "FigureA3_annual_temporal_indicators.pdf"

print("Input CSV:", INPUT_FILE)
print("Figure outputs:", OUTPUT_DIR)


# ===================================================================
# 2. FIGURE SETTINGS
# ===================================================================

YEARS = list(
    range(
        2015,
        2023
    )
)


PANEL_SPECS = {

    "A": {
        "title":
            "Panel A. Base Alternative = Mixed-use",

        "rows": [
            "Industrial",
            "Office",
            "Retail"
        ]
    },

    "B": {
        "title":
            "Panel B. Base Alternative = Retail",

        "rows": [
            "Mixed-use",
            "Industrial",
            "Office"
        ]
    },

    "C": {
        "title":
            "Panel C. Base Alternative = Industrial",

        "rows": [
            "Mixed-use",
            "Office",
            "Retail"
        ]
    },

    "D": {
        "title":
            "Panel D. Base Alternative = Office",

        "rows": [
            "Mixed-use",
            "Industrial",
            "Retail"
        ]
    }
}


VMIN = -3.0
VMAX = 3.0


# ===================================================================
# 3. READ AND VALIDATE DATA
# ===================================================================

df = pd.read_csv(
    INPUT_FILE
)


required_columns = {
    "Panel",
    "Panel_Title",
    "Base",
    "Year",
    "Target",
    "Estimate",
    "Std_Error",
    "z_value",
    "p_value",
    "Significance"
}


missing_columns = (
    required_columns
    .difference(
        df.columns
    )
)


if missing_columns:

    raise ValueError(
        "The exported CSV is missing these required columns: "
        + ", ".join(
            sorted(
                missing_columns
            )
        )
    )


df["Year"] = pd.to_numeric(
    df["Year"],
    errors="raise"
).astype(int)


for column in [
    "Estimate",
    "Std_Error",
    "z_value",
    "p_value"
]:

    df[column] = pd.to_numeric(
        df[column],
        errors="raise"
    )


if len(df) != 96:

    raise ValueError(
        f"Expected 96 annual-coefficient rows, but found {len(df)}."
    )


for panel_id in [
    "A",
    "B",
    "C",
    "D"
]:

    panel_n = (
        df[
            df["Panel"]
            == panel_id
        ]
        .shape[0]
    )

    if panel_n != 24:

        raise ValueError(
            f"Panel {panel_id} should contain 24 rows, "
            f"but contains {panel_n}."
        )


# Recalculate significance from p-values.
#
# Manuscript convention:
# *** = p < 0.05
# *   = p < 0.10

df["Significance"] = np.select(

    [
        df["p_value"] < 0.05,
        df["p_value"] < 0.10
    ],

    [
        "***",
        "*"
    ],

    default=""
)


# ===================================================================
# 4. COLOUR SCALE AND TEXT FORMATTING
# ===================================================================

coef_cmap = LinearSegmentedColormap.from_list(

    "coefficient_scale",

    [
        "#3268A8",
        "#F9F9F9",
        "#D94B41"
    ]
)


coef_norm = TwoSlopeNorm(
    vmin=VMIN,
    vcenter=0.0,
    vmax=VMAX
)


def format_coefficient(
    value
):

    text = f"{value:.3f}"

    return text.replace(
        "-",
        "\N{MINUS SIGN}"
    )


def choose_text_colour(
    rgba
):

    red, green, blue, _ = rgba

    luminance = (
        0.2126 * red
        + 0.7152 * green
        + 0.0722 * blue
    )

    if luminance < 0.48:
        return "white"

    return "#111111"


# ===================================================================
# 5. CREATE FIXED FIGURE CANVAS
# ===================================================================

fig = plt.figure(
    figsize=(
        18,
        10
    ),
    facecolor="white"
)


canvas = fig.add_axes(
    [
        0,
        0,
        1,
        1
    ]
)


canvas.set_xlim(
    0,
    1
)


canvas.set_ylim(
    0,
    1
)


canvas.axis(
    "off"
)


# ===================================================================
# 6. TITLE AND SUBTITLE
# ===================================================================

fig.text(

    0.5,
    0.966,

    "Figure A.3. Annual Temporal Indicators in the Final-Stage MNL "
    "under Alternative Base Specifications",

    ha="center",
    va="top",

    fontsize=20,
    fontweight="bold"
)


fig.text(

    0.5,
    0.925,

    "Each cell reports the coefficient estimate.  "
    "*** p < 0.05; * p < 0.10.  "
    "2023 is omitted and serves as the reference year.",

    ha="center",
    va="top",

    fontsize=11.5
)


# ===================================================================
# 7. PANEL GEOMETRY
# ===================================================================

PANEL_WIDTH = 0.425
PANEL_HEIGHT = 0.300
HEADER_HEIGHT = 0.043


PANEL_POSITIONS = {

    "A": (
        0.045,
        0.565
    ),

    "B": (
        0.530,
        0.565
    ),

    "C": (
        0.045,
        0.225
    ),

    "D": (
        0.530,
        0.225
    )
}


# ===================================================================
# 8. DRAW THE FOUR PANELS
# ===================================================================

for panel_id in [
    "A",
    "B",
    "C",
    "D"
]:

    panel_x, panel_y = (
        PANEL_POSITIONS[
            panel_id
        ]
    )

    panel_spec = (
        PANEL_SPECS[
            panel_id
        ]
    )


    # ---------------------------------------------------------------
    # 8.1 Panel header
    # ---------------------------------------------------------------

    canvas.add_patch(

        Rectangle(

            (
                panel_x,
                panel_y
                + PANEL_HEIGHT
            ),

            PANEL_WIDTH,
            HEADER_HEIGHT,

            facecolor="#173F7A",
            edgecolor="none"
        )
    )


    canvas.text(

        panel_x
        + PANEL_WIDTH / 2,

        panel_y
        + PANEL_HEIGHT
        + HEADER_HEIGHT / 2,

        panel_spec["title"],

        ha="center",
        va="center",

        fontsize=13.2,
        fontweight="bold",
        color="white"
    )


    # ---------------------------------------------------------------
    # 8.2 Heatmap geometry
    # ---------------------------------------------------------------

    label_width = 0.090


    grid_x = (
        panel_x
        + label_width
    )


    grid_y = (
        panel_y
        + 0.050
    )


    grid_width = (
        PANEL_WIDTH
        - label_width
        - 0.010
    )


    grid_height = 0.205


    cell_width = (
        grid_width
        / 8
    )


    cell_height = (
        grid_height
        / 3
    )


    # ---------------------------------------------------------------
    # 8.3 Row heading and year headings
    # ---------------------------------------------------------------

    canvas.text(

        grid_x
        - 0.010,

        grid_y
        + grid_height
        + 0.016,

        "Target\nAlternative",

        ha="right",
        va="bottom",

        fontsize=8.7,
        fontweight="bold",

        linespacing=0.88
    )


    for year_index, year in enumerate(
        YEARS
    ):

        year_center = (
            grid_x
            + (
                year_index
                + 0.5
            )
            * cell_width
        )


        canvas.text(

            year_center,

            grid_y
            + grid_height
            + 0.016,

            str(
                year
            ),

            ha="center",
            va="bottom",

            fontsize=10.4,
            fontweight="bold"
        )


    # ---------------------------------------------------------------
    # 8.4 Subtle heatmap border
    # ---------------------------------------------------------------

    canvas.add_patch(

        Rectangle(

            (
                grid_x,
                grid_y
            ),

            grid_width,
            grid_height,

            fill=False,

            edgecolor="#D0D0D0",
            linewidth=0.8
        )
    )


    # ---------------------------------------------------------------
    # 8.5 Divider between 2019 and 2020
    # ---------------------------------------------------------------

    pandemic_divider_x = (
        grid_x
        + 5
        * cell_width
    )


    canvas.plot(

        [
            pandemic_divider_x,
            pandemic_divider_x
        ],

        [
            grid_y,
            grid_y
            + grid_height
            + 0.004
        ],

        linestyle=(
            0,
            (
                4,
                3
            )
        ),

        linewidth=0.9,

        color="#777777"
    )


    # ---------------------------------------------------------------
    # 8.6 Rows and cells
    # ---------------------------------------------------------------

    for row_index, target in enumerate(
        panel_spec["rows"]
    ):

        row_center_y = (
            grid_y
            + grid_height
            - (
                row_index
                + 0.5
            )
            * cell_height
        )


        canvas.text(

            grid_x
            - 0.012,

            row_center_y,

            target,

            ha="right",
            va="center",

            fontsize=11.2
        )


        for year_index, year in enumerate(
            YEARS
        ):

            cell_x = (
                grid_x
                + year_index
                * cell_width
            )


            selected = df[

                (
                    df["Panel"]
                    == panel_id
                )

                &

                (
                    df["Target"]
                    == target
                )

                &

                (
                    df["Year"]
                    == year
                )
            ]


            if selected.empty:

                raise ValueError(
                    "Missing coefficient for "
                    f"Panel {panel_id}, "
                    f"{target}, "
                    f"{year}."
                )


            if len(
                selected
            ) > 1:

                raise ValueError(
                    "Duplicate coefficient for "
                    f"Panel {panel_id}, "
                    f"{target}, "
                    f"{year}."
                )


            estimate = float(
                selected.iloc[0][
                    "Estimate"
                ]
            )


            significance = str(
                selected.iloc[0][
                    "Significance"
                ]
            ).strip()


            cell_colour = (
                coef_cmap(
                    coef_norm(
                        estimate
                    )
                )
            )


            canvas.add_patch(

                Rectangle(

                    (
                        cell_x,
                        row_center_y
                        - cell_height / 2
                    ),

                    cell_width,
                    cell_height,

                    facecolor=cell_colour,

                    edgecolor="white",
                    linewidth=1.15
                )
            )


            text_colour = (
                choose_text_colour(
                    cell_colour
                )
            )


            # Coefficient estimate
            canvas.text(

                cell_x
                + cell_width / 2,

                row_center_y
                + 0.010,

                format_coefficient(
                    estimate
                ),

                ha="center",
                va="center",

                fontsize=10.2,

                color=text_colour
            )


            # Significance marker
            if significance:

                canvas.text(

                    cell_x
                    + cell_width / 2,

                    row_center_y
                    - 0.020,

                    significance,

                    ha="center",
                    va="center",

                    fontsize=10.0,
                    fontweight="bold",

                    color=text_colour
                )


    # ---------------------------------------------------------------
    # 8.7 Pandemic-period label
    # ---------------------------------------------------------------

    canvas.text(

        grid_x
        + 6.5
        * cell_width,

        grid_y
        - 0.017,

        "Pandemic period",

        ha="center",
        va="top",

        fontsize=9.8,

        color="#5D2AA8"
    )


# ===================================================================
# 9. SHARED COEFFICIENT SCALE
# ===================================================================

colourbar_x = 0.275
colourbar_y = 0.132

colourbar_width = 0.450
colourbar_height = 0.018

number_of_segments = 400


for segment in range(
    number_of_segments
):

    fraction = (
        segment
        / number_of_segments
    )


    value = (
        VMIN
        + fraction
        * (
            VMAX
            - VMIN
        )
    )


    canvas.add_patch(

        Rectangle(

            (
                colourbar_x
                + fraction
                * colourbar_width,

                colourbar_y
            ),

            colourbar_width
            / number_of_segments,

            colourbar_height,

            facecolor=coef_cmap(
                coef_norm(
                    value
                )
            ),

            edgecolor="none"
        )
    )


canvas.text(

    0.5,

    colourbar_y
    + 0.030,

    "Coefficient estimate",

    ha="center",
    va="bottom",

    fontsize=11.7,
    fontweight="bold"
)


for tick in range(
    -3,
    4
):

    tick_x = (
        colourbar_x
        + (
            tick
            - VMIN
        )
        / (
            VMAX
            - VMIN
        )
        * colourbar_width
    )


    canvas.plot(

        [
            tick_x,
            tick_x
        ],

        [
            colourbar_y
            - 0.004,

            colourbar_y
        ],

        linewidth=0.8,
        color="#777777"
    )


    canvas.text(

        tick_x,

        colourbar_y
        - 0.010,

        str(
            tick
        ).replace(
            "-",
            "\N{MINUS SIGN}"
        ),

        ha="center",
        va="top",

        fontsize=9.8
    )


canvas.text(

    colourbar_x
    - 0.012,

    colourbar_y
    + colourbar_height / 2,

    "More negative",

    ha="right",
    va="center",

    fontsize=9.8
)


canvas.text(

    colourbar_x
    + colourbar_width
    + 0.012,

    colourbar_y
    + colourbar_height / 2,

    "More positive",

    ha="left",
    va="center",

    fontsize=9.8
)


# ===================================================================
# 10. SAVE FIGURE
# ===================================================================

fig.savefig(

    OUTPUT_PNG,

    dpi=400,

    bbox_inches="tight",

    facecolor="white"
)


fig.savefig(

    OUTPUT_PDF,

    bbox_inches="tight",

    facecolor="white"
)


plt.show()


print(
    "\nSaved PNG:"
)

print(
    OUTPUT_PNG
)


print(
    "\nSaved PDF:"
)

print(
    OUTPUT_PDF
)
