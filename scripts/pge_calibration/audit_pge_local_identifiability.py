"""Audit local PGE-noise/prior separability at participant fit solutions.

The likelihood is evaluated with common Monte Carlo random numbers at a
3-by-3 stencil in log(sigma_PGE), log(tau_prior).  The resulting finite-
difference Hessian is a local diagnostic, not a replacement for a full
parameter-recovery study.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
import pyfar as pf

from bayesian_listener import BayesianListener
from bayesian_listener.fitting import negloglik
from run_pge_population_fit import target_coordinates


def parse_args() -> argparse.Namespace:
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fits",
        type=Path,
        default=repo / "results" / "pge_population_fits_shmax_mc200.csv",
    )
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
        default=repo / "results" / "pge_local_identifiability_mc200.csv",
    )
    parser.add_argument("--participants", nargs="*", default=None)
    parser.add_argument("--mc", type=int, default=200)
    parser.add_argument("--log-step", type=float, default=0.10)
    parser.add_argument("--seed", type=int, default=8675309)
    parser.add_argument("--no-resume", action="store_true")
    return parser.parse_args()


def participant_likelihood_data(
    model: BayesianListener,
    measured: pd.DataFrame,
    participant: str,
    targets_coords: pf.Coordinates,
):
    rows = measured.loc[measured["participant"].eq(participant)]
    target_indices = model.coords.find_nearest(targets_coords)[0][0]
    targets = model.target[target_indices]
    responses = pf.Coordinates.from_spherical_elevation(
        np.deg2rad(rows["azi_response"].to_numpy()),
        np.deg2rad(rows["ele_response"].to_numpy()),
        np.ones(len(rows)),
    )
    response_targets = pf.Coordinates.from_spherical_elevation(
        np.deg2rad(rows["azi_target"].to_numpy()),
        np.deg2rad(rows["ele_target"].to_numpy()),
        np.ones(len(rows)),
    )
    response_target_indices = targets_coords.find_nearest(response_targets)[0][0]
    return targets, responses, response_target_indices


def evaluate_stencil(model, data, fit, step: float, mc: int, seed: int):
    targets, responses, response_target_indices = data
    x0 = np.log(float(fit["sigma_spectral"]))
    y0 = np.log(1.0 / float(fit["sigma_prior"]) ** 2)
    fixed = np.array([
        np.log(float(fit["sigma_ild"])),
        x0,
        np.log(float(fit["kappa_motor"])),
        y0,
    ])

    values = {}
    for ix in (-1, 0, 1):
        for iy in (-1, 0, 1):
            point = fixed.copy()
            point[1] = x0 + ix * step
            point[3] = y0 + iy * step
            # Common random numbers make differences reflect the parameters,
            # not independent Monte Carlo draws at adjacent stencil points.
            np.random.seed(seed)
            values[ix, iy] = negloglik(
                model,
                targets,
                responses,
                response_target_indices,
                point,
                num_repetitions=mc,
            )

    h = step
    f00 = values[0, 0]
    h_xx = (values[1, 0] - 2 * f00 + values[-1, 0]) / h**2
    h_yy = (values[0, 1] - 2 * f00 + values[0, -1]) / h**2
    h_xy = (
        values[1, 1]
        - values[1, -1]
        - values[-1, 1]
        + values[-1, -1]
    ) / (4 * h**2)
    grad_x = (values[1, 0] - values[-1, 0]) / (2 * h)
    grad_y = (values[0, 1] - values[0, -1]) / (2 * h)
    hessian = np.array([[h_xx, h_xy], [h_xy, h_yy]])
    eigvals = np.linalg.eigvalsh(hessian)
    positive_definite = bool(np.all(eigvals > 0))
    condition = float(eigvals[-1] / eigvals[0]) if positive_definite else np.inf
    correlation = np.nan
    if positive_definite:
        covariance = np.linalg.inv(hessian)
        correlation = covariance[0, 1] / np.sqrt(
            covariance[0, 0] * covariance[1, 1]
        )
    return {
        "nll_common_random_at_fit": f00,
        "gradient_log_sigma": grad_x,
        "gradient_log_tau_prior": grad_y,
        "hessian_log_sigma_log_sigma": h_xx,
        "hessian_log_sigma_log_tau": h_xy,
        "hessian_log_tau_log_tau": h_yy,
        "hessian_min_eigenvalue": float(eigvals[0]),
        "hessian_max_eigenvalue": float(eigvals[-1]),
        "hessian_positive_definite": positive_definite,
        "hessian_condition_number": condition,
        "local_covariance_correlation": float(correlation),
    }


def main() -> int:
    args = parse_args()
    fits = pd.read_csv(args.fits)
    fits = fits.loc[fits["success"].astype(str).str.lower().eq("true")]
    if args.participants:
        fits = fits.loc[fits["subject"].isin(args.participants)]
    responses = pd.read_csv(args.responses)
    measured = responses.loc[responses["condition"].eq("Measured")].copy()
    coords = target_coordinates(measured)

    output_rows: list[dict] = []
    completed: set[str] = set()
    if args.output.exists() and not args.no_resume:
        previous = pd.read_csv(args.output)
        output_rows = previous.to_dict("records")
        completed = set(previous["subject"].astype(str))

    for _, fit in fits.sort_values("subject").iterrows():
        participant = str(fit["subject"])
        if participant in completed:
            print(f"Skipping completed {participant}")
            continue
        print(f"Auditing {participant}")
        sofa = args.hrtf_dir / f"{participant}_FreeFieldCompMinPhase_48kHz.sofa"
        model = BayesianListener(str(sofa))
        model.compute_target(convention="barumerli2023pge")
        model.compute_template(interpolation=str(fit["method"]))
        data = participant_likelihood_data(model, measured, participant, coords)
        audit = evaluate_stencil(
            model, data, fit, args.log_step, args.mc, args.seed
        )
        audit.update({
            "subject": participant,
            "sigma_spectral": fit["sigma_spectral"],
            "sigma_prior": fit["sigma_prior"],
            "sigma_motor": fit["sigma_motor"],
            "mc_samples": args.mc,
            "common_random_seed": args.seed,
            "log_step": args.log_step,
        })
        output_rows = [
            row for row in output_rows if str(row.get("subject")) != participant
        ]
        output_rows.append(audit)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(output_rows).sort_values("subject").to_csv(
            args.output, index=False
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
