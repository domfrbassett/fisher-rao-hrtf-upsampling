"""Figures drawn from the evaluation summary (results/evaluation/full_evaluation_summary.csv).

Outputs (paper/figures/)
  airm_heatmap.pdf                  mean AIRM per method and retention level
  bayesian_subject_boxplots.pdf     observer metrics relative to the dense self-reference
  metric_relationships_paper.pdf    AIRM against LSD and against relative local polar error

The CRB/observer ellipse figure comes from plot_ellipse_figures.py.
"""
from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pandas as pd

import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, to_rgb
from matplotlib.patches import Patch


ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = Path(os.environ.get("FISHERRAO_RESULT_ROOT", ROOT / "results" / "evaluation"))
SUMMARY_CSV = RESULT_ROOT / "full_evaluation_summary.csv"
FIG_DIR = ROOT / "paper" / "figures"

METHOD_ORDER = [
    "SUpDEq_SH",
    "SUpDEq_MCA",
    "SUpDEq_NN_MCA_6dB",
    "SUpDEq_Bary_MCA_6dB",
    "RANF",
    "FSP_AE",
]

METHOD_LABELS = {
    "SUpDEq_SH": "SUpDEq-SH",
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
    # Every method is scored on the common 20 Hz--16 kHz band (LSD) and on the
    # 16 kHz low-passed fields (ILD error).
    df["LSDdB"] = df["LSDdB_16k"]
    df["ILDErrorDb"] = df["ILDErrorDb_16k"]
    df = df[df["method"].isin(METHOD_ORDER)].copy()
    numeric_cols = [
        "retainedDirections",
        "meanAIRM",
        "LSDdB",
        "ILDErrorDb",
        "relativeLateralRMSErrorDeg",
        "relativeLocalPolarRMSErrorDeg",
        "relativeQuadrantErrorPercentagePoints",
    ]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def mean_airm_by_condition(df: pd.DataFrame) -> pd.DataFrame:
    completed = df[df["status"] == "completed"]
    return completed.groupby(["method", "retainedDirections"], as_index=False).agg(
        meanAIRM=("meanAIRM", "mean")
    )


def save_figure(fig: plt.Figure, name: str) -> None:
    fig.savefig(FIG_DIR / f"{name}.pdf", dpi=300)
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
    fig, ax = plt.subplots(figsize=(5.2, 3.9))
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

    axes[0].set_xlabel("LSD, 20 Hz–16 kHz (dB)")
    axes[0].set_ylabel("Mean AIRM")
    axes[1].set_xlabel("Relative local polar RMS (deg)")
    axes[1].set_ylabel("Mean AIRM")
    for ax in axes:
        ax.set_yscale("log")
        ax.set_yticks([0.3, 0.5, 1, 2, 5, 10], ["0.3", "0.5", "1", "2", "5", "10"])
        ax.minorticks_off()
        ax.grid(True, color="0.88", linewidth=0.7)
        ax.set_axisbelow(True)
    axes[1].legend(title="Retained", frameon=False, loc="upper left")
    fig.tight_layout()
    save_figure(fig, "metric_relationships_paper")


def _data_segments(intervals, gap_fraction=0.15):
    """Merge box/whisker extents into y-ranges, breaking only at empty gaps.

    intervals: (low, high) whisker extents of every drawn box. A break is placed
    wherever no box occupies a gap wider than gap_fraction of the data span;
    otherwise a single continuous range is returned.
    """
    iv = sorted(intervals + [(0.0, 0.0)])
    span = max(h for _, h in iv) - min(l for l, _ in iv)
    segments = [list(iv[0])]
    for lo, hi in iv[1:]:
        if lo - segments[-1][1] > gap_fraction * span:
            segments.append([lo, hi])
        else:
            segments[-1][1] = max(segments[-1][1], hi)
    out = []
    for lo, hi in segments:
        pad = max(0.08 * (hi - lo), 0.03 * span, 0.2)
        out.append((lo - pad, hi + pad))
    return out


def bayesian_distribution_boxplots(df: pd.DataFrame) -> None:
    """Subject-wise boxplots, one column per retention level with its own y-range.

    Rows are the three observer metrics. Each panel is scaled to its own data so
    that medians and interquartile ranges stay legible, and a panel's axis is
    split only where its boxes leave an empty gap.
    """
    completed = df[(df["status"] == "completed") & (df["method"].isin(METHOD_ORDER))].copy()
    colours = plt.get_cmap("tab10")
    method_colours = {m: colours(i % 10) for i, m in enumerate(METHOD_ORDER)}
    panels = [
        ("relativeLateralRMSErrorDeg", "Lateral RMS\n(deg)"),
        ("relativeLocalPolarRMSErrorDeg", "Local polar RMS\n(deg)"),
        ("relativeQuadrantErrorPercentagePoints", "Quadrant error\n(pp)"),
    ]
    methods_at = {n: [m for m in METHOD_ORDER
                      if completed[(completed.retainedDirections == n) & (completed.method == m)].shape[0]]
                  for n in RETENTION_ORDER}

    fig = plt.figure(figsize=(7.0, 6.2))
    outer = fig.add_gridspec(3, len(RETENTION_ORDER), hspace=0.12, wspace=0.42,
                             width_ratios=[len(methods_at[n]) for n in RETENTION_ORDER],
                             top=0.88, bottom=0.03, left=0.12, right=0.99)
    for r, (metric, label) in enumerate(panels):
        for c, n in enumerate(RETENTION_ORDER):
            methods = methods_at[n]
            values = {m: completed[(completed.retainedDirections == n) & (completed.method == m)][metric]
                      .dropna().to_numpy(float) for m in methods}
            extents = [(float(np.percentile(v, 5)), float(np.percentile(v, 95))) for v in values.values() if v.size]
            segments = _data_segments(extents)[::-1]            # top segment first
            spans = np.array([hi - lo for lo, hi in segments])
            ratios = np.maximum(spans, 0.35 * spans.max())
            inner = outer[r, c].subgridspec(len(segments), 1, height_ratios=ratios, hspace=0.08)
            axes = [fig.add_subplot(inner[i]) for i in range(len(segments))]
            for ax, (lo, hi) in zip(axes, segments):
                for k, m in enumerate(methods):
                    bp = ax.boxplot(values[m], positions=[k], widths=0.7, patch_artist=True,
                                    showfliers=False, whis=(5, 95),
                                    medianprops={"color": "black", "linewidth": 1.1},
                                    boxprops={"linewidth": 0.6}, whiskerprops={"linewidth": 0.6},
                                    capprops={"linewidth": 0.6})
                    for patch in bp["boxes"]:
                        patch.set_facecolor(method_colours[m])
                        patch.set_alpha(0.86)
                ax.set_ylim(lo, hi)
                ax.set_xlim(-0.6, len(methods) - 0.4)
                ax.axhline(0, color="0.45", linewidth=0.5)
                ax.grid(True, axis="y", color="0.9", linewidth=0.6)
                ax.set_axisbelow(True)
                ax.tick_params(axis="x", bottom=False, labelbottom=False)
                ax.tick_params(axis="y", labelsize=10, length=2.5, pad=1.5)
                ax.yaxis.set_major_locator(plt.MaxNLocator(nbins=4 if ax is axes[-1] else 2, min_n_ticks=2))
            for upper, lower in zip(axes[:-1], axes[1:]):
                upper.spines["bottom"].set_visible(False)
                lower.spines["top"].set_visible(False)
                d = 0.03
                kw = {"color": "k", "clip_on": False, "linewidth": 0.7}
                for x in (0, 1):
                    upper.plot((x - d, x + d), (-d, d), transform=upper.transAxes, **kw)
                    lower.plot((x - d, x + d), (1 - d, 1 + d), transform=lower.transAxes, **kw)
            if r == 0:
                axes[0].set_title(f"$N={n}$", fontsize=12, pad=4)
            if c == 0:
                holder = fig.add_subplot(outer[r, c], frameon=False)
                holder.tick_params(labelleft=False, labelbottom=False, left=False, bottom=False)
                holder.set_ylabel(label, labelpad=26)
    handles = [Patch(facecolor=method_colours[m], alpha=0.86, label=METHOD_LABELS[m])
               for m in METHOD_ORDER]
    fig.legend(handles=handles, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.55, 1.0))
    fig.savefig(FIG_DIR / "bayesian_subject_boxplots.pdf", dpi=300, bbox_inches="tight", pad_inches=0.03)
    plt.close(fig)


def main() -> None:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    configure_matplotlib()
    df = load_summary()
    airm_heatmap(mean_airm_by_condition(df))
    metric_relationships(df)
    bayesian_distribution_boxplots(df)
    print(f"Wrote figures to {FIG_DIR}")


if __name__ == "__main__":
    main()
