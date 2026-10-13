"""Template-matched (unadapted) sensitivity of reconstructed cue fields.

The Fisher tensor of a reconstruction describes an observer adapted to the reconstructed field.
A listener who decodes with templates learned from their own ears instead discriminates along the
cue change their own ears would produce. For a linear observer of this kind, the sensitivity to a
displacement rho*u, relative to the reference, is

    r(u) = (J u)' Sigma^-1 (J_hat u) / (u' g u),        g = J' Sigma^-1 J,

whereas the adapted ratio is a(u) = sqrt(u' g_hat u / u' g u). If the reconstruction only rescales
the expected cue change, r = a; cue variation orthogonal to it adds nothing to r, and opposing
variation makes r smaller or negative (reversed judgements). By Cauchy-Schwarz, |r| <= a.

Inputs: metric-tensor files written by run_evaluation("tensors", ...), which include the
cross terms J_target' J_recon per cue family. Several result roots (parallel workers) can be given.

Every summary is reported for all cues together and separately for the spectral (PGE) and the
interaural (ILD + ITD) families. For a single scalar cue the template reduces to the direction in
which the cue changes, so interaural gains stay gains unless the cue changes the wrong way; the
template argument bites for the multidimensional spectral cues.

Outputs (results/evaluation/analysis/):
  template_matched_rows.csv      one row per subject x method x retention level
  template_matched_summary.csv   medians over subjects per method x retention level
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

import numpy as np
import pandas as pd

import fisher_lib as F

REPO = Path(__file__).resolve().parents[1]
N_ANGLES = 36          # displacement directions u over [0, pi); u and -u are equivalent
FAMILIES = {"all": (0, 1, 2), "spectral": (0,), "interaural": (1, 2)}
GAIN = 1.02            # ratio counted as a gain (2% tolerance against numerical noise)
LOSS = 1 / GAIN        # ratio counted as a loss


def unit_directions(n: int = N_ANGLES) -> np.ndarray:
    th = np.pi * np.arange(n) / n
    return np.stack([np.cos(th), np.sin(th)], 1)


def ratios(g: np.ndarray, ghat: np.ndarray, cross: np.ndarray, eta: float = F.ETA):
    """Adapted a(u) and template-matched r(u) for stacks of 2x2 tensors; shapes (dir, n_angles)."""
    U = unit_directions()
    ge = g + eta * np.eye(2)
    q_ref = np.einsum("ui,nij,uj->nu", U, ge, U)
    q_hat = np.einsum("ui,nij,uj->nu", U, ghat + eta * np.eye(2), U)
    q_x = np.einsum("ui,nij,uj->nu", U, cross, U)
    return np.sqrt(q_hat / q_ref), q_x / q_ref


def cauchy_schwarz_ok(g, ghat, cross) -> bool:
    U = unit_directions()
    q_ref = np.einsum("ui,nij,uj->nu", U, g, U)
    q_hat = np.einsum("ui,nij,uj->nu", U, ghat, U)
    q_x = np.einsum("ui,nij,uj->nu", U, cross, U)
    return bool(np.all(np.abs(q_x) <= np.sqrt(q_ref * q_hat) * (1 + 1e-6) + 1e-9))


def row_summary(a: np.ndarray, r: np.ndarray) -> dict:
    gain = a > GAIN
    out = {
        "mean_log_adapted": float(np.mean(np.log(a))),
        "median_template_ratio": float(np.median(r)),
        "frac_adapted_gain": float(gain.mean()),
        "frac_template_loss": float((r < LOSS).mean()),
        "frac_template_reversal": float((r < 0).mean()),
    }
    if gain.any():
        out["frac_gain_not_realised"] = float((r[gain] < GAIN).mean())
        out["frac_gain_to_loss"] = float((r[gain] < LOSS).mean())
        out["frac_gain_to_reversal"] = float((r[gain] < 0).mean())
        out["median_template_ratio_where_gain"] = float(np.median(r[gain]))
    else:
        out.update(frac_gain_not_realised=np.nan, frac_gain_to_loss=np.nan, frac_gain_to_reversal=np.nan,
                   median_template_ratio_where_gain=np.nan)
    return out


def family_sum(stack: np.ndarray, families, order: int, sigma_mon: float) -> np.ndarray:
    """Noise-weighted sum over the chosen cue families of a (order, family, dir, 2, 2) stack."""
    sig = (sigma_mon, F.SIGMA["ild"], F.SIGMA["itd"])
    io = F.ORDERS.index(order)
    return sum(stack[io, f] / sig[f] ** 2 for f in families)


def analyse(roots: list[Path], order: int, sigma_mon: float) -> pd.DataFrame:
    rows = []
    pat = re.compile(r"(?P<method>.+)_N(?P<n>\d{3})_metric_tensor\.mat$")
    for root in roots:
        for subj_dir in sorted((root / "metric_tensors").glob("subject_*")):
            sid = int(subj_dir.name.split("_")[1])
            ref = F.read_tensor_file(subj_dir / "reference_metric_tensor.mat")
            for path in sorted(subj_dir.glob("*_metric_tensor.mat")):
                m = pat.match(path.name)
                if not m or path.name.startswith("reference"):
                    continue
                rec = F.read_tensor_file(path)
                if rec["gram"] is None or "cross" not in rec:
                    continue                        # not applicable, or written without cross terms
                row = {"subjectId": sid, "method": m["method"], "N": int(m["n"]), "root": root.name}
                for fam, members in FAMILIES.items():
                    gf = family_sum(ref["gram"], members, order, sigma_mon)
                    ghat = family_sum(rec["gram"], members, order, sigma_mon)
                    C = family_sum(rec["cross"], members, order, sigma_mon)
                    if not cauchy_schwarz_ok(gf, ghat, C):
                        raise RuntimeError(f"Cauchy-Schwarz violated in {path} ({fam}): check the export")
                    a, r = ratios(gf, ghat, C)
                    prefix = "" if fam == "all" else fam + "_"
                    row.update({prefix + k: v for k, v in row_summary(a, r).items()})
                rows.append(row)
    df = pd.DataFrame(rows)
    if df.empty:
        raise SystemExit("No reconstruction tensor files with cross terms found.")
    dup = df.duplicated(["subjectId", "method", "N"], keep="last")
    if dup.any():
        print(f"{dup.sum()} duplicate rows from later roots replace earlier ones")
        df = df[~df.duplicated(["subjectId", "method", "N"], keep="last")]
    return df.sort_values(["method", "N", "subjectId"]).reset_index(drop=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roots", nargs="*", type=Path,
                    help="result folders (default: results/evaluation_tensors*)")
    ap.add_argument("--order", type=int, default=6)
    ap.add_argument("--sigma-mon", type=float, default=F.SIGMA["mon"])
    ap.add_argument("--out", type=Path, default=REPO / "results" / "evaluation" / "analysis")
    args = ap.parse_args()
    roots = args.roots or sorted((REPO / "results").glob("evaluation_tensors*"))
    df = analyse(roots, args.order, args.sigma_mon)
    tag = "" if (args.order, args.sigma_mon) == (6, F.SIGMA["mon"]) else f"_order{args.order}_sm{args.sigma_mon:g}"
    args.out.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.out / f"template_matched_rows{tag}.csv", index=False)
    cols = [c for c in df.columns if any(k in c for k in ("frac_", "median_", "mean_"))]
    summ = df.groupby(["method", "N"])[cols].median().reset_index()
    summ.insert(2, "nSubjects", df.groupby(["method", "N"]).size().values)
    summ.to_csv(args.out / f"template_matched_summary{tag}.csv", index=False)
    with pd.option_context("display.width", 200):
        show = ["method", "N", "nSubjects", "frac_adapted_gain", "frac_gain_not_realised", "frac_gain_to_loss",
                "spectral_frac_gain_to_loss", "interaural_frac_gain_to_loss", "frac_gain_to_reversal",
                "median_template_ratio_where_gain"]
        print(summ[show].round(3).to_string(index=False))


if __name__ == "__main__":
    main()
