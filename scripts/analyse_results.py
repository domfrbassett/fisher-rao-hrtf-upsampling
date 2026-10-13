"""Analyses of the evaluation results (16 kHz cue band).

Inputs
  results/evaluation/full_evaluation_summary.csv   (merged worker output)
  results/evaluation/metric_tensors/subject_XXXX/*.mat

Outputs (results/evaluation/analysis/)
  cell_summary.csv                 cohort summaries per method x N
  correlations.csv                 cross-condition, row-wise (bootstrap) and
                                   within-condition rank agreement
  within_condition_pairs.csv       paired method comparisons per N
  sensitivity_rankings.csv         method rankings under sigma_mon / SH order
  thresholds_subject.csv           per-subject d'=1 thresholds
  thresholds_summary.csv           cohort-median thresholds
  thresholds_by_order.csv          cohort-median reference thresholds at SH orders 4, 6, 8
  median_reference_tensors.npz     elementwise and log-Euclidean medians
"""
from __future__ import annotations

import argparse
import itertools
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import kendalltau, pearsonr, spearmanr

import fisher_lib as F

METHODS = ["SUpDEq_SH", "SUpDEq_MCA", "SUpDEq_NN_MCA_6dB", "SUpDEq_Bary_MCA_6dB", "RANF", "FSP_AE"]
RETENTIONS = [100, 19, 5, 3]
METRICS = {
    "LSD": "LSDdB_16k",
    "ILD": "ILDErrorDb_16k",
    "Relative lateral RMS": "relativeLateralRMSErrorDeg",
    "Relative local polar RMS": "relativeLocalPolarRMSErrorDeg",
    "Relative quadrant error": "relativeQuadrantErrorPercentagePoints",
}
THRESHOLD_SPECS = {
    "H_az0_el0": (0, 0, 0.0),
    "H_az45_el0": (45, 0, 0.0),
    "H_az90_el0": (90, 0, 0.0),
    "V_az0_el0": (0, 0, 90.0),
    "V_az0_el45": (0, 45, 90.0),
    "D60_az0_el0": (0, 0, 60.0),
}
RNG = np.random.default_rng(0)


def load_summary(root: Path) -> pd.DataFrame:
    df = pd.read_csv(root / "full_evaluation_summary.csv")
    df["applicable"] = df["status"].eq("completed")
    return df


def tensor_path(root: Path, sid: int, method: str, n: int) -> Path:
    return root / "metric_tensors" / f"subject_{sid:04d}" / f"{method}_N{n:03d}_metric_tensor.mat"


def load_grams(root: Path, df: pd.DataFrame):
    refs, recons = {}, {}
    for sid in sorted(df.subjectId.unique()):
        refs[sid] = F.read_tensor_file(root / "metric_tensors" / f"subject_{sid:04d}" / "reference_metric_tensor.mat")
    for row in df[df.applicable].itertuples():
        recons[(row.subjectId, row.method, row.retainedDirections)] = F.read_tensor_file(
            tensor_path(root, row.subjectId, row.method, row.retainedDirections))
    return refs, recons


def mean_airm_variant(refs, recons, df, order=6, sigma_mon=1.25):
    out = {}
    for key, rec in recons.items():
        g = F.tensor_from_gram(refs[key[0]]["gram"], order, sigma_mon)
        gh = F.tensor_from_gram(rec["gram"], order, sigma_mon)
        out[key] = float(F.airm(g, gh).mean())
    return out


