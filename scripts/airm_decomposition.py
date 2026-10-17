"""Exact scale/shape split of the AIRM discrepancy.

For 2x2 tensors with generalised eigenvalues lambda_1, lambda_2 of (g_hat, g),

    d_AIRM^2 = log^2 lambda_1 + log^2 lambda_2 = 0.5 * l^2 + d_shape^2,

with l = log lambda_1 + log lambda_2 = log det g_hat - log det g (signed scale error)
and d_shape = |log(lambda_1 / lambda_2)| / sqrt(2), the AIRM between the two tensors
after each is normalised to unit determinant (anisotropy and orientation together).

Cohort means of both terms per method and retention level support the scale/shape
statements in the results section.

Input:  results/evaluation/full_evaluation_summary.csv and metric_tensors/
Output: results/evaluation/analysis/airm_decomposition.csv
"""
from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pandas as pd

import fisher_lib as F
from plot_summary_figures import METHOD_ORDER

ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = Path(os.environ.get("FISHERRAO_RESULT_ROOT", ROOT / "results" / "evaluation"))


def subject_folder(subject_id: int) -> Path:
    return RESULT_ROOT / "metric_tensors" / f"subject_{subject_id:04d}"


def scale_shape(g: np.ndarray, ghat: np.ndarray, eta: float = F.ETA) -> tuple[np.ndarray, np.ndarray]:
    """Signed log-determinant ratio l and shape distance d_shape, per direction."""
    eye = np.eye(2)
    L = np.linalg.cholesky(g + eta * eye)
    Linv = np.linalg.inv(L)
    S = Linv @ (ghat + eta * eye) @ np.swapaxes(Linv, -1, -2)
    S = 0.5 * (S + np.swapaxes(S, -1, -2))
    log_lam = np.log(np.maximum(np.linalg.eigvalsh(S), 1e-12))
    return log_lam.sum(axis=-1), np.abs(log_lam[:, 1] - log_lam[:, 0]) / np.sqrt(2)


def collect() -> pd.DataFrame:
    df = pd.read_csv(RESULT_ROOT / "full_evaluation_summary.csv")
    df = df[(df.status == "completed") & df.method.isin(METHOD_ORDER)]
    references, rows = {}, []
    max_check = 0.0
    for r in df.itertuples():
        if r.subjectId not in references:
            ref = F.read_tensor_file(subject_folder(r.subjectId) / "reference_metric_tensor.mat")
            references[r.subjectId] = F.tensor_from_gram(ref["gram"])
        g = references[r.subjectId]
        rec = F.read_tensor_file(
            subject_folder(r.subjectId) / f"{r.method}_N{r.retainedDirections:03d}_metric_tensor.mat")
        gh = F.tensor_from_gram(rec["gram"])
        ell, d_shape = scale_shape(g, gh)
        max_check = max(max_check, np.max(np.abs(np.sqrt(0.5 * ell**2 + d_shape**2) - F.airm(g, gh))))
        rows.append(dict(method=r.method, N=r.retainedDirections,
                         meanSquaredAIRM=np.mean(0.5 * ell**2 + d_shape**2),
                         scaleTerm=np.mean(0.5 * ell**2), shapeTerm=np.mean(d_shape**2),
                         meanSignedLogDet=np.mean(ell), meanShape=np.mean(d_shape)))
    print(f"identity check: max |sqrt(l^2/2 + d_shape^2) - AIRM| = {max_check:.1e}")
    out = pd.DataFrame(rows).groupby(["N", "method"]).mean()
    out["scaleShare"] = out.scaleTerm / out.meanSquaredAIRM
    return out.round(3)


def main() -> None:
    table = collect()
    out_dir = RESULT_ROOT / "analysis"
    out_dir.mkdir(parents=True, exist_ok=True)
    table.to_csv(out_dir / "airm_decomposition.csv")
    print(table.to_string())


if __name__ == "__main__":
    main()
