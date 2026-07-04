from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, to_rgb
from matplotlib.patches import Patch


ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = ROOT / "results" / "barumerli_pge_fisher_final"
SUMMARY_CSV = RESULT_ROOT / "full_evaluation_summary.csv"
FSP_AE_SUMMARY_CSV = (
    ROOT
    / "results"
    / "learning_comparator_extension"
    / "full_evaluation_summary.csv"
)
FSP_AE_LSD_16K_CSV = (
    ROOT
    / "results"
    / "learning_comparator_extension"
    / "fsp_ae_lsd_20_16k.csv"
)
SAM_CSV = ROOT / "results" / "ml_lap_sam_metrics.csv"
FIG_DIR = ROOT / "figures" / "evaluation"
TABLE_DIR = ROOT / "tables" / "evaluation"


METHOD_ORDER = [
    "SUpDEq_SH",
    "SUpDEq_MCA",
    "SUpDEq_NN_MCA_6dB",
    "SUpDEq_Bary_MCA_6dB",
    "RANF",
    "FSP_AE",
]

CORE_METHODS = [
    "SUpDEq_SH",
    "SUpDEq_MCA",
    "SUpDEq_NN_MCA_6dB",
    "SUpDEq_Bary_MCA_6dB",
    "RANF",
    "FSP_AE",
]

DISTRIBUTION_METHODS = [
    "SUpDEq_SH",
    "SUpDEq_MCA",
    "SUpDEq_NN_MCA_6dB",
    "SUpDEq_Bary_MCA_6dB",
    "RANF",
    "FSP_AE",
]

METHOD_LABELS = {
    "None_NN": "Natural",
    "SH": "SH",
    "OBTA_SH": "OBTA-SH",
    "PC_SH": "PC-SH",
    "SUpDEq_SH": "SUpDEq-SH",
    "SUpDEq_Lim_SH": "SUpDEq-Lim-SH",
    "SUpDEq_AP_SH": "SUpDEq-AP-SH",
    "SUpDEq_Lim_AP_SH": "SUpDEq-Lim-AP-SH",
    "SUpDEq_NN": "SUpDEq-Natural",
    "SUpDEq_MCA": "SUpDEq-MCA",
    "SUpDEq_NN_MCA_6dB": "SUpDEq-Natural-MCA",
    "SUpDEq_Bary_MCA_6dB": "SUpDEq-Bary-MCA",
    "RANF": "RANF",
    "FSP_AE": "FSP-AE",
}

RETENTION_ORDER = [100, 19, 5, 3]


def configure_matplotlib() -> None:
    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.serif": ["Times New Roman", "STIXGeneral", "DejaVu Serif"],
            "mathtext.fontset": "cm",
            "font.size": 12,
            "axes.labelsize": 13,
            "axes.titlesize": 13,
            "xtick.labelsize": 11,
            "ytick.labelsize": 11,
            "legend.fontsize": 10,
            "figure.titlesize": 14,
            "axes.linewidth": 0.8,
            "savefig.bbox": "tight",
            "savefig.pad_inches": 0.03,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


