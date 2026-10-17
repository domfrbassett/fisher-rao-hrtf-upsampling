"""Reference cue fields of one listener and the magnitudes of their whitened gradients.

Top row: SH-fitted (degree 6) ITD, ILD and three left-ear PGE components over azimuth and elevation.
Bottom row: |grad q_m| / sigma_m, the d' produced by a 1-degree displacement along the direction of
steepest change when that cue is used alone. The Fisher tensor sums the outer products of these
whitened gradients over all cues.

Input:  results/evaluation/analysis/cue_fields/reference_cues.npz (scripts/cue_fields/extract_reference_cues.py)
Output: paper/figures/cue_maps.pdf
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, TwoSlopeNorm
from matplotlib.ticker import FuncFormatter, LogLocator, NullFormatter

from plot_summary_figures import configure_matplotlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "cue_fields"))
import cue_pipeline as cp  # noqa: E402

CUES = ROOT / "results" / "evaluation" / "analysis" / "cue_fields" / "reference_cues.npz"
FIG_DIR = ROOT / "paper" / "figures"
SUBJECT = 10
L_MAX = 6
PGE_FREQS = (5750.0, 8036.0, 11197.0)


def unit(az_deg: np.ndarray, el_deg: np.ndarray) -> np.ndarray:
    a, e = np.radians(az_deg), np.radians(el_deg)
    return np.stack([np.cos(e) * np.cos(a), np.cos(e) * np.sin(a), np.sin(e)], -1)


def azel_axes(ax, xlabel: bool, ylabel: bool) -> None:
    ax.set_xlim(180, -180)                       # listener's left on the left
    ax.set_ylim(-45, 90)
    ax.set_aspect("equal")
    ax.set_xticks([180, 90, 0, -90, -180])
    ax.set_yticks([-45, 0, 45, 90])
    ax.tick_params(labelsize=11, length=2.5)
    if xlabel:
        ax.set_xlabel(r"Azimuth ($^\circ$)")
    else:
        ax.set_xticklabels([])
    if ylabel:
        ax.set_ylabel(r"Elevation ($^\circ$)")
    else:
        ax.set_yticklabels([])


def colorbar(fig, mappable, ax, label: str, log: bool = False) -> None:
    cb = fig.colorbar(mappable, ax=ax, orientation="horizontal", location="bottom", shrink=0.85,
                      aspect=28, pad=0.03)
    cb.outline.set_linewidth(0.5)
    if log:
        lo, hi = mappable.norm.vmin, mappable.norm.vmax
        subs = (1.0, 2.0, 5.0) if hi / lo > 6 else (1.0, 1.5, 2.0, 3.0, 5.0)
        ticks = [m * 10.0 ** k for k in range(int(np.floor(np.log10(lo))), int(np.ceil(np.log10(hi))) + 1)
                 for m in subs if lo <= m * 10.0 ** k <= hi]
        cb.ax.xaxis.set_minor_formatter(NullFormatter())
        cb.ax.xaxis.set_minor_locator(LogLocator(subs="all", numticks=12))
        cb.set_ticks(ticks)
        cb.ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
    cb.set_label(label, fontsize=12)
    cb.ax.tick_params(labelsize=10, length=2)


def main() -> None:
    configure_matplotlib()
    data = np.load(CUES)
    r, fam, q = data["r"], data["fam"], data[f"q_{SUBJECT}"]
    sigma = cp.sigma_vec(fam)

    az = np.arange(-180.0, 180.1, 1.0)
    el = np.arange(-45.0, 90.1, 1.0)
    A, E = np.meshgrid(az, el)
    rq = unit(A.ravel(), np.clip(E.ravel(), -89.9, 89.9))
    coef = cp.fit_sh(r, q, L_MAX)
    field = cp.real_sh(rq, L_MAX)[0] @ coef
    J = cp.tangent_jacobian(coef, rq, L_MAX)
    grad = np.sqrt((J ** 2).sum(-1)) / sigma * np.pi / 180      # d' per degree, per cue

    fc = cp.erb_centres()[1:]                    # PGE component b sits at the upper band of each pair
    n_pge = int(np.sum(fam == 0) // 2)
    panels = [("ITD", q.shape[1] - 1, "ITD (JND)", True),
              ("ILD", q.shape[1] - 2, "ILD (dB)", True)]
    for f in PGE_FREQS:
        b = int(np.argmin(np.abs(fc[:n_pge] - f)))
        panels.append((f"PGE, left ear, {fc[b] / 1000:.1f} kHz", b, "PGE (dB/ERB)", False))

    fig, axes = plt.subplots(2, len(panels), figsize=(14.0, 4.35), constrained_layout=True)
    fig.get_layout_engine().set(w_pad=0.02, h_pad=0.02, wspace=0.02, hspace=0.02)
    for i, (title, idx, unit_label, diverging) in enumerate(panels):
        f = field[:, idx].reshape(A.shape)
        g = grad[:, idx].reshape(A.shape)
        ax = axes[0, i]
        if diverging:
            lim = np.percentile(np.abs(f), 99.5)
            m = ax.pcolormesh(A, E, f, cmap="RdBu_r", norm=TwoSlopeNorm(0.0, -lim, lim), shading="auto",
                              rasterized=True)
            ax.contour(A, E, f, levels=np.linspace(-lim, lim, 13), colors="k", linewidths=0.3, alpha=0.5)
        else:
            m = ax.pcolormesh(A, E, f, cmap="viridis", vmin=0.0, vmax=np.percentile(f, 99.5),
                              shading="auto", rasterized=True)
        azel_axes(ax, xlabel=False, ylabel=i == 0)
        ax.set_title(title, fontsize=12.5, pad=4)
        ax.text(0.0, 1.03, f"({'abcde'[i]})", transform=ax.transAxes, fontsize=12, ha="left", va="bottom")
        colorbar(fig, m, ax, unit_label)

        ax = axes[1, i]
        m = ax.pcolormesh(A, E, g, cmap="magma", norm=LogNorm(np.percentile(g, 2), np.percentile(g, 99.7)),
                          shading="auto", rasterized=True)
        azel_axes(ax, xlabel=True, ylabel=i == 0)
        ax.text(0.0, 1.03, f"({'fghij'[i]})", transform=ax.transAxes, fontsize=12, ha="left", va="bottom")
        colorbar(fig, m, ax, r"$\|\nabla q_m\|/\sigma_m$ ($d'$ per degree)", log=True)

    fig.savefig(FIG_DIR / "cue_maps.pdf", dpi=300)
    plt.close(fig)


if __name__ == "__main__":
    main()
