"""Fit PGE spectral noise to the released SONICOM localisation cohort.

The script filters the released behavioural table to the measured-individual
baseline condition and runs the two-stage likelihood procedure from Barumerli
et al. (2026), replacing spectral amplitudes with the positive-gradient
representation from Barumerli et al. (2023).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import sys
import time

import numpy as np
import pandas as pd
import pyfar as pf

from bayesian_listener import __version__
from bayesian_listener.fitting import fit_listener


def parse_args() -> argparse.Namespace:
    """Parse command-line options."""
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--responses",
        type=Path,
        default=repo / "data" / "AXD_full_dataset_20260202.csv",
    )
    parser.add_argument(
        "--hrtf-dir", type=Path, default=repo / "data" / "sonicom_hrtf"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo / "results" / "pge_population_fits_shmax.csv",
    )
    parser.add_argument("--participants", nargs="*", default=None)
    parser.add_argument("--method", default="SHMAX")
    parser.add_argument("--mc", type=int, default=200)
    parser.add_argument("--motor-mc", type=int, default=200)
    parser.add_argument("--grid-points", type=int, default=1)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--no-resume", action="store_true", help="Refit successful existing rows."
    )
    return parser.parse_args()


def target_coordinates(rows: pd.DataFrame) -> pf.Coordinates:
    """Return the unique experimental target directions."""
    target_table = rows[["azi_target", "ele_target"]].copy()
    # One contributing experiment stores left-hemisphere azimuths as
    # 210..330 deg while the others use -150..-30 deg.  Canonicalise before
    # de-duplication; these are the same 33 physical target directions.
    target_table["azi_target"] = (
        (target_table["azi_target"] + 180.0) % 360.0
    ) - 180.0
    targets = (
        target_table
        .drop_duplicates()
        .sort_values(["azi_target", "ele_target"])
    )
    return pf.Coordinates.from_spherical_elevation(
        np.deg2rad(targets["azi_target"].to_numpy()),
        np.deg2rad(targets["ele_target"].to_numpy()),
        np.ones(len(targets)),
    )


def write_results(path: Path, rows: list[dict]) -> None:
    """Write accumulated results atomically enough for resumable batch use."""
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def main() -> int:
    """Run participant-wise PGE fits and save each completed fit."""
    args = parse_args()
    data = pd.read_csv(args.responses)
    measured = data.loc[data["condition"].eq("Measured")].copy()
    available = sorted(measured["participant"].unique())
    participants = args.participants or available
    unknown = sorted(set(participants) - set(available))
    if unknown:
        raise ValueError(f"Participants absent from measured condition: {unknown}")

    output_rows: list[dict] = []
    completed: set[str] = set()
    if args.output.exists() and not args.no_resume:
        previous = pd.read_csv(args.output)
        output_rows = previous.to_dict("records")
        if "success" in previous:
            success = previous["success"].astype(str).str.lower().eq("true")
            completed = set(previous.loc[success, "subject"].astype(str))

    coords = target_coordinates(measured)
    print(
        f"Measured baseline: {len(measured)} trials, {len(available)} participants, "
        f"{coords.cshape[0]} targets"
    )
    print(
        f"Convention: barumerli2023pge | interpolation: {args.method} | "
        f"MC: {args.mc}/{args.motor_mc}"
    )

    for participant in participants:
        if participant in completed:
            print(f"Skipping completed {participant}")
            continue
        sofa = args.hrtf_dir / f"{participant}_FreeFieldCompMinPhase_48kHz.sofa"
        if not sofa.exists():
            result = {
                "subject": participant,
                "method": args.method,
                "convention": "barumerli2023pge",
                "success": False,
                "error": f"Missing HRTF: {sofa}",
            }
        else:
            started = time.time()
            result = fit_listener(
                sofa_path=str(sofa),
                obs_tbl=measured,
                targets_coords=coords,
                interpolation_method=args.method,
                subject_id=participant,
                num_repetitions=args.mc,
                num_repetitions_motor=args.motor_mc,
                num_grid_points=args.grid_points,
                motor_estimation_seed=args.seed,
                verbose=True,
                convention="barumerli2023pge",
            )
            result["wall_time_batch"] = time.time() - started
        result["experiment"] = "+".join(sorted(measured.loc[
            measured["participant"].eq(participant), "experiment"
        ].unique()))
        result["mc_samples"] = args.mc
        result["motor_mc_samples"] = args.motor_mc
        result["seed"] = args.seed
        output_rows = [
            row for row in output_rows if str(row.get("subject")) != participant
        ]
        output_rows.append(result)
        write_results(args.output, output_rows)

    metadata = {
        "created_unix": time.time(),
        "python": sys.version,
        "platform": platform.platform(),
        "bayesian_listener_version": __version__,
        "responses": str(args.responses.resolve()),
        "hrtf_dir": str(args.hrtf_dir.resolve()),
        "condition": "Measured",
        "convention": "barumerli2023pge",
        "interpolation": args.method,
        "mc_samples": args.mc,
        "motor_mc_samples": args.motor_mc,
        "grid_points_per_parameter": args.grid_points,
        "pge_pipeline": "auditory amplitudes -> adjacent-band positive gradients -> spatial interpolation",
        "target_azimuth_canonicalization": "[-180, 180)",
        "participants_requested": participants,
    }
    args.output.with_suffix(".metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