def load_summary() -> pd.DataFrame:
    df = pd.read_csv(SUMMARY_CSV)
    if FSP_AE_SUMMARY_CSV.is_file():
        fsp = pd.read_csv(FSP_AE_SUMMARY_CSV)
        df = pd.concat([df, fsp], ignore_index=True)
    if FSP_AE_LSD_16K_CSV.is_file():
        fsp_lsd = pd.read_csv(FSP_AE_LSD_16K_CSV)
        fsp_lsd = fsp_lsd.rename(columns={"LSDdB_20_16k": "FSP_AE_LSDdB"})
        df = df.merge(
            fsp_lsd,
            how="left",
            on=["subjectId", "retainedDirections"],
        )
        idx = df["method"].eq("FSP_AE") & df["FSP_AE_LSDdB"].notna()
        df.loc[idx, "LSDdB"] = df.loc[idx, "FSP_AE_LSDdB"]
        df = df.drop(columns=["FSP_AE_LSDdB"])
    df = df[df["method"].isin(METHOD_ORDER)].copy()
    numeric_cols = [
        "retainedDirections",
        "meanAIRM",
        "medianAIRM",
        "stdAIRM",
        "iqrAIRM",
        "meanDeterminantError",
        "meanAnisotropyError",
        "meanOrientationErrorDeg",
        "orientationValidProportion",
        "LSDdB",
        "ILDErrorDb",
        "lateralRMSErrorDeg",
        "localPolarRMSErrorDeg",
        "quadrantErrorPercent",
        "relativeLateralRMSErrorDeg",
        "relativeLocalPolarRMSErrorDeg",
        "relativeQuadrantErrorPercentagePoints",
    ]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def load_sam_metrics() -> pd.DataFrame:
    if not SAM_CSV.is_file():
        return pd.DataFrame()
    df = pd.read_csv(SAM_CSV)
    df = df[df["method"] == "RANF"].copy()
    for col in ["retention", "lapLSDdB", "lapILDErrorDb", "lapITDErrorUs"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def aggregate_completed(df: pd.DataFrame) -> pd.DataFrame:
    completed = df[df["status"] == "completed"].copy()
    agg = (
        completed.groupby(["method", "retainedDirections"], as_index=False)
        .agg(
            rows=("subjectId", "count"),
            meanAIRM=("meanAIRM", "mean"),
            sdAIRM=("meanAIRM", "std"),
            medianAIRM=("medianAIRM", "mean"),
            determinant=("meanDeterminantError", "mean"),
            anisotropy=("meanAnisotropyError", "mean"),
            orientation=("meanOrientationErrorDeg", "mean"),
            orientValid=("orientationValidProportion", "mean"),
            LSDdB=("LSDdB", "mean"),
            ILD=("ILDErrorDb", "mean"),
            relLateral=("relativeLateralRMSErrorDeg", "mean"),
            relPolar=("relativeLocalPolarRMSErrorDeg", "mean"),
            relQuadrant=("relativeQuadrantErrorPercentagePoints", "mean"),
        )
        .sort_values(["retainedDirections", "method"])
    )
    return agg


def save_figure(fig: plt.Figure, name: str) -> None:
    for suffix in (".pdf", ".png"):
        fig.savefig(FIG_DIR / f"{name}{suffix}", dpi=300)
    plt.close(fig)


def contrast_text_colour(cmap, norm, value: float) -> str:
    """Choose black or white annotation text from rendered cell luminance."""
    r, g, b = to_rgb(cmap(norm(value)))
    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return "black" if luminance > 0.55 else "white"


def airm_heatmap(agg: pd.DataFrame) -> None:
    pivot = (
        agg.pivot(index="method", columns="retainedDirections", values="meanAIRM")
        .reindex(METHOD_ORDER)
        .reindex(columns=RETENTION_ORDER)
    )
    values = pivot.to_numpy(dtype=float)
    finite = values[np.isfinite(values)]
    fig, ax = plt.subplots(figsize=(7.2, 5.8))
    cmap = plt.get_cmap("viridis")
    norm = LogNorm(vmin=max(0.25, np.nanmin(finite)), vmax=np.nanmax(finite))
    image = ax.imshow(
        values,
        aspect="auto",
        cmap=cmap,
        norm=norm,
    )
    ax.set_xticks(range(len(RETENTION_ORDER)), [str(v) for v in RETENTION_ORDER])
    ax.set_yticks(
        range(len(METHOD_ORDER)),
        [METHOD_LABELS.get(m, m) for m in METHOD_ORDER],
    )
    ax.set_xlabel("Retained directions")
    ax.set_title("Mean AIRM tensor discrepancy")
    ax.tick_params(axis="both", length=0)

    for i in range(values.shape[0]):
        for j in range(values.shape[1]):
            val = values[i, j]
            if np.isfinite(val):
                colour = contrast_text_colour(cmap, norm, val)
                ax.text(j, i, f"{val:.2f}", ha="center", va="center", color=colour, fontsize=8.5)
            else:
                ax.text(j, i, "N/A", ha="center", va="center", color="black", fontsize=8.5)

    cbar = fig.colorbar(image, ax=ax, fraction=0.046, pad=0.02)
    cbar.set_label("Mean AIRM distance")
    save_figure(fig, "airm_heatmap")


def metric_relationships(df: pd.DataFrame) -> None:
    completed = df[df["status"] == "completed"].copy()
    fig, axes = plt.subplots(1, 2, figsize=(8.4, 3.8))
    cmap = plt.get_cmap("plasma")
    colour_map = {100: cmap(0.08), 19: cmap(0.36), 5: cmap(0.66), 3: cmap(0.9)}

    for retention in RETENTION_ORDER:
        rows = completed[completed["retainedDirections"] == retention]
        axes[0].scatter(
            rows["LSDdB"],
            rows["meanAIRM"],
            s=18,
            alpha=0.58,
            color=colour_map[retention],
            edgecolor="none",
            label=str(retention),
        )
        axes[1].scatter(
            rows["relativeLocalPolarRMSErrorDeg"],
            rows["meanAIRM"],
            s=18,
            alpha=0.58,
            color=colour_map[retention],
            edgecolor="none",
            label=str(retention),
        )

    axes[0].set_xlabel("LSD (dB)")
    axes[0].set_ylabel("Mean AIRM")
    axes[1].set_xlabel("Relative local polar RMS (deg)")
    axes[1].set_ylabel("Mean AIRM")
    for ax in axes:
        ax.grid(True, color="0.88", linewidth=0.7)
        ax.set_axisbelow(True)
    axes[1].legend(title="Retained", frameon=False, loc="upper left")
    fig.tight_layout()
    save_figure(fig, "metric_relationships_paper")


def tensor_component_bars(agg: pd.DataFrame) -> None:
    selected = agg[agg["method"].isin(CORE_METHODS)].copy()
    selected["methodLabel"] = selected["method"].map(METHOD_LABELS)
    x = np.arange(len(RETENTION_ORDER))
    width = 0.12
    fig, axes = plt.subplots(1, 3, figsize=(9.2, 3.7), sharex=True)
    metrics = [
        ("determinant", "Log-determinant error"),
        ("anisotropy", "Anisotropy-ratio error"),
        ("orientation", "Orientation error (deg)"),
    ]
    colours = plt.get_cmap("tab10")
    for i_method, method in enumerate(CORE_METHODS):
        rows = (
            selected[selected["method"] == method]
            .set_index("retainedDirections")
            .reindex(RETENTION_ORDER)
        )
        offset = (i_method - (len(CORE_METHODS) - 1) / 2) * width
        for ax, (metric, ylabel) in zip(axes, metrics):
            y = rows[metric].to_numpy(dtype=float)
            ax.bar(
                x + offset,
                y,
                width=width,
                color=colours(i_method),
                label=METHOD_LABELS[method],
            )
            ax.set_ylabel(ylabel)
            ax.grid(True, axis="y", color="0.88", linewidth=0.7)
            ax.set_axisbelow(True)
    for ax in axes:
        ax.set_xticks(x, [str(v) for v in RETENTION_ORDER])
        ax.set_xlabel("Retained directions")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.05))
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    save_figure(fig, "tensor_component_bars")


