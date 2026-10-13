"""Aggregate and audit the participant-wise PGE likelihood fits."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


def parse_args() -> argparse.Namespace:
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input-glob",
        default="pge_featurefirst_mc200_part*.csv",
        help="Glob relative to the results directory.",
    )
    parser.add_argument("--results-dir", type=Path, default=repo / "results")
    parser.add_argument(
        "--output",
        type=Path,
        default=repo / "results" / "pge_population_fits_shmax_mc200.csv",
    )
    parser.add_argument("--bootstrap", type=int, default=20_000)
    parser.add_argument("--seed", type=int, default=20260927)
    return parser.parse_args()


def bootstrap_ci(values: np.ndarray, statistic, repeats: int, rng) -> list[float]:
    samples = rng.choice(values, size=(repeats, len(values)), replace=True)
    estimates = statistic(samples, axis=1)
    return np.quantile(estimates, [0.025, 0.975]).tolist()


def describe(values: pd.Series, repeats: int, rng) -> dict:
    finite = values[np.isfinite(values)].to_numpy(dtype=float)
    leave_one_out_medians = np.array(
        [np.median(np.delete(finite, i)) for i in range(len(finite))]
    )
    return {
        "n": int(len(finite)),
        "mean": float(np.mean(finite)),
        "sd": float(np.std(finite, ddof=1)),
        "median": float(np.median(finite)),
        "iqr": np.quantile(finite, [0.25, 0.75]).tolist(),
        "range": [float(np.min(finite)), float(np.max(finite))],
        "bootstrap_95_ci_mean": bootstrap_ci(
            finite, np.mean, repeats, rng
        ),
        "bootstrap_95_ci_median": bootstrap_ci(
            finite, np.median, repeats, rng
        ),
        "leave_one_out_median_range": [
            float(np.min(leave_one_out_medians)),
            float(np.max(leave_one_out_medians)),
        ],
    }


def main() -> int:
    args = parse_args()
    files = sorted(args.results_dir.glob(args.input_glob))
    if not files:
        raise FileNotFoundError(
            f"No files matching {args.results_dir / args.input_glob}"
        )
    frames = [pd.read_csv(path).assign(source_file=path.name) for path in files]
    combined = pd.concat(frames, ignore_index=True)
    combined = combined.sort_values("subject").drop_duplicates("subject", keep="last")
    combined["success"] = combined["success"].astype(str).str.lower().eq("true")
    combined["spectral_near_bound"] = (
        (combined["sigma_spectral"] <= 0.11)
        | (combined["sigma_spectral"] >= 49.9)
    )
    combined["prior_near_bound"] = (
        (combined["sigma_prior"] <= 0.11)
        | (combined["sigma_prior"] >= 175.0)
    )
    combined["motor_near_bound"] = (
        (combined["sigma_motor"] <= 2.2)
        | (combined["sigma_motor"] >= 79.0)
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    combined.to_csv(args.output, index=False)

    good = combined.loc[combined["success"]].copy()
    rng = np.random.default_rng(args.seed)
    summary = {
        "input_files": [str(path.resolve()) for path in files],
        "participants_total": int(len(combined)),
        "participants_successful": int(len(good)),
        "participants_failed": combined.loc[
            ~combined["success"], "subject"
        ].astype(str).tolist(),
        "near_parameter_bounds": good.loc[
            good[[
                "spectral_near_bound", "prior_near_bound", "motor_near_bound"
            ]].any(axis=1),
            "subject",
        ].astype(str).tolist(),
        "sigma_spectral_db": describe(
            good["sigma_spectral"], args.bootstrap, rng
        ),
        "sigma_motor_deg": describe(good["sigma_motor"], args.bootstrap, rng),
        "sigma_prior_deg": describe(good["sigma_prior"], args.bootstrap, rng),
        "fit_runtime_seconds": describe(
            good["wall_time_batch"], args.bootstrap, rng
        ),
        "by_experiment_membership": {},
    }
    for experiment, rows in good.groupby("experiment", dropna=False):
        summary["by_experiment_membership"][str(experiment)] = {
            "n": int(len(rows)),
            "sigma_spectral_median_db": float(rows["sigma_spectral"].median()),
            "sigma_spectral_mean_db": float(rows["sigma_spectral"].mean()),
            "sigma_motor_median_deg": float(rows["sigma_motor"].median()),
            "sigma_prior_median_deg": float(rows["sigma_prior"].median()),
        }

    summary_path = args.output.with_suffix(".summary.json")
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
