"""Prepare SONICOM layouts expected by HRTFformer and RANF.

The source dataset may be flattened or nested. This script creates a comparator
work layout with:

- HRTFformer-compatible nested folders under `HRTF_Datasets/SONICOM`
- a `Sonicom` alias because the public HRTFformer code inconsistently uses
  `Sonicom` and `SONICOM`
- RANF-compatible flat SOFAs under `ranf_sonicom/sonicom/subjects`

Files are hard-linked where possible and copied otherwise.
"""

from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path

from shared_hu_protocol import discover_subject_ids


def link_or_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        return
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def find_sofa(source_root: Path, subject_id: int, source_suffix: str) -> Path:
    name = f"P{subject_id:04d}_{source_suffix}.sofa"
    matches = list(source_root.rglob(name))
    if not matches:
        raise FileNotFoundError(f"Could not find {name} below {source_root}")
    return matches[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("dependencies/Sonicom_HRTFs"))
    parser.add_argument(
        "--source-suffix",
        default="FreeFieldCompMinPhase_48kHz",
        help="Example: FreeFieldCompMinPhase_48kHz or FreeFieldComp_48kHz.",
    )
    parser.add_argument("--work-root", type=Path, default=Path("ml_comparator_research/comparator_protocol/work"))
    args = parser.parse_args()

    pattern = f"P*_{args.source_suffix}.sofa"
    subject_ids = discover_subject_ids(args.source_root, pattern)
    if not subject_ids:
        raise RuntimeError(f"No source SOFAs matching {pattern} below {args.source_root}")

    hrtfformer_root = args.work_root / "HRTF_Datasets" / "SONICOM"
    hrtfformer_alias = args.work_root / "HRTF_Datasets" / "Sonicom"
    ranf_root = args.work_root / "ranf_sonicom" / "sonicom" / "subjects"

    for subject_id in subject_ids:
        src = find_sofa(args.source_root, subject_id, args.source_suffix)
        nested_name = src.name
        nested_dst = (
            hrtfformer_root
            / f"P{subject_id:04d}"
            / "HRTF"
            / "HRTF"
            / "48kHz"
            / nested_name
        )
        alias_dst = (
            hrtfformer_alias
            / f"P{subject_id:04d}"
            / "HRTF"
            / "HRTF"
            / "48kHz"
            / nested_name
        )
        ranf_dst = ranf_root / nested_name
        link_or_copy(src, nested_dst)
        link_or_copy(src, alias_dst)
        link_or_copy(src, ranf_dst)

    print(f"Prepared {len(subject_ids)} subjects.")
    print(f"HRTFformer root parent: {args.work_root / 'HRTF_Datasets'}")
    print(f"RANF subjects root: {ranf_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