def subject_distribution_boxplots(df: pd.DataFrame) -> None:
    completed = df[
        (df["status"] == "completed")
        & (df["method"].isin(DISTRIBUTION_METHODS))
    ].copy()
    panels = [
        ("meanAIRM", "Mean AIRM", (0, 45)),
        ("LSDdB", "LSD (dB)", None),
        ("relativeLocalPolarRMSErrorDeg", "Relative local polar RMS (deg)", None),
    ]
    colours = plt.get_cmap("tab10")
    method_colours = {
        method: colours(idx % 10) for idx, method in enumerate(DISTRIBUTION_METHODS)
    }
    fig, axes = plt.subplots(3, 1, figsize=(8.6, 8.8), sharex=True)
    n_methods = len(DISTRIBUTION_METHODS)
    group_gap = 1.15
    box_width = 0.55
    tick_positions = []

    for i_ret, retention in enumerate(RETENTION_ORDER):
        base = i_ret * (n_methods + group_gap)
        tick_positions.append(base + (n_methods - 1) / 2)
        for i_method, method in enumerate(DISTRIBUTION_METHODS):
            position = base + i_method
            rows = completed[
                (completed["retainedDirections"] == retention)
                & (completed["method"] == method)
            ]
            for ax, (metric, ylabel, ylim) in zip(axes, panels):
                values = rows[metric].dropna().to_numpy(dtype=float)
                if values.size == 0:
                    continue
                bp = ax.boxplot(
                    values,
                    positions=[position],
                    widths=box_width,
                    patch_artist=True,
                    showfliers=False,
                    whis=(5, 95),
                    medianprops={"color": "black", "linewidth": 1.2},
                    boxprops={"linewidth": 0.8},
                    whiskerprops={"linewidth": 0.8},
                    capprops={"linewidth": 0.8},
                )
                for patch in bp["boxes"]:
                    patch.set_facecolor(method_colours[method])
                    patch.set_alpha(0.78)
                if ylim is not None:
                    ax.set_ylim(*ylim)
                ax.set_ylabel(ylabel)
                ax.grid(True, axis="y", color="0.88", linewidth=0.7)
                ax.set_axisbelow(True)

    axes[-1].set_xticks(tick_positions, [str(v) for v in RETENTION_ORDER])
    axes[-1].set_xlabel("Retained directions")
    handles = [
        Patch(facecolor=method_colours[m], alpha=0.78, label=METHOD_LABELS[m])
        for m in DISTRIBUTION_METHODS
    ]
    fig.legend(handles=handles, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.015))
    fig.tight_layout(rect=(0, 0, 1, 0.965))
    save_figure(fig, "subject_distribution_boxplots")