def cell_summary(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (m, n), g in df.groupby(["method", "retainedDirections"]):
        a = g[g.applicable]
        rows.append({
            "method": m, "N": n, "nApplicable": len(a), "nSubjects": len(g),
            "meanAIRM": a.meanAIRM.mean(), "medianOfMeanAIRM": a.meanAIRM.median(),
            "q1": a.meanAIRM.quantile(.25), "q3": a.meanAIRM.quantile(.75),
            "medianDirectionAIRM": a.medianAIRM.mean(),
            "nearFloorProportion": a.nearFloorProportion.mean(),
            "determinant": a.meanDeterminantError.mean(), "anisotropy": a.meanAnisotropyError.mean(),
            "orientationDeg": a.meanOrientationErrorDeg.mean(),
            **{k: a[c].mean() for k, c in METRICS.items()},
            "LSD_20k": a.LSDdB.mean(),
            "message": "" if len(a) else g.message.iloc[0],
        })
    return pd.DataFrame(rows)


def bootstrap_subjects(df, fn, n_boot=1000):
    subjects = df.subjectId.unique()
    vals = []
    for _ in range(n_boot):
        draw = RNG.choice(subjects, size=len(subjects), replace=True)
        boot = pd.concat([df[df.subjectId == s] for s in draw], ignore_index=True)
        vals.append(fn(boot))
    return np.nanpercentile(vals, [2.5, 97.5])


def within_condition_tau(df, col):
    """Mean over subjects and N of Kendall tau between AIRM and metric across methods."""
    taus = []
    for (sid, n), g in df.groupby(["subjectId", "retainedDirections"]):
        g = g.dropna(subset=["meanAIRM", col])
        if len(g) >= 3:
            taus.append(kendalltau(g.meanAIRM, g[col]).statistic)
    return float(np.nanmean(taus))


def correlations(df: pd.DataFrame, cells: pd.DataFrame) -> pd.DataFrame:
    a = df[df.applicable]
    out = []
    for name, col in METRICS.items():
        rows = a.dropna(subset=[col])
        c = cells.dropna(subset=[name, "meanAIRM"])
        if len(c) < 3 or len(rows) < 3:
            continue
        rec = {
            "metric": name,
            "cellPearson": pearsonr(c.meanAIRM, c[name]).statistic,
            "cellSpearman": spearmanr(c.meanAIRM, c[name]).statistic,
            "nCells": len(c),
            "rowSpearman": spearmanr(rows.meanAIRM, rows[col]).statistic,
            "nRows": len(rows),
            "withinTauMean": within_condition_tau(rows, col),
        }
        lo, hi = bootstrap_subjects(rows, lambda b: spearmanr(b.meanAIRM, b[col]).statistic)
        rec["rowSpearmanCI"] = f"[{lo:.2f}, {hi:.2f}]"
        lo, hi = bootstrap_subjects(rows, lambda b: within_condition_tau(b, col), n_boot=300)
        rec["withinTauCI"] = f"[{lo:.2f}, {hi:.2f}]"
        for n in RETENTIONS:
            cn = c[c.N == n]
            rec[f"cellSpearman_N{n}"] = spearmanr(cn.meanAIRM, cn[name]).statistic if len(cn) >= 3 else np.nan
        out.append(rec)
    return pd.DataFrame(out)


def paired_comparisons(df: pd.DataFrame) -> pd.DataFrame:
    """For each N and pair of methods, how often AIRM and each metric disagree on which is better."""
    a = df[df.applicable]
    rows = []
    for n in RETENTIONS:
        an = a[a.retainedDirections == n]
        methods = sorted(an.method.unique())
        for m1, m2 in itertools.combinations(methods, 2):
            x = an[an.method == m1].set_index("subjectId")
            y = an[an.method == m2].set_index("subjectId")
            common = x.index.intersection(y.index)
            x, y = x.loc[common], y.loc[common]
            d_airm = y.meanAIRM - x.meanAIRM
            rec = {"N": n, "methodA": m1, "methodB": m2, "nSubjects": len(common),
                   "meanAIRM_A": x.meanAIRM.mean(), "meanAIRM_B": y.meanAIRM.mean(),
                   "propAIRM_Bworse": float((d_airm > 0).mean()),
                   "det_A": x.meanDeterminantError.mean(), "det_B": y.meanDeterminantError.mean(),
                   "anis_A": x.meanAnisotropyError.mean(), "anis_B": y.meanAnisotropyError.mean(),
                   "orient_A": x.meanOrientationErrorDeg.mean(), "orient_B": y.meanOrientationErrorDeg.mean()}
            for name, col in METRICS.items():
                d = y[col] - x[col]
                ok = d.notna() & d_airm.notna()
                rec[f"{name}_A"] = x[col].mean()
                rec[f"{name}_B"] = y[col].mean()
                rec[f"{name}_propBworse"] = float((d[ok] > 0).mean()) if ok.any() else np.nan
                rec[f"{name}_disagree"] = float(((d[ok] > 0) != (d_airm[ok] > 0)).mean()) if ok.any() else np.nan
            rows.append(rec)
    return pd.DataFrame(rows)


def ranking(series_by_cell: dict, df: pd.DataFrame, label: str) -> list[dict]:
    a = df[df.applicable].copy()
    a["v"] = [series_by_cell[(r.subjectId, r.method, r.retainedDirections)] for r in a.itertuples()]
    out = []
    for n, g in a.groupby("retainedDirections"):
        means = g.groupby("method").v.mean().sort_values()
        out.append({"variant": label, "N": n, "ranking": " < ".join(means.index),
                    **{f"mean_{m}": means.get(m, np.nan) for m in METHODS}})
    return out


def thresholds(refs, recons, df, sigma_mon=1.25, order=6):
    rows = []
    any_ref = next(iter(refs.values()))
    azel = any_ref["azel"]
    idx = {}
    for key, (az, el, ang) in THRESHOLD_SPECS.items():
        d = np.abs(((azel[:, 0] - az + 180) % 360) - 180) + np.abs(azel[:, 1] - el)
        idx[key] = int(np.argmin(d))
        assert d[idx[key]] < 1e-6, key
    units = {k: np.array([np.cos(np.radians(v[2])), np.sin(np.radians(v[2]))]) for k, v in THRESHOLD_SPECS.items()}

    def compute(gram):
        g = F.tensor_from_gram(gram, order, sigma_mon)
        return {k: float(F.threshold_deg(g[idx[k]], units[k])) for k in THRESHOLD_SPECS}

    for sid, ref in refs.items():
        rows.append({"subjectId": sid, "method": "Measured", "N": 0, **compute(ref["gram"])})
    for (sid, m, n), rec in recons.items():
        rows.append({"subjectId": sid, "method": m, "N": n, **compute(rec["gram"])})
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    args = ap.parse_args()
    root = args.root
    out = root / "analysis"
    out.mkdir(exist_ok=True)

    df = load_summary(root)
    refs, recons = load_grams(root, df)

    # Consistency check: offline recomputation reproduces the MATLAB AIRM.
    primary = mean_airm_variant(refs, recons, df)
    a = df[df.applicable]
    diff = max(abs(primary[(r.subjectId, r.method, r.retainedDirections)] - r.meanAIRM) for r in a.itertuples())
    print(f"max |offline - MATLAB| mean AIRM = {diff:.2e}")
    assert diff < 1e-8

    cells = cell_summary(df)
    cells.to_csv(out / "cell_summary.csv", index=False)
    correlations(df, cells).to_csv(out / "correlations.csv", index=False)
    paired_comparisons(df).to_csv(out / "within_condition_pairs.csv", index=False)

    ranks = ranking(primary, df, "primary (SH 6, sigma_mon 1.25 dB)")
    for order in (4, 8):
        ranks += ranking(mean_airm_variant(refs, recons, df, order=order), df, f"SH order {order}")
    ranks += ranking(mean_airm_variant(refs, recons, df, sigma_mon=2.85), df, "sigma_mon 2.85 dB")
    pd.DataFrame(ranks).to_csv(out / "sensitivity_rankings.csv", index=False)

    th = thresholds(refs, recons, df)
    th.to_csv(out / "thresholds_subject.csv", index=False)
    th285 = thresholds(refs, {}, df, sigma_mon=2.85)
    summ = th.groupby(["method", "N"]).median(numeric_only=True).drop(columns="subjectId").reset_index()
    ref285 = th285.drop(columns=["subjectId"]).groupby(["method", "N"]).median().reset_index()
    ref285["method"] = "Measured (sigma_mon 2.85 dB)"
    pd.concat([summ, ref285]).to_csv(out / "thresholds_summary.csv", index=False)
    by_order = []
    for sm in (1.25, 2.85):
        for order in (4, 6, 8):
            t = thresholds(refs, {}, df, sigma_mon=sm, order=order).drop(columns=["subjectId", "method", "N"]).median()
            by_order.append({"sigma_mon": sm, "sh_order": order, **t.to_dict()})
    pd.DataFrame(by_order).to_csv(out / "thresholds_by_order.csv", index=False)

    g_ref = np.stack([F.tensor_from_gram(r["gram"]) for r in refs.values()])
    np.savez(out / "median_reference_tensors.npz",
             elementwise_median_fisher=np.median(g_ref, axis=0),
             log_euclidean_mean_fisher=F.log_euclidean_mean(g_ref + F.ETA * np.eye(2)),
             coordinates_azimuth_elevation_deg=next(iter(refs.values()))["azel"],
             coordinates_cartesian=next(iter(refs.values()))["cart"],
             subjects=np.array(sorted(refs)))
    print("done")


if __name__ == "__main__":
    main()
