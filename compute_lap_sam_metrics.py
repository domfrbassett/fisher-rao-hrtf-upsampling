from __future__ import annotations

import argparse
import csv
import contextlib
import io
import sys
import warnings
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
VENDOR = PROJECT_ROOT / "_vendor_python"
if VENDOR.is_dir():
    sys.path.insert(0, str(VENDOR))

import numpy as np
from spatialaudiometrics import lap_challenge as lap

warnings.filterwarnings(
    "ignore",
    message="divide by zero encountered in log10",
    category=RuntimeWarning,
)


RETENTIONS = (100, 19, 5, 3)
METHODS = ("RANF", "FSP_AE")
TEST_SUBJECTS = (10, 22, 26, 30, 32, 33, 37, 40, 48, 59, 68, 71, 73, 78, 80, 82,
                 83, 88, 89, 100, 104, 116, 118, 128, 141, 143, 148, 149, 152,
                 166, 168, 169, 172, 173, 175, 179, 191, 193, 196, 198, 200)


def run_one(aligned_root: Path, method: str, retention: int, subject_id: int) -> dict[str, object]:
    target = aligned_root / "target" / f"N{retention:03d}" / f"Sonicom_{subject_id}.sofa"
    pred = aligned_root / method / f"N{retention:03d}" / f"Sonicom_{subject_id}.sofa"
    row: dict[str, object] = {
        "method": method,
        "retention": retention,
        "subjectId": subject_id,
        "targetPath": str(target),
        "predPath": str(pred),
    }
    if not target.is_file() or not pred.is_file():
        row.update(status="missing", message="missing aligned target or prediction")
        return row

    try:
        with contextlib.redirect_stdout(io.StringIO()):
            metrics, threshold_bool, _ = lap.calculate_task_two_metrics(str(target), str(pred))
    except SystemExit as exc:
        row.update(status="error", message=str(exc))
        return row
    except Exception as exc:  # Keep the batch going; the CSV is the audit trail.
        row.update(status="error", message=repr(exc))
        return row

    row.update(
        status="completed",
        message="",
        lapITDErrorUs=float(metrics[0]),
        lapILDErrorDb=float(metrics[1]),
        lapLSDdB=float(metrics[2]),
        belowITDThreshold=bool(threshold_bool[0]),
        belowILDThreshold=bool(threshold_bool[1]),
        belowLSDThreshold=bool(threshold_bool[2]),
    )
    return row


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--aligned-root", type=Path, default=PROJECT_ROOT / "ml_comparator_research" / "comparator_protocol" / "work" / "ml_lap_aligned")
    parser.add_argument("--out", type=Path, default=PROJECT_ROOT / "results" / "ml_lap_sam_metrics.csv")
    parser.add_argument("--methods", nargs="*", default=list(METHODS))
    parser.add_argument("--subjects", nargs="*", type=int, default=list(TEST_SUBJECTS))
    args = parser.parse_args()

    rows = []
    for method in args.methods:
        for retention in RETENTIONS:
            for subject_id in args.subjects:
                print(f"SAM {method} N={retention} subject={subject_id}")
                rows.append(run_one(args.aligned_root, method, retention, subject_id))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted(set().union(*(row.keys() for row in rows)))
    with args.out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nWrote {args.out}")
    completed = [row for row in rows if row.get("status") == "completed"]
    for method in args.methods:
        for retention in RETENTIONS:
            subset = [
                row for row in completed
                if row["method"] == method and int(row["retention"]) == retention
            ]
            if not subset:
                continue
            print(
                f"{method} N={retention}: "
                f"ITD={np.mean([row['lapITDErrorUs'] for row in subset]):.3f} us, "
                f"ILD={np.mean([row['lapILDErrorDb'] for row in subset]):.3f} dB, "
                f"LSD={np.mean([row['lapLSDdB'] for row in subset]):.3f} dB "
                f"(n={len(subset)})"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