def bayesian_distribution_boxplots(df: pd.DataFrame) -> None:
    completed = df[
        (df["status"] == "completed")
        & (df["method"].isin(DISTRIBUTION_METHODS))
    ].copy()
    n_methods = len(DISTRIBUTION_METHODS)
    group_gap = 1.65
    box_width = 0.72
    tick_positions = []

    fig = plt.figure(figsize=(9.8, 13.25))
    outer = fig.add_gridspec(
        3, 1,
        height_ratios=[5.25, 2.28, 2.28],
        hspace=0.18,
        top=0.93,
        bottom=0.062,
        left=0.088,
        right=0.985,
    )
    lat_gs = outer[0].subgridspec(
        3, 1,
        height_ratios=[1.45, 1.65, 2.25],
        hspace=0.045,
    )
    lat_axes = [fig.add_subplot(lat_gs[i, 0]) for i in range(3)]
    polar_ax = fig.add_subplot(outer[1, 0])
    qe_ax = fig.add_subplot(outer[2, 0])
    all_axes = lat_axes + [polar_ax, qe_ax]

    colours = plt.get_cmap("tab10")
    method_colours = {
        method: colours(idx % 10) for idx, method in enumerate(DISTRIBUTION_METHODS)
    }

    def draw_metric(ax, metric, set_ticks=False):
        for i_ret, retention in enumerate(RETENTION_ORDER):
            base = i_ret * (n_methods + group_gap)
            if set_ticks:
                tick_positions.append(base + (n_methods - 1) / 2)
            for i_method, method in enumerate(DISTRIBUTION_METHODS):
                position = base + i_method
                rows = completed[
                    (completed["retainedDirections"] == retention)
                    & (completed["method"] == method)
                ]
                values = rows[metric].dropna().to_numpy(dtype=float)
                if values.size == 0:
                    continue
                bp = ax.boxplot(
                    values,
                    positions=[position],
                    widths=box_width,
                    patch_artist=True,
                    showfliers=False,
                    whis=(5, 95),
                    medianprops={"color": "black", "linewidth": 1.08},
                    boxprops={"linewidth": 0.8},
                    whiskerprops={"linewidth": 0.8},
                    capprops={"linewidth": 0.8},
                )
                for patch in bp["boxes"]:
                    patch.set_facecolor(method_colours[method])
                    patch.set_alpha(0.86)

    lateral_ranges = [(27.25, 28.65), (7.7, 19.7), (-0.35, 6.35)]
    for ax, ylim in zip(lat_axes, lateral_ranges):
        draw_metric(ax, "relativeLateralRMSErrorDeg", set_ticks=(ax is lat_axes[0]))
        ax.set_ylim(*ylim)

    draw_metric(polar_ax, "relativeLocalPolarRMSErrorDeg")
    draw_metric(qe_ax, "relativeQuadrantErrorPercentagePoints")

    for ax, metric in [
        (polar_ax, "relativeLocalPolarRMSErrorDeg"),
        (qe_ax, "relativeQuadrantErrorPercentagePoints"),
    ]:
        values = completed[metric].dropna().to_numpy(dtype=float)
        if values.size:
            lower = min(0.0, float(np.nanmin(values)))
            upper = float(np.nanmax(values))
            pad = max(0.75, 0.08 * (upper - lower))
            ax.set_ylim(lower - pad, upper + pad)

    for ax in all_axes:
        ax.grid(True, axis="y", color="0.88", linewidth=0.7)
        ax.set_axisbelow(True)
        ax.set_xlim(
            -0.85,
            (len(RETENTION_ORDER) - 1) * (n_methods + group_gap)
            + n_methods
            - 0.15,
        )

    for ax in lat_axes[:-1]:
        ax.spines["bottom"].set_visible(False)
        ax.tick_params(labelbottom=False, bottom=False)
    for ax in lat_axes[1:]:
        ax.spines["top"].set_visible(False)

    for upper, lower in [(lat_axes[0], lat_axes[1]), (lat_axes[1], lat_axes[2])]:
        d = 0.006
        kwargs = {"color": "k", "clip_on": False, "linewidth": 0.75}
        upper.plot((-d, +d), (-d, +d), transform=upper.transAxes, **kwargs)
        upper.plot((1 - d, 1 + d), (-d, +d), transform=upper.transAxes, **kwargs)
        lower.plot((-d, +d), (1 - d, 1 + d), transform=lower.transAxes, **kwargs)
        lower.plot((1 - d, 1 + d), (1 - d, 1 + d), transform=lower.transAxes, **kwargs)

    for ax in lat_axes + [polar_ax]:
        ax.tick_params(labelbottom=False, bottom=False)
    qe_ax.set_xticks(tick_positions, [str(v) for v in RETENTION_ORDER])
    qe_ax.set_xlabel("Retained directions")

    lat_axes[1].set_ylabel("Relative lateral RMS (deg)", labelpad=10)
    polar_ax.set_ylabel("Relative local polar RMS (deg)", labelpad=8)
    qe_ax.set_ylabel("Relative quadrant error (pp)", labelpad=8)

    handles = [
        Patch(facecolor=method_colours[m], alpha=0.86, label=METHOD_LABELS[m])
        for m in DISTRIBUTION_METHODS
    ]
    fig.legend(
        handles=handles,
        loc="upper center",
        ncol=3,
        frameon=False,
        bbox_to_anchor=(0.5, 0.99),
    )
    for suffix in (".pdf", ".png"):
        fig.savefig(
            FIG_DIR / f"bayesian_subject_boxplots{suffix}",
            dpi=300,
            bbox_inches="tight",
            pad_inches=0.035,
        )
    plt.close(fig)


