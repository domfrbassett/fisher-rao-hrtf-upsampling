"""Python re-implementation of the MATLAB Fisher cue pipeline (matlab/private/evaluate_fisher_tensor_airm.m).

Mirrors: 16 kHz FIR band limit (fir1 order 256, Kaiser beta 8, cutoff 15.5 kHz),
SOFAhrtf2dtf('log'), AMT barumerli2023_featureextraction ('pge', fhigh 16 kHz):
complex all-pole gammatone bank at 1-ERB spacing, sqrt(HWR) -> RMS -> dB,
Baumgartner positive gradients; broadband ILD; MaxIACCe ITD with the
Reijniers JND transform. Validated against the MATLAB Fisher tensors (maximum pointwise AIRM 4e-7).

SONICOM files are read from dependencies/Sonicom_HRTFs, or from FISHERRAO_DATASET_ROOT if set,
as for the MATLAB evaluation.
"""
from __future__ import annotations

import math
import os
from functools import lru_cache
from pathlib import Path

import h5py
import numpy as np
from scipy import signal
from scipy.special import sph_harm_y

FS = 48000.0
REPO = Path(__file__).resolve().parents[2]
SOFA_ROOT = Path(os.environ.get("FISHERRAO_DATASET_ROOT") or REPO / "dependencies" / "Sonicom_HRTFs")
OUT = REPO / "results" / "evaluation" / "analysis" / "cue_fields"
SIGMA_MON, SIGMA_ILD, SIGMA_ITD = 1.25, 1.0, 0.569
TEST_IDS = [10, 22, 26, 30, 32, 33, 37, 40, 48, 59, 68, 71, 73, 78, 80, 82, 83, 88, 89, 100, 104,
            116, 118, 128, 141, 143, 148, 149, 152, 166, 168, 169, 172, 173, 175, 179, 191, 193,
            196, 198, 200]


def load_sofa(sid: int):
    name = f"P{sid:04d}_FreeFieldCompMinPhase_48kHz.sofa"
    p = SOFA_ROOT / f"P{sid:04d}" / "HRTF" / "HRTF" / "48kHz" / name
    if not p.exists():
        p = next(SOFA_ROOT.rglob(name))
    with h5py.File(p, "r") as f:
        ir = np.asarray(f["Data.IR"][()], float)[:, :2, :]
        sp = np.asarray(f["SourcePosition"][()], float)
    az, el = np.radians(sp[:, 0]), np.radians(sp[:, 1])
    r = np.stack([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)], 1)
    return ir, r, sp[:, :2]


def band_limit(ir: np.ndarray, order: int = 256, cutoff: float = 15500.0, beta: float = 8.0):
    b = signal.firwin(order + 1, cutoff / (FS / 2), window=("kaiser", beta))
    padded = np.concatenate([ir, np.zeros(ir.shape[:-1] + (order,))], axis=-1)
    return signal.lfilter(b, 1.0, padded, axis=-1)


