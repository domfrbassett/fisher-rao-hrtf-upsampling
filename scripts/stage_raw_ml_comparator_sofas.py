from __future__ import annotations

import argparse
import shutil
from pathlib import Path


RETENTIONS = (3, 5, 19, 100)


def subject_id_from_ranf_name(path: Path) -> int:
    # RANF exports names such as pred_p0010.sofa.
    stem = path.stem
    if not stem.startswith("pred_p"):
        raise ValueError(f"Unexpected RANF SOFA name: {path.name}")
    return int(stem.replace("pred_p", ""))


def copy_ranf_raw(project_root: Path, out_root: Path) -> None:
    work_root = project_root / "ml_comparator_research" / "comparator_protocol" / "work"
    for retention in RETENTIONS:
        source = (
            work_root
            / "ranf_sonicom"
            / "experiments"
            / f"ranf_hu_N{retention:03d}"
            / "log"
            / "eval_raw_no_node_replacement"
        )
        if not source.is_dir():
            raise FileNotFoundError(f"Missing raw RANF folder: {source}")

        sofas = sorted(source.glob("pred_p*.sofa"))
        if len(sofas) != 41:
            raise RuntimeError(f"Expected 41 raw RANF SOFAs in {source}, found {len(sofas)}")

        dest = out_root / "RANF" / f"N{retention:03d}"
        dest.mkdir(parents=True, exist_ok=True)
        for sofa in sofas:
            subject_id = subject_id_from_ranf_name(sofa)
            shutil.copy2(sofa, dest / f"Sonicom_{subject_id}.sofa")


def copy_fsp_ae_raw(project_root: Path, out_root: Path, fsp_root: Path | None) -> None:
    if fsp_root is None:
        candidates = [
            project_root / "FSP_AE_raw",
            project_root
            / "ml_comparator_research"
            / "comparator_protocol"
            / "work"
            / "ml_lap_aligned"
            / "FSP_AE_raw",
        ]
        fsp_root = next((candidate for candidate in candidates if candidate.is_dir()), candidates[0])

    for retention in RETENTIONS:
        source = fsp_root / f"N{retention:03d}"
        if not source.is_dir():
            raise FileNotFoundError(f"Missing raw FSP-AE folder: {source}")

        sofas = sorted(source.glob("Sonicom_*.sofa"))
        if len(sofas) != 41:
            raise RuntimeError(f"Expected 41 raw FSP-AE SOFAs in {source}, found {len(sofas)}")

        dest = out_root / "FSP_AE" / f"N{retention:03d}"
        dest.mkdir(parents=True, exist_ok=True)
        for sofa in sofas:
            shutil.copy2(sofa, dest / sofa.name)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stage non-node-replaced ML comparator SOFAs for MATLAB evaluation."
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path.cwd(),
        help="Repository/project root. Defaults to current directory.",
    )
    parser.add_argument(
        "--out-root",
        type=Path,
        default=None,
        help="Output aligned comparator root. Defaults to comparator work/ml_lap_aligned_raw_ml.",
    )
    parser.add_argument(
        "--fsp-root",
        type=Path,
        default=None,
        help="Root containing FSP_AE_raw/N003 etc. Defaults to common project locations.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove the output root before staging.",
    )
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    out_root = args.out_root
    if out_root is None:
        out_root = (
            project_root
            / "ml_comparator_research"
            / "comparator_protocol"
            / "work"
            / "ml_lap_aligned_raw_ml"
        )
    out_root = out_root.resolve()

    if args.clean and out_root.exists():
        shutil.rmtree(out_root)

    copy_ranf_raw(project_root, out_root)
    copy_fsp_ae_raw(project_root, out_root, args.fsp_root)

    print(f"Staged raw ML comparator SOFAs in {out_root}")
    for method in ("RANF", "FSP_AE"):
        for retention in RETENTIONS:
            count = len(list((out_root / method / f"N{retention:03d}").glob("Sonicom_*.sofa")))
            print(f"{method} N{retention:03d}: {count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
