from __future__ import annotations

import argparse
import contextlib
import csv
import io
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
VENDOR = PROJECT_ROOT / "_vendor_python"
if VENDOR.is_dir():
    sys.path.insert(0, str(VENDOR))

import numpy as np
import sofar as sf


RETENTIONS = (100, 19, 5, 3)
TEST_SUBJECTS = (10, 22, 26, 30, 32, 33, 37, 40, 48, 59, 68, 71, 73, 78, 80, 82,
                 83, 88, 89, 100, 104, 116, 118, 128, 141, 143, 148, 149, 152,
                 166, 168, 169, 172, 173, 175, 179, 191, 193, 196, 198, 200)


def rounded_az_el(sofa) -> list[tuple[float, float]]:
    src = np.asarray(sofa.SourcePosition, dtype=float)
    return [(round(float(az), 2), round(float(el), 2)) for az, el in src[:, :2]]


def read_sofa_quiet(path: Path):
    with contextlib.redirect_stdout(io.StringIO()):
        return sf.read_sofa(str(path))


def subject_target_path(work: Path, retention: int, subject_id: int) -> Path:
    return (
        work / "ranf_sonicom" / "experiments" / f"ranf_hu_N{retention:03d}"
        / "log" / "eval" / f"target_p{subject_id:04d}.sofa"
    )


def ranf_path(work: Path, retention: int, subject_id: int) -> Path:
    return (
        work / "ranf_sonicom" / "experiments" / f"ranf_hu_N{retention:03d}"
        / "log" / "eval" / f"pred_p{subject_id:04d}.sofa"
    )


def write_sofa_like(source, out_path: Path, indices: list[int] | None = None) -> None:
    out = sf.Sofa("SimpleFreeFieldHRIR")
    if indices is None:
        out.Data_IR = np.asarray(source.Data_IR, dtype=float)
        out.SourcePosition = np.asarray(source.SourcePosition, dtype=float)
        delay = np.asarray(source.Data_Delay, dtype=float)
    else:
        out.Data_IR = np.asarray(source.Data_IR, dtype=float)[indices, :, :]
        out.SourcePosition = np.asarray(source.SourcePosition, dtype=float)[indices, :]
        delay = np.asarray(source.Data_Delay, dtype=float)
        if delay.ndim == 2 and delay.shape[0] == np.asarray(source.SourcePosition).shape[0]:
            delay = delay[indices, :]

    out.Data_SamplingRate = float(np.asarray(source.Data_SamplingRate).reshape(-1)[0])
    out.Data_Delay = delay
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sf.write_sofa(str(out_path), out)


def align_to_target(source_path: Path, target, target_keys: list[tuple[float, float]], out_path: Path) -> dict:
    source = read_sofa_quiet(source_path)
    source_keys = rounded_az_el(source)
    lookup: dict[tuple[float, float], int] = {}
    duplicates = 0
    for idx, key in enumerate(source_keys):
        if key in lookup:
            duplicates += 1
            continue
        lookup[key] = idx

    missing = [key for key in target_keys if key not in lookup]
    if missing:
        return {
            "status": "error",
            "message": f"missing {len(missing)} target directions; first missing {missing[:5]}",
            "sourceDirections": len(source_keys),
            "targetDirections": len(target_keys),
            "intersectionDirections": len(set(source_keys) & set(target_keys)),
            "sourceSamples": int(np.asarray(source.Data_IR).shape[2]),
            "targetSamples": int(np.asarray(target.Data_IR).shape[2]),
            "duplicates": duplicates,
        }

    source_samples = int(np.asarray(source.Data_IR).shape[2])
    target_samples = int(np.asarray(target.Data_IR).shape[2])
    if source_samples != target_samples:
        return {
            "status": "invalid_length",
            "message": f"source HRIR length {source_samples} does not match LAP target length {target_samples}",
            "sourceDirections": len(source_keys),
            "targetDirections": len(target_keys),
            "intersectionDirections": len(set(source_keys) & set(target_keys)),
            "sourceSamples": source_samples,
            "targetSamples": target_samples,
            "duplicates": duplicates,
        }

    indices = [lookup[key] for key in target_keys]
    write_sofa_like(source, out_path, indices)
    return {
        "status": "completed",
        "message": "",
        "sourceDirections": len(source_keys),
        "targetDirections": len(target_keys),
        "intersectionDirections": len(set(source_keys) & set(target_keys)),
        "sourceSamples": source_samples,
        "targetSamples": target_samples,
        "duplicates": duplicates,
    }


def copy_target(target_path: Path, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(target_path, out_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-root", type=Path, default=PROJECT_ROOT / "ml_comparator_research" / "comparator_protocol" / "work")
    parser.add_argument("--out-root", type=Path, default=PROJECT_ROOT / "ml_comparator_research" / "comparator_protocol" / "work" / "ml_lap_aligned")
    parser.add_argument("--subjects", nargs="*", type=int, default=list(TEST_SUBJECTS))
    args = parser.parse_args()

    rows = []
    for retention in RETENTIONS:
        for subject_id in args.subjects:
            target_path = subject_target_path(args.work_root, retention, subject_id)
            if not target_path.is_file():
                rows.append({
                    "method": "target",
                    "retention": retention,
                    "subjectId": subject_id,
                    "status": "missing",
                    "message": f"missing canonical target {target_path}",
                })
                continue

            target = read_sofa_quiet(target_path)
            target_keys = rounded_az_el(target)
            aligned_target = args.out_root / "target" / f"N{retention:03d}" / f"Sonicom_{subject_id}.sofa"
            copy_target(target_path, aligned_target)
            rows.append({
                "method": "target",
                "retention": retention,
                "subjectId": subject_id,
                "status": "completed",
                "message": "",
                "sourceDirections": len(target_keys),
                "targetDirections": len(target_keys),
                "intersectionDirections": len(target_keys),
                "sourceSamples": int(np.asarray(target.Data_IR).shape[2]),
                "targetSamples": int(np.asarray(target.Data_IR).shape[2]),
                "duplicates": 0,
                "sourcePath": str(target_path),
                "alignedPath": str(aligned_target),
            })

            sources = {
                "RANF": ranf_path(args.work_root, retention, subject_id),
            }
            for method, source_path in sources.items():
                if source_path is None or not Path(source_path).is_file():
                    rows.append({
                        "method": method,
                        "retention": retention,
                        "subjectId": subject_id,
                        "status": "missing",
                        "message": f"missing source SOFA {source_path}",
                    })
                    continue
                out_path = args.out_root / method / f"N{retention:03d}" / f"Sonicom_{subject_id}.sofa"
                row = align_to_target(Path(source_path), target, target_keys, out_path)
                row.update({
                    "method": method,
                    "retention": retention,
                    "subjectId": subject_id,
                    "sourcePath": str(source_path),
                    "alignedPath": str(out_path) if row["status"] == "completed" else "",
                })
                rows.append(row)

    report_path = args.out_root / "ml_lap_alignment_report.csv"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted(set().union(*(row.keys() for row in rows)))
    with report_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {report_path}")
    for method in ("RANF",):
        method_rows = [row for row in rows if row.get("method") == method]
        counts: dict[str, int] = {}
        for row in method_rows:
            counts[row.get("status", "")] = counts.get(row.get("status", ""), 0) + 1
        print(f"{method}: {counts}")
    print("FSP_AE writes directly to ml_lap_aligned/FSP_AE via RUN_FSP_AE_SONICOM_FULL.ps1.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