def hrtf2dtf_log(ir: np.ndarray, f1: float = 50.0, f2: float = 18000.0, atten: float = 20.0):
    n = ir.shape[-1]
    f = np.arange(n) * FS / n
    idx = (f >= f1) & (f <= f2)
    idx[n // 2 + 1:] = idx[1:n // 2][::-1]
    H = np.fft.fft(ir, axis=-1)                         # (dir, ear, n)
    logmag = np.log(np.abs(H) + np.finfo(float).eps)
    avg = logmag.mean(axis=0, keepdims=True)            # per ear
    cep = np.fft.ifft(avg, axis=-1)
    cep[..., n // 2 + 1:] = 0
    cep[..., 1:n // 2] *= 2
    ctf = np.exp(avg) * np.exp(1j * np.angle(np.exp(np.fft.fft(cep, axis=-1))))
    D = H.copy()
    D[..., idx] = H[..., idx] / ctf[..., idx]
    return np.real(np.fft.ifft(D, axis=-1)) / 10 ** (atten / 20)


def freqtoerb(f):
    return 9.2645 * np.sign(f) * np.log(1 + np.abs(f) * 0.00437)


def erbtofreq(e):
    return (1 / 0.00437) * np.sign(e) * (np.exp(np.abs(e) / 9.2645) - 1)


def audfiltbw(fc):
    return 24.7 + fc / 9.265


@lru_cache(maxsize=4)
def erb_centres(flow: float = 700.0, fhigh: float = 16000.0, bw: float = 1.0):
    lo, hi = freqtoerb(np.array([flow, fhigh]))
    n = int(math.floor((hi - lo) / bw))
    rem = (hi - lo) - n * bw
    pts = lo + np.arange(n + 1) * bw + rem / 2
    return erbtofreq(pts)


def gammatone_bank(x: np.ndarray, fc: np.ndarray, n: int = 4):
    """2*real(complex all-pole gammatone) outputs, x: (..., time) -> (..., band, time)."""
    betamul = math.factorial(n - 1) ** 2 / (math.pi * math.factorial(2 * n - 2) * 2 ** (-(2 * n - 2)))
    beta = betamul * audfiltbw(fc)
    out = np.empty(x.shape[:-1] + (len(fc), x.shape[-1]))
    for i, (f0, bt) in enumerate(zip(fc, beta)):
        atilde = np.exp(-2 * np.pi * bt / FS - 1j * 2 * np.pi * f0 / FS)
        a = np.poly(np.full(n, atilde))
        b = (1 - np.exp(-2 * np.pi * bt / FS)) ** n
        out[..., i, :] = 2 * np.real(signal.lfilter([b], a, x.astype(complex), axis=-1))
    return out


def maxiacce_itd(dtf: np.ndarray):
    bb, aa = signal.butter(10, 3000 / (FS / 2))
    lp = signal.lfilter(bb, aa, dtf, axis=-1)
    env = np.abs(signal.hilbert(lp, axis=-1))
    ns = env.shape[-1]
    itd = np.empty(env.shape[0])
    for d in range(env.shape[0]):
        cc = np.correlate(env[d, 0], env[d, 1], "full")
        itd[d] = (np.argmax(np.abs(cc)) - (ns - 1)) / FS
    return itd


def transform_itd(tau):
    a, b = 32.5e-6, 0.095
    return np.sign(tau) * (np.log(a + b * np.abs(tau)) - np.log(a)) / b


def extract_cues(sid: int):
    """Return r (793,3), az/el, q (793,M) and family index arrays."""
    ir, r, azel = load_sofa(sid)
    dtf = hrtf2dtf_log(band_limit(ir))
    front = np.argmin(np.abs(azel[:, 0]) + np.abs(azel[:, 1]))
    dtf = dtf / (np.max(np.abs(dtf[front])) + np.finfo(float).eps)
    itd = transform_itd(maxiacce_itd(dtf))
    rms = np.sqrt(np.mean(dtf ** 2, axis=-1))
    ild = 20 * np.log10(rms[:, 0]) - 20 * np.log10(rms[:, 1])
    fc = erb_centres()
    padded = np.concatenate([dtf, np.zeros(dtf.shape[:-1] + (int(0.05 * FS) - dtf.shape[-1],))], -1)
    y = gammatone_bank(padded, fc)                       # (dir, ear, band, time)
    lev = 20 * np.log10(np.sqrt(np.mean(np.maximum(y, 0), axis=-1)))   # rms(sqrt(hwr))
    erb = audfiltbw(fc)
    dg = int(round(np.mean(erb[1:] / np.diff(fc))))
    pge = np.maximum(lev[:, :, dg:] - lev[:, :, :-dg], 0)            # (dir, ear, band-dg)
    mon = pge.transpose(0, 2, 1).reshape(len(r), -1, order="F") if False else \
        np.concatenate([pge[:, 0, :], pge[:, 1, :]], axis=1)
    q = np.concatenate([mon, ild[:, None], itd[:, None]], axis=1)
    fam = np.array([0] * mon.shape[1] + [1, 2])
    return r, azel, q, fam


# ---------- spherical harmonics and tangent gradients ----------

def real_sh(r: np.ndarray, L: int):
    """Orthonormal real SH up to degree L at unit vectors r: (n, (L+1)^2), with degree labels."""
    theta = np.arccos(np.clip(r[:, 2], -1, 1))
    phi = np.arctan2(r[:, 1], r[:, 0])
    cols, deg = [], []
    for l in range(L + 1):
        for m in range(-l, l + 1):
            Y = sph_harm_y(l, abs(m), theta, phi)
            if m < 0:
                cols.append(np.sqrt(2) * (-1) ** m * Y.imag)
            elif m == 0:
                cols.append(Y.real)
            else:
                cols.append(np.sqrt(2) * (-1) ** m * Y.real)
            deg.append(l)
    return np.stack(cols, 1), np.array(deg)


def tangent_basis(r: np.ndarray):
    aux = np.where(np.abs(r[:, 2:3]) > 0.9, np.array([[0, 1, 0]]), np.array([[0, 0, 1]]))
    u1 = np.cross(aux, r)
    u1 /= np.linalg.norm(u1, axis=1, keepdims=True)
    u2 = np.cross(r, u1)
    return u1, u2


def tangent_jacobian(coef: np.ndarray, r: np.ndarray, L: int, h: float = 1e-4):
    """J (n, M, 2): derivatives of the SH field (coef: (L+1)^2 x M) along u1, u2 (radians)."""
    u1, u2 = tangent_basis(r)
    J = []
    for u in (u1, u2):
        rp = r + h * u
        rm = r - h * u
        rp /= np.linalg.norm(rp, axis=1, keepdims=True)
        rm /= np.linalg.norm(rm, axis=1, keepdims=True)
        fp = real_sh(rp, L)[0] @ coef
        fm = real_sh(rm, L)[0] @ coef
        J.append((fp - fm) / (2 * np.arctan(h)))
    return np.stack(J, -1)


def sigma_vec(fam: np.ndarray, sigma_mon: float = SIGMA_MON):
    return np.array([sigma_mon, SIGMA_ILD, SIGMA_ITD])[fam]


def fisher_tensor(J: np.ndarray, fam: np.ndarray, sigma_mon: float = SIGMA_MON):
    w = 1.0 / sigma_vec(fam, sigma_mon) ** 2
    return np.einsum("nmi,m,nmj->nij", J, w, J)


def family_grams(J: np.ndarray, fam: np.ndarray):
    return np.stack([np.einsum("nmi,nmj->nij", J[:, fam == k], J[:, fam == k]) for k in range(3)])


def fit_sh(r: np.ndarray, q: np.ndarray, L: int, ridge: float = 0.0, Y=None):
    Y = real_sh(r, L)[0] if Y is None else Y
    if ridge == 0:
        return np.linalg.lstsq(Y, q, rcond=None)[0]
    return np.linalg.solve(Y.T @ Y + ridge * np.eye(Y.shape[1]), Y.T @ q)
