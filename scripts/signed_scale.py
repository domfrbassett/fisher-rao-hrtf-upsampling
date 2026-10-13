"""Signed scale change of the reconstructed Fisher tensors.

For every applicable row, the per-direction log-determinant ratio
log det(g_hat + eta I) / det(g + eta I) is averaged over directions, together with
the fraction of directions where the reconstruction carries more information than
the reference. Rows are then averaged per retention level and method.

Input:  results/evaluation/full_evaluation_summary.csv and metric_tensors/
Output: results/evaluation/analysis/signed_scale.csv
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

import fisher_lib as F

ROOT = Path(__file__).resolve().parents[1] / "results" / "evaluation"


def subject_folder(subject_id: int) -> Path:
    return ROOT / "metric_tensors" / f"subject_{subject_id:04d}"


def main() -> None:
    df = pd.read_csv(ROOT / "full_evaluation_summary.csv")
    df = df[df.status == "completed"]
    eye = np.eye(2) * F.ETA
    references = {}
    rows = []
    for r in df.itertuples():
        if r.subjectId not in references:
            ref = F.read_tensor_file(subject_folder(r.subjectId) / "reference_metric_tensor.mat")
            references[r.subjectId] = F.tensor_from_gram(ref["gram"])
        g = references[r.subjectId]
        rec = F.read_tensor_file(
            subject_folder(r.subjectId) / f"{r.method}_N{r.retainedDirections:03d}_metric_tensor.mat")
        gh = F.tensor_from_gram(rec["gram"])
        signed_log_det = np.log(np.linalg.det(gh + eye) / np.linalg.det(g + eye))
        rows.append(dict(method=r.method, N=r.retainedDirections,
                         signedLogDet=signed_log_det.mean(),
                         fracMoreInfo=(signed_log_det > 0).mean()))
    out = pd.DataFrame(rows).groupby(["N", "method"]).mean().round(3)
    out.to_csv(ROOT / "analysis" / "signed_scale.csv")
    print(out.to_string())


if __name__ == "__main__":
    main()
