"""Does the -45 deg boundary ring affect the Fisher-tensor results?

    python scripts/boundary_sensitivity.py results/evaluation

It needs the per-subject tensor files (results/evaluation/metric_tensors/), which the MATLAB
evaluation writes but git does not track. It recomputes every tensor from the stored Gram
matrices (SH order 6, sigma_mon = 1.25 dB, as in the paper) and reports:

1. Reference inflation: per subject, how much larger the Fisher information is on the lowest
   ring (-45 deg) than on the next ring up (-30 deg). A large ratio with no counterpart between
   other adjacent rings indicates an SH extrapolation artefact at the edge of the measured region.
2. Mean AIRM, signed log-det and the method ranking per retention level, over all 793
   directions (as reported), excluding the -45 deg ring, and excluding the -45 and -30 deg rings.

Output: <root>/analysis/boundary_sensitivity_{rows,cells,reference}.csv and a printed summary.
Whether the inflation is an artefact of the SH fit or real cue structure is checked against the
measured cues in scripts/cue_fields/boundary_raw_vs_sh.py.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

import fisher_lib as F

ORDER, SIGMA_MON = 6, 1.25


def tensor_path(root: Path, sid: int, method: str, n: int) -> Path:
    return root / "metric_tensors" / f"subject_{sid:04d}" / f"{method}_N{n:03d}_metric_tensor.mat"


def masks(el: np.ndarray) -> dict[str, np.ndarray]:
    rings = np.unique(np.round(el, 6))
    return {"all": np.ones_like(el, bool),
            "excl_m45": ~np.isclose(el, rings[0]),
            "excl_m45_m30": ~(np.isclose(el, rings[0]) | np.isclose(el, rings[1])),
            "only_m45": np.isclose(el, rings[0])}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path, nargs="?", default=Path("results/evaluation"))
    root = ap.parse_args().root
    df = pd.read_csv(root / "full_evaluation_summary.csv")
    df = df[df["status"].eq("completed")]

    refs, ref_rows = {}, []
    for sid in sorted(df.subjectId.unique()):
        r = F.read_tensor_file(root / "metric_tensors" / f"subject_{sid:04d}" / "reference_metric_tensor.mat")
        g = F.tensor_from_gram(r["gram"], ORDER, SIGMA_MON)
        el = r["azel"][:, 1]
        refs[sid] = (g, el)
        rings = np.unique(np.round(el, 6))
        root_det = np.sqrt(np.clip(np.linalg.det(g), 0, None))
        ring_med = np.array([np.median(root_det[np.isclose(el, e)]) for e in rings])
        adj = ring_med[1:] / ring_med[:-1]                 # ratio of each ring to the one below
        below_45 = rings[1:] <= 30.0 + 1e-6                # adjacent pairs from -30 up to 30 deg
        ref_rows.append(dict(subjectId=sid,
                             ratio_m45_over_m30=float(ring_med[0] / ring_med[1]),
                             max_other_adjacent_ratio=float(np.max(np.maximum(adj, 1 / adj)[1:][below_45[1:]]))))
    ref_df = pd.DataFrame(ref_rows)

    rows = []
    for row in df.itertuples():
        g, el = refs[row.subjectId]
        rec = F.read_tensor_file(tensor_path(root, row.subjectId, row.method, row.retainedDirections))
        gh = F.tensor_from_gram(rec["gram"], ORDER, SIGMA_MON)
        assert np.allclose(rec["azel"][:, 1], el), "reference and reconstruction grids differ"
        d = F.airm(g, gh)
        eye = np.eye(2) * F.ETA
        signed = np.log(np.linalg.det(gh + eye) / np.linalg.det(g + eye))
        out = dict(subjectId=row.subjectId, method=row.method, N=row.retainedDirections,
                   reported_meanAIRM=row.meanAIRM)
        for name, m in masks(el).items():
            out[f"airm_{name}"] = float(d[m].mean())
            out[f"signedlogdet_{name}"] = float(signed[m].mean())
        rows.append(out)
    rows = pd.DataFrame(rows)
    check = np.max(np.abs(rows.airm_all - rows.reported_meanAIRM))

    cells = rows.groupby(["N", "method"], as_index=False).mean(numeric_only=True).drop(columns="subjectId")
    out_dir = root / "analysis"
    out_dir.mkdir(exist_ok=True)
    rows.to_csv(out_dir / "boundary_sensitivity_rows.csv", index=False)
    cells.to_csv(out_dir / "boundary_sensitivity_cells.csv", index=False)
    ref_df.to_csv(out_dir / "boundary_sensitivity_reference.csv", index=False)

    print(f"Recomputed vs reported mean AIRM, max abs difference: {check:.2e}")
    print("\n1. Reference Fisher information, -45 ring / -30 ring (median sqrt det g):")
    print(f"   median over subjects {ref_df.ratio_m45_over_m30.median():.2f} "
          f"(IQR {ref_df.ratio_m45_over_m30.quantile(.25):.2f}-{ref_df.ratio_m45_over_m30.quantile(.75):.2f}); "
          f"largest other adjacent-ring ratio, -30 to 30 deg: median {ref_df.max_other_adjacent_ratio.median():.2f}")
    print("\n2. Cohort-mean AIRM by retention level (all / excl -45 / excl -45,-30 / -45 ring only):")
    for n, c in cells.groupby("N", sort=False):
        print(f"   N={n}")
        for r in c.sort_values("airm_all").itertuples():
            print(f"     {r.method:22s} {r.airm_all:6.3f} {r.airm_excl_m45:6.3f} "
                  f"{r.airm_excl_m45_m30:6.3f} {r.airm_only_m45:6.3f}")
        for v in ("all", "excl_m45", "excl_m45_m30"):
            print(f"     ranking ({v}): " + " < ".join(c.sort_values(f'airm_{v}').method))
    print("\n   Signed log-det (all / excl -45):")
    for r in cells.itertuples():
        print(f"     N={r.N:3d} {r.method:22s} {r.signedlogdet_all:+.3f} {r.signedlogdet_excl_m45:+.3f}")


if __name__ == "__main__":
    main()
