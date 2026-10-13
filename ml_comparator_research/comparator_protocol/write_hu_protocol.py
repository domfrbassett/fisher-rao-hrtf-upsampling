"""Write the shared SONICOM comparator protocol JSON."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from shared_hu_protocol import write_protocol_json


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sofa-root",
        type=Path,
        default=Path("dependencies/Sonicom_HRTFs"),
        help="Root containing SONICOM SOFA files.",
    )
    parser.add_argument(
        "--sofa-pattern",
        default="P*_FreeFieldCompMinPhase_48kHz.sofa",
        help="SOFA file pattern. Use P*_FreeFieldComp_48kHz.sofa if min-phase files are not present.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("ml_comparator_research/comparator_protocol/outputs/hu_hrtfformer_protocol.json"),
    )
    parser.add_argument(
        "--source-position-csv",
        type=Path,
        help="Optional CSV exported by export_protocol_source_positions.m with SourcePosition columns.",
    )
    args = parser.parse_args()

    source_positions = None
    if args.source_position_csv:
        source_positions = np.loadtxt(args.source_position_csv, delimiter=",")

    protocol = write_protocol_json(args.sofa_root, args.output, args.sofa_pattern, source_positions)
    print(f"Wrote protocol to {args.output}")
    print(f"Subjects: {len(protocol['subjectIds'])}")
    print(f"Train/test: {len(protocol['trainSubjectIds'])}/{len(protocol['testSubjectIds'])}")
    for retention, indices in protocol["sonicomDirectionIndices"].items():
        print(f"N={retention}: {len(indices)} directions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
