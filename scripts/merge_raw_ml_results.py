from __future__ import annotations

import shutil
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
CLASSICAL_ROOT = ROOT / "results" / "barumerli_pge_fisher_hu_no_gep_final"
RAW_ROOT = (
    ROOT
    / "raw"
    / "barumerli_pge_fisher_hu_ml_comparators_raw_ml"
    / "barumerli_pge_fisher_hu_ml_comparators_raw_ml"
)
OUT_ROOT = ROOT / "results" / "barumerli_pge_fisher_hu_raw_ml_final"
ML_METHODS = {"RANF", "FSP_AE"}


def copy_tree_filtered(source: Path, destination: Path, *, exclude_ml: bool) -> None:
    for item in source.rglob("*"):
        if item.is_dir():
            continue
        rel = item.relative_to(source)
        rel_parts = set(rel.parts)
        if exclude_ml and rel_parts.intersection(ML_METHODS):
            continue
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)


def main() -> int:
    classical_csv = CLASSICAL_ROOT / "full_evaluation_summary.csv"
    raw_csv = RAW_ROOT / "full_evaluation_summary.csv"
    if not classical_csv.is_file():
        raise FileNotFoundError(classical_csv)
    if not raw_csv.is_file():
        raise FileNotFoundError(raw_csv)

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    OUT_ROOT.mkdir(parents=True)

    classical = pd.read_csv(classical_csv)
    raw = pd.read_csv(raw_csv)
    if set(raw["method"].unique()) != ML_METHODS:
        raise RuntimeError(f"Raw summary methods are not {sorted(ML_METHODS)}: {sorted(raw['method'].unique())}")

    merged = pd.concat(
        [classical[~classical["method"].isin(ML_METHODS)], raw],
        ignore_index=True,
    )

    expected_rows = 14 * 4 * 41
    if len(merged) != expected_rows:
        raise RuntimeError(f"Expected {expected_rows} merged rows, found {len(merged)}")

    counts = merged.groupby(["method", "retainedDirections"]).size()
    bad = counts[counts != 41]
    if not bad.empty:
        raise RuntimeError(f"Unexpected method-retention counts:\n{bad}")

    merged.to_csv(OUT_ROOT / "full_evaluation_summary.csv", index=False)
    shutil.copy2(CLASSICAL_ROOT / "evaluation_subject_ids.csv", OUT_ROOT / "evaluation_subject_ids.csv")

    copy_tree_filtered(CLASSICAL_ROOT / "metric_tensors", OUT_ROOT / "metric_tensors", exclude_ml=True)
    copy_tree_filtered(RAW_ROOT / "metric_tensors", OUT_ROOT / "metric_tensors", exclude_ml=False)

    tensor_count = sum(1 for _ in (OUT_ROOT / "metric_tensors").rglob("*") if _.is_file())
    print(f"Wrote {OUT_ROOT}")
    print(f"Merged rows: {len(merged)}")
    print(f"Metric tensor files: {tensor_count}")
    print(merged.groupby(["method", "retainedDirections"]).size().unstack(fill_value=0).to_string())
    print(merged["status"].value_counts(dropna=False).to_string())
    print(merged["perceptualStatus"].value_counts(dropna=False).to_string())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