def lsd_distribution_boxplot(df: pd.DataFrame) -> None:
    completed = df[
        (df["status"] == "completed")
        & (df["method"].isin(DISTRIBUTION_METHODS))
    ].copy()
    colours = plt.get_cmap("tab10")
    method_colours = {
        method: colours(idx % 10) for idx, method in enumerate(DISTRIBUTION_METHODS)
    }
    fig, ax = plt.subplots(figsize=(8.6, 3.8))
    n_methods = len(DISTRIBUTION_METHODS)
    group_gap = 1.15
    box_width = 0.55
    tick_positions = []

    for i_ret, retention in enumerate(RETENTION_ORDER):
        base = i_ret * (n_methods + group_gap)
        tick_positions.append(base + (n_methods - 1) / 2)
        for i_method, method in enumerate(DISTRIBUTION_METHODS):
            position = base + i_method
            values = completed[
                (completed["retainedDirections"] == retention)
                & (completed["method"] == method)
            ]["LSDdB"].dropna().to_numpy(dtype=float)
            if values.size == 0:
                continue
            bp = ax.boxplot(
                values,
                positions=[position],
                widths=box_width,
                patch_artist=True,
                showfliers=False,
                whis=(5, 95),
                medianprops={"color": "black", "linewidth": 1.2},
                boxprops={"linewidth": 0.8},
                whiskerprops={"linewidth": 0.8},
                capprops={"linewidth": 0.8},
            )
            for patch in bp["boxes"]:
                patch.set_facecolor(method_colours[method])
                patch.set_alpha(0.78)

    ax.set_xticks(tick_positions, [str(v) for v in RETENTION_ORDER])
    ax.set_xlabel("Retained directions")
    ax.set_ylabel("LSD (dB)")
    ax.grid(True, axis="y", color="0.88", linewidth=0.7)
    ax.set_axisbelow(True)
    handles = [
        Patch(facecolor=method_colours[m], alpha=0.78, label=METHOD_LABELS[m])
        for m in DISTRIBUTION_METHODS
    ]
    fig.legend(handles=handles, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.08))
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    save_figure(fig, "lsd_subject_boxplot")


