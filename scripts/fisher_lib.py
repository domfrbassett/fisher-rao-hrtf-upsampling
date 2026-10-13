"""Fisher-tensor helpers for the analysis scripts.

Reads the MATLAB v7.3 tensor files written by the evaluation
(results/<run>/metric_tensors/subject_####/*.mat) and recomputes tensors, AIRM and
thresholds from the stored per-cue-family Gram matrices.
"""
from __future__ import annotations

from pathlib import Path

import h5py
import numpy as np

SIGMA = {"mon": 1.25, "ild": 1.0, "itd": 0.569}
ETA = 1e-6
ORDERS = (4, 6, 8)


def read_tensor_file(path: Path) -> dict:
    with h5py.File(path, "r") as f:
        out = {}
        if "familyGram" in f and f["familyGram"].ndim == 5:
            # MATLAB [2,2,nDir,3 families,3 orders] -> h5py (order, family, dir, 2, 2)
            out["gram"] = np.asarray(f["familyGram"][()])
        else:
            out["gram"] = None
        if "crossFamilyGram" in f and f["crossFamilyGram"].ndim == 5:
            # Unsymmetrised J_target' J_recon; h5py reverses MATLAB's axes, so swap
            # the last two to index (order, family, dir, target axis, recon axis).
            out["cross"] = np.swapaxes(np.asarray(f["crossFamilyGram"][()]), -1, -2)
        out["tensor"] = np.asarray(f["metricTensor"][()])  # (dir, 2, 2)
        if "airmByDirection" in f and f["airmByDirection"].ndim == 2:
            out["airm"] = np.asarray(f["airmByDirection"][()]).ravel()
        out["azel"] = np.asarray(f["coordinatesAzimuthElevationDeg"][()]).T
        out["cart"] = np.asarray(f["coordinatesCartesian"][()]).T
    return out


def tensor_from_gram(gram: np.ndarray, order: int = 6, sigma_mon: float = SIGMA["mon"],
                     sigma_ild: float = SIGMA["ild"], sigma_itd: float = SIGMA["itd"]) -> np.ndarray:
    io = ORDERS.index(order)
    g = (gram[io, 0] / sigma_mon**2 + gram[io, 1] / sigma_ild**2 + gram[io, 2] / sigma_itd**2)
    return 0.5 * (g + np.swapaxes(g, -1, -2))


def cross_from_gram(cross: np.ndarray, order: int = 6, sigma_mon: float = SIGMA["mon"],
                    sigma_ild: float = SIGMA["ild"], sigma_itd: float = SIGMA["itd"]) -> np.ndarray:
    """Noise-weighted cross tensor J_target' Sigma^-1 J_recon (not symmetrised)."""
    io = ORDERS.index(order)
    return cross[io, 0] / sigma_mon**2 + cross[io, 1] / sigma_ild**2 + cross[io, 2] / sigma_itd**2


def airm(g: np.ndarray, ghat: np.ndarray, eta: float = ETA) -> np.ndarray:
    """Pointwise AIRM between stacks of 2x2 SPD tensors (regularised)."""
    eye = np.eye(2)
    A = g + eta * eye
    B = ghat + eta * eye
    L = np.linalg.cholesky(A)
    Linv = np.linalg.inv(L)
    S = Linv @ B @ np.swapaxes(Linv, -1, -2)
    S = 0.5 * (S + np.swapaxes(S, -1, -2))
    lam = np.maximum(np.linalg.eigvalsh(S), 1e-12)
    return np.sqrt(np.sum(np.log(lam) ** 2, axis=-1))


def threshold_deg(g: np.ndarray, u: np.ndarray) -> np.ndarray:
    """d'=1 threshold in degrees along unit tangent direction(s) u (tangent basis coords)."""
    q = np.einsum("...i,...ij,...j->...", u, g, u)
    return np.degrees(1.0 / np.sqrt(q))


def log_euclidean_mean(tensors: np.ndarray, axis: int = 0) -> np.ndarray:
    w, v = np.linalg.eigh(tensors)
    logs = (v * np.log(w)[..., None, :]) @ np.swapaxes(v, -1, -2)
    m = logs.mean(axis=axis)
    w, v = np.linalg.eigh(m)
    return (v * np.exp(w)[..., None, :]) @ np.swapaxes(v, -1, -2)
