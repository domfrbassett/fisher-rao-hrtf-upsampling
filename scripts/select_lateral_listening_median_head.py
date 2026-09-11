from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
SUMMARY_CSV = ROOT / "results" / "barumerli_pge_fisher_hu_raw_ml_final" / "full_evaluation_summary.csv"
FSP_AE_LSD_CSV = ROOT / "results" / "barumerli_pge_fisher_hu_raw_ml_final" / "fsp_ae_lsd_20_16k.csv"
OUT_DIR = ROOT / "listening_test" / "audit"

METHODS = ["SUpDEq_MCA", "RANF", "FSP_AE"]
RETENTIONS = [5, 19]
METRICS = [
    "LSDdB",
    "ILDErrorDb",
    "relativeLateralRMSErrorDeg",
    "relativeLocalPolarRMSErrorDeg",
    "relativeQuadrantErrorPercentagePoints",
]


def load_summary() -> pd.DataFrame:
    df = pd.read_csv(SUMMARY_CSV)
    if FSP_AE_LSD_CSV.is_file():
        fsp_lsd = pd.read_csv(FSP_AE_LSD_CSV)
        fsp_lsd = fsp_lsd.rename(columns={"LSDdB_20_16k": "FSP_AE_LSDdB_20_16k"})
        df = df.merge(fsp_lsd, on=["subjectId", "retainedDirections"], how="left")
        idx = df["method"].eq("FSP_AE") & df["FSP_AE_LSDdB_20_16k"].notna()
        df.loc[idx, "LSDdB"] = df.loc[idx, "FSP_AE_LSDdB_20_16k"]
        df = df.drop(columns=["FSP_AE_LSDdB_20_16k"])
    return df


def robust_scale(values: pd.Series) -> tuple[float, float]:
    median = float(values.median())
    q1 = float(values.quantile(0.25))
    q3 = float(values.quantile(0.75))
    iqr = q3 - q1
    if not np.isfinite(iqr) or iqr <= 1.0e-12:
        std = float(values.std(ddof=0))
        iqr = std if std > 1.0e-12 else 1.0
    return median, iqr


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    df = load_summary()
    df = df[
        df["method"].isin(METHODS)
        & df["retainedDirections"].isin(RETENTIONS)
        & df["status"].eq("completed")
        & df["perceptualStatus"].eq("completed")
    ].copy()

    missing = [metric for metric in METRICS if metric not in df.columns]
    if missing:
        raise RuntimeError(f"Missing required metrics: {missing}")

    required_count = len(METHODS) * len(RETENTIONS)
    counts = df.groupby("subjectId").size()
    complete_subjects = counts[counts == required_count].index
    df = df[df["subjectId"].isin(complete_subjects)].copy()

    scale_rows = []
    wide_rows = {}
    normalised_rows = {}
    for (method, retention), subset in df.groupby(["method", "retainedDirections"], sort=True):
        for metric in METRICS:
            median, scale = robust_scale(subset[metric])
            column = f"{method}_N{int(retention):03d}_{metric}"
            scale_rows.append(
                {
                    "method": method,
                    "retainedDirections": int(retention),
                    "metric": metric,
                    "cohortMedian": median,
                    "normalisationScaleIQR": scale,
                }
            )
            for _, row in subset.iterrows():
                subject = int(row["subjectId"])
                wide_rows.setdefault(subject, {"subjectId": subject})[column] = float(row[metric])
                normalised_rows.setdefault(subject, {"subjectId": subject})[
                    f"{column}_absRobustDeviation"
                ] = abs(float(row[metric]) - median) / scale

    rank_rows = []
    for subject, row in sorted(normalised_rows.items()):
        deviations = [value for key, value in row.items() if key != "subjectId"]
        rank_rows.append(
            {
                "subjectId": subject,
                "nonFisherMeanAbsRobustDeviation": float(np.mean(deviations)),
                "nonFisherMedianAbsRobustDeviation": float(np.median(deviations)),
                "nonFisherMaxAbsRobustDeviation": float(np.max(deviations)),
                "metricConditionCount": len(deviations),
            }
        )
    rank_rows = sorted(rank_rows, key=lambda row: (row["nonFisherMeanAbsRobustDeviation"], row["subjectId"]))
    for rank, row in enumerate(rank_rows, start=1):
        row["rank"] = rank

    selected = rank_rows[0]
    summary = {
        "selectedSubjectId": selected["subjectId"],
        "selectionRule": "Minimum mean absolute robust deviation from cohort median across non-Fisher metric-condition columns.",
        "includedMethods": METHODS,
        "includedRetainedDirections": RETENTIONS,
        "includedMetrics": METRICS,
        "excludedMetrics": [
            "meanAIRM",
            "medianAIRM",
            "stdAIRM",
            "iqrAIRM",
            "meanDeterminantError",
            "meanAnisotropyError",
            "meanOrientationErrorDeg",
            "orientationValidCount",
            "orientationValidProportion",
            "predictedDPrimeReference",
            "predictedDPrimeField",
            "predictedDeltaDPrime",
            "localAIRM",
        ],
        "fspAeLsdConvention": "FSP_AE LSD uses the 20 Hz to 16 kHz supported-band correction where available.",
        "selectedRankRow": selected,
    }

    rank_path = OUT_DIR / "median_head_non_fisher_ranked_subjects.csv"
    raw_path = OUT_DIR / "median_head_non_fisher_raw_metric_matrix.csv"
    norm_path = OUT_DIR / "median_head_non_fisher_normalised_deviations.csv"
    scale_path = OUT_DIR / "median_head_non_fisher_scaling.csv"
    summary_path = OUT_DIR / "median_head_non_fisher_summary.json"

    with rank_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rank_rows[0].keys()))
        writer.writeheader()
        writer.writerows(rank_rows)

    pd.DataFrame.from_dict(wide_rows, orient="index").sort_index().to_csv(raw_path, index=False)
    pd.DataFrame.from_dict(normalised_rows, orient="index").sort_index().to_csv(norm_path, index=False)
    pd.DataFrame(scale_rows).to_csv(scale_path, index=False)
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))
    print(f"Wrote {rank_path}")
    print(f"Wrote {raw_path}")
    print(f"Wrote {norm_path}")
    print(f"Wrote {scale_path}")
    print(f"Wrote {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