def latex_num(value: float, digits: int = 2) -> str:
    if not np.isfinite(value):
        return "--"
    return f"{value:.{digits}f}"


def write_airm_table(agg: pd.DataFrame, n_subjects: int) -> None:
    rows = []
    for method in METHOD_ORDER:
        method_rows = agg[agg["method"] == method].set_index("retainedDirections")
        vals = [latex_num(method_rows.loc[n, "meanAIRM"], 2) if n in method_rows.index else "--" for n in RETENTION_ORDER]
        rows.append((METHOD_LABELS[method], vals))

    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        f"\\caption{{Mean AIRM discrepancy over the {n_subjects}-subject SONICOM evaluation cohort. Lower values indicate closer preservation of the reference Fisher tensor field.}}",
        "\\label{tab:airm_summary}",
        "\\small",
        "\\begin{tabular}{lrrrr}",
        "\\toprule",
        "Method & $N=100$ & $N=19$ & $N=5$ & $N=3$ \\\\",
        "\\midrule",
    ]
    for label, vals in rows:
        lines.append(f"{label} & " + " & ".join(vals) + " \\\\")
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "airm_summary_table.tex").write_text("\n".join(lines), encoding="utf-8")


def write_tensor_component_mean_table(agg: pd.DataFrame) -> None:
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{Mean secondary Fisher-tensor component errors over the 41-subject cohort for the principal comparison set. Dashes denote conditions that are not applicable or for which the component summary is undefined under the stated validity criteria.}",
        "\\label{tab:tensor_component_means}",
        "\\scriptsize",
        "\\begin{tabular}{llrrrr}",
        "\\toprule",
        "Component & Method & $N=100$ & $N=19$ & $N=5$ & $N=3$ \\\\",
        "\\midrule",
    ]
    components = [
        ("Log-det.", "determinant", 2),
        ("Anisotropy", "anisotropy", 2),
        ("Orientation ($^\\circ$)", "orientation", 1),
    ]
    for i_component, (component_label, column, digits) in enumerate(components):
        if i_component:
            lines.append("\\addlinespace")
        for method in DISTRIBUTION_METHODS:
            rows = agg[agg["method"] == method].set_index("retainedDirections")
            vals = []
            for retention in RETENTION_ORDER:
                if retention not in rows.index:
                    vals.append("--")
                else:
                    vals.append(latex_num(rows.loc[retention, column], digits))
            lines.append(
                f"{component_label} & {METHOD_LABELS[method]} & "
                + " & ".join(vals)
                + " \\\\"
            )
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "tensor_component_mean_table.tex").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def write_airm_median_iqr_table(df: pd.DataFrame) -> None:
    completed = df[
        (df["status"] == "completed")
        & (df["method"].isin(DISTRIBUTION_METHODS))
    ].copy()
    summary = (
        completed.groupby(["method", "retainedDirections"])["meanAIRM"]
        .agg(
            median="median",
            q1=lambda x: x.quantile(0.25),
            q3=lambda x: x.quantile(0.75),
        )
        .reset_index()
    )
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{Subject-wise median and interquartile range of mean AIRM for the core distributional comparison. Values are reported as median [Q1, Q3] across the 41 held-out subjects.}",
        "\\label{tab:airm_median_iqr}",
        "\\small",
        "\\begin{tabular}{lrrrr}",
        "\\toprule",
        "Method & $N=100$ & $N=19$ & $N=5$ & $N=3$ \\\\",
        "\\midrule",
    ]
    for method in DISTRIBUTION_METHODS:
        rows = summary[summary["method"] == method].set_index("retainedDirections")
        vals = []
        for retention in RETENTION_ORDER:
            if retention not in rows.index:
                vals.append("--")
                continue
            row = rows.loc[retention]
            vals.append(
                f"{latex_num(row['median'], 2)} "
                f"[{latex_num(row['q1'], 2)}, {latex_num(row['q3'], 2)}]"
            )
        lines.append(f"{METHOD_LABELS[method]} & " + " & ".join(vals) + " \\\\")
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "airm_median_iqr_table.tex").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def median_iqr_string(values: pd.Series, digits: int = 2) -> str:
    clean = pd.to_numeric(values, errors="coerce").dropna()
    if clean.empty:
        return "--"
    median = clean.median()
    q1 = clean.quantile(0.25)
    q3 = clean.quantile(0.75)
    return f"{latex_num(median, digits)} [{latex_num(q1, digits)}, {latex_num(q3, digits)}]"


