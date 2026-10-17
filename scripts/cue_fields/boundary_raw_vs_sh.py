"""Is the large reference Fisher information on the lowest measured ring (-45 deg) real cue
structure or an artefact of the order-6 SH fit at the edge of the measured region?

For the 41 test subjects' measured cue fields (whitened with sigma_mon = 1.25 dB, sigma_ILD = 1 dB,
sigma_ITD = 0.569), compares
  - the azimuthal and elevational components of the SH order-6 Fisher tensor, evaluated on the
    measured rings and below the lowest one (-50 to -60 deg, where there are no measurements),
  - finite differences of the measured cues without any fit: along each ring at 5 and 20 deg
    azimuth steps, and between consecutive rings at the same azimuth,
  - the same between-ring differences of the SH-fitted cues.
Each value is d'^2 per rad^2: the median over the 72 azimuths, then the median over subjects.

Run from this folder after extract_reference_cues.py:
    python boundary_raw_vs_sh.py
Output: results/evaluation/analysis/cue_fields/boundary_raw_vs_sh.csv
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import cue_pipeline as cp

L = 6
EVAL_EL = [-60, -55, -50, -45, -40, -37.5, -35, -30, -25, -20, -15, -10, 0, 10, 20, 30]
AZ = np.arange(0, 360, 5.0)


def unit(az_deg: np.ndarray, el_deg: np.ndarray) -> np.ndarray:
    a, e = np.radians(az_deg), np.radians(el_deg)
    return np.stack([np.cos(e) * np.cos(a), np.cos(e) * np.sin(a), np.sin(e)], -1)


def main() -> None:
    d = np.load(cp.OUT / "reference_cues.npz")
    r, azel, fam = d["r"], d["azel"], d["fam"]
    sids = sorted(int(k[2:]) for k in d.files if k.startswith("q_"))
    el = np.round(azel[:, 1], 6)
    az = np.round(azel[:, 0] % 360, 6)
    rings = np.unique(el)[:-1]                       # the single 90 deg point is not a ring
    whiten = 1.0 / cp.sigma_vec(fam)
    families = {"all": np.ones(len(fam), bool), "spectral": fam == 0, "interaural": fam > 0}
    grid = unit(np.tile(AZ, len(EVAL_EL)), np.repeat(EVAL_EL, len(AZ)))
    Y = cp.real_sh(r, L)[0]

    def ring(e):
        idx = np.where(el == e)[0]
        return idx[np.argsort(az[idx])]

    rows = []
    for sid in sids:
        q = d[f"q_{sid}"] * whiten
        coef = cp.fit_sh(r, q, L, Y=Y)
        J = cp.tangent_jacobian(coef, grid, L)        # u1 = increasing azimuth, u2 = elevation
        for fname, fm in families.items():
            g_az = (J[:, fm, 0] ** 2).sum(1).reshape(len(EVAL_EL), -1)
            g_el = (J[:, fm, 1] ** 2).sum(1).reshape(len(EVAL_EL), -1)
            for i, e in enumerate(EVAL_EL):
                rows += [dict(subjectId=sid, family=fname, quantity="sh6_tensor_azimuth", el=e, value=np.median(g_az[i])),
                         dict(subjectId=sid, family=fname, quantity="sh6_tensor_elevation", el=e, value=np.median(g_el[i]))]
            for e in rings:
                idx = ring(e)
                for k in (1, 4):
                    dq = q[np.roll(idx, -k)][:, fm] - q[idx][:, fm]
                    delta = 2 * np.arcsin(np.cos(np.radians(e)) * np.sin(np.radians(5 * k) / 2))
                    rows.append(dict(subjectId=sid, family=fname, quantity=f"measured_azimuth_{5 * k}deg",
                                     el=e, value=np.median((dq ** 2).sum(1)) / delta ** 2))
            for e0, e1 in zip(rings[:-1], rings[1:]):
                i0, i1 = ring(e0), ring(e1)
                delta = np.radians(e1 - e0)
                dq = q[i1][:, fm] - q[i0][:, fm]
                dfit = (Y[i1] - Y[i0]) @ coef[:, fm]
                rows += [dict(subjectId=sid, family=fname, quantity="measured_between_rings",
                              el=(e0 + e1) / 2, value=np.median((dq ** 2).sum(1)) / delta ** 2),
                         dict(subjectId=sid, family=fname, quantity="sh6_fit_between_rings",
                              el=(e0 + e1) / 2, value=np.median((dfit ** 2).sum(1)) / delta ** 2)]

    med = (pd.DataFrame(rows).groupby(["family", "quantity", "el"], as_index=False)["value"].median())
    med.to_csv(cp.OUT / "boundary_raw_vs_sh.csv", index=False)

    a = med[med.family == "all"].pivot(index="el", columns="quantity", values="value")
    print("All cues, cohort medians (d'^2 per rad^2):")
    print(a.round(1).to_string())
    print("\nRatio of the -45 deg ring to the -30 deg ring:")
    print(f"  SH tensor, elevation component  {a.loc[-45, 'sh6_tensor_elevation'] / a.loc[-30, 'sh6_tensor_elevation']:.2f}")
    print(f"  SH tensor, azimuth component    {a.loc[-45, 'sh6_tensor_azimuth'] / a.loc[-30, 'sh6_tensor_azimuth']:.2f}")
    print(f"  measured, azimuth 20 deg steps  {a.loc[-45, 'measured_azimuth_20deg'] / a.loc[-30, 'measured_azimuth_20deg']:.2f}")
    print(f"  measured between rings, (-45,-30) / (-30,-20)  "
          f"{a.loc[-37.5, 'measured_between_rings'] / a.loc[-25, 'measured_between_rings']:.2f}")


if __name__ == "__main__":
    main()