def write_lsd_median_iqr_table(df: pd.DataFrame) -> None:
    completed = df[
        (df["status"] == "completed")
        & (df["method"].isin(DISTRIBUTION_METHODS))
    ].copy()
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{Subject-wise median and interquartile range of LSD for the core distributional comparison. Values are reported as median [Q1, Q3] in dB across the 41 held-out subjects.}",
        "\\label{tab:lsd_median_iqr}",
        "\\small",
        "\\begin{tabular}{lrrrr}",
        "\\toprule",
        "Method & $N=100$ & $N=19$ & $N=5$ & $N=3$ \\\\",
        "\\midrule",
    ]
    for method in DISTRIBUTION_METHODS:
        vals = []
        for retention in RETENTION_ORDER:
            rows = completed[
                (completed["method"] == method)
                & (completed["retainedDirections"] == retention)
            ]
            vals.append(median_iqr_string(rows["LSDdB"], 2))
        lines.append(f"{METHOD_LABELS[method]} & " + " & ".join(vals) + " \\\\")
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "lsd_median_iqr_table.tex").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def write_bayesian_median_iqr_table(df: pd.DataFrame) -> None:
    completed = df[
        (df["status"] == "completed")
        & (df["method"].isin(DISTRIBUTION_METHODS))
    ].copy()
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{Subject-wise median and interquartile range of selected Bayesian-observer degradation metrics for the core distributional comparison. Values are reported as median [Q1, Q3] relative to the dense self-reference condition.}",
        "\\label{tab:bayesian_median_iqr}",
        "\\small",
        "\\begin{tabular}{lrlll}",
        "\\toprule",
        "Method & $N$ & Rel. lateral RMS ($^\\circ$) & Rel. polar RMS ($^\\circ$) & Rel. QE (pp) \\\\",
        "\\midrule",
    ]
    for retention in [19, 5, 3]:
        for method in DISTRIBUTION_METHODS:
            rows = completed[
                (completed["method"] == method)
                & (completed["retainedDirections"] == retention)
            ]
            if rows.empty:
                continue
            lines.append(
                f"{METHOD_LABELS[method]} & {retention} & "
                f"{median_iqr_string(rows['relativeLateralRMSErrorDeg'], 2)} & "
                f"{median_iqr_string(rows['relativeLocalPolarRMSErrorDeg'], 2)} & "
                f"{median_iqr_string(rows['relativeQuadrantErrorPercentagePoints'], 2)} \\\\"
            )
        if retention != 3:
            lines.append("\\addlinespace")
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "bayesian_median_iqr_table.tex").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def write_best_methods_table(agg: pd.DataFrame) -> None:
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{Best-performing method at each retention condition under selected metrics. Values are cohort means.}",
        "\\label{tab:best_methods}",
        "\\small",
        "\\begin{tabular}{rlll}",
        "\\toprule",
        "$N$ & AIRM & LSD & Relative local polar RMS \\\\",
        "\\midrule",
    ]
    for retention in RETENTION_ORDER:
        rows = agg[agg["retainedDirections"] == retention]
        best_airm = rows.loc[rows["meanAIRM"].idxmin()]
        best_lsd = rows.loc[rows["LSDdB"].idxmin()]
        best_polar = rows.loc[rows["relPolar"].idxmin()]
        lines.append(
            f"{retention} & {METHOD_LABELS[best_airm['method']]} ({latex_num(best_airm['meanAIRM'], 2)}) "
            f"& {METHOD_LABELS[best_lsd['method']]} ({latex_num(best_lsd['LSDdB'], 2)} dB) "
            f"& {METHOD_LABELS[best_polar['method']]} ({latex_num(best_polar['relPolar'], 2)}$^\\circ$) \\\\"
        )
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "best_methods_table.tex").write_text("\n".join(lines), encoding="utf-8")


def write_ranf_sam_table(sam: pd.DataFrame) -> None:
    if sam.empty:
        return
    agg = (
        sam.groupby("retention", as_index=False)
        .agg(
            subjects=("subjectId", "count"),
            itd=("lapITDErrorUs", "mean"),
            ild=("lapILDErrorDb", "mean"),
            lsd=("lapLSDdB", "mean"),
        )
        .set_index("retention")
        .reindex(RETENTION_ORDER)
    )
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{LAP/SAM objective metrics for the RANF comparator over the 41-subject SONICOM test cohort. Values are cohort means and are computed with the Spatial Audio Metrics LAP Task~2 convention.}",
        "\\label{tab:ranf_sam_metrics}",
        "\\small",
        "\\begin{tabular}{rrrr}",
        "\\toprule",
        "$N$ & ITD error ($\\mu$s) & ILD error (dB) & LSD (dB) \\\\",
        "\\midrule",
    ]
    for retention, row in agg.iterrows():
        lines.append(
            f"{int(retention)} & {latex_num(row['itd'], 2)} & "
            f"{latex_num(row['ild'], 2)} & {latex_num(row['lsd'], 2)} \\\\"
        )
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    (TABLE_DIR / "ranf_sam_metrics_table.tex").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def write_aggregate_csv(agg: pd.DataFrame) -> None:
    agg.to_csv(TABLE_DIR / "aggregate_metrics.csv", index=False)


def main() -> None:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    TABLE_DIR.mkdir(parents=True, exist_ok=True)
    configure_matplotlib()
    df = load_summary()
    sam = load_sam_metrics()
    n_subjects = int(df["subjectId"].nunique())
    agg = aggregate_completed(df)
    write_aggregate_csv(agg)
    airm_heatmap(agg)
    metric_relationships(df)
    tensor_component_bars(agg)
    subject_distribution_boxplots(df)
    bayesian_distribution_boxplots(df)
    lsd_distribution_boxplot(df)
    write_airm_table(agg, n_subjects)
    write_tensor_component_mean_table(agg)
    write_airm_median_iqr_table(df)
    write_lsd_median_iqr_table(df)
    write_bayesian_median_iqr_table(df)
    write_best_methods_table(agg)
    write_ranf_sam_table(sam)
    print(f"Wrote figures to {FIG_DIR}")
    print(f"Wrote tables to {TABLE_DIR}")


if __name__ == "__main__":
    main()


