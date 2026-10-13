"""Model-free spatial roughness of the measured cue fields.

For each cue family, d'^2 between whitened cue vectors of measured directions separated by delta is
computed directly from the 793-direction grid (no spherical-harmonic fit): along elevation rings
-30..45 deg for azimuthal separations of 5-40 deg, and between rings for elevational separations of
10-30 deg. A differentiable field gives d'^2 proportional to delta^2; the exponent 2s of a power-law
fit (azimuth 5-20 deg, elevation 10-30 deg) measures departure from smoothness (s = 1: smooth).

Outputs (results/evaluation/analysis/cue_fields/):
  roughness_subject.csv   s per subject, cue family and axis
  roughness_summary.csv   median s with 95% bootstrap interval over subjects
"""
import numpy as np
import pandas as pd

import cue_pipeline as cp

d = np.load(cp.OUT / "reference_cues.npz")
azel, fam = d["azel"], d["fam"]
sig = cp.sigma_vec(fam)
RINGS = [-30, -20, -10, 0, 10, 20, 30, 45]
AZ_STEPS = [1, 2, 3, 4, 6, 8]                       # x 5 deg
EL_STEPS = {10: (-30, -20, -10, 0, 10, 20), 20: (-30, -20, -10, 0, 10), 30: (-30, -20, -10, 0)}
FIT = {"azimuth": [5, 10, 15, 20], "elevation": [10, 20, 30]}
FAMILIES = {"PGE": 0, "ILD": 1, "ITD": 2}


def ring(e):
    idx = np.where(np.isclose(azel[:, 1], e))[0]
    return idx[np.argsort(np.mod(azel[idx, 0], 360))]


def structure(Q):
    """Median d'^2/delta^2 (delta in radians) at each separation."""
    out = {"azimuth": {}, "elevation": {}}
    for k in AZ_STEPS:
        v = []
        for e in RINGS:
            A = Q[ring(e)]
            dl = np.radians(5 * k) * np.cos(np.radians(e))
            v.append(((np.roll(A, -k, 0) - A) ** 2).sum(1) / dl ** 2)
        out["azimuth"][5 * k] = float(np.median(np.concatenate(v)))
    for step, starts in EL_STEPS.items():
        v = [((Q[ring(a + step)] - Q[ring(a)]) ** 2).sum(1) / np.radians(step) ** 2 for a in starts]
        out["elevation"][step] = float(np.median(np.concatenate(v)))
    return out


rows = []
for sid in cp.TEST_IDS:
    q = d[f"q_{sid}"] / sig
    for name, f in FAMILIES.items():
        st = structure(q[:, fam == f])
        for axis, xs in FIT.items():
            slope = np.polyfit(np.log(xs), np.log([st[axis][x] for x in xs]), 1)[0]   # d'^2/delta^2 ~ delta^(2s-2)
            rows.append({"subjectId": sid, "cue": name, "axis": axis, "s": 1 + slope / 2,
                         **{f"dprime2_over_delta2_{x}deg": st[axis][x] for x in st[axis]}})
subj = pd.DataFrame(rows)
subj.to_csv(cp.OUT / "roughness_subject.csv", index=False)

rng = np.random.default_rng(0)
summ = []
for (cue, axis), g in subj.groupby(["cue", "axis"], sort=False):
    s = g["s"].to_numpy()
    boots = [np.median(rng.choice(s, len(s))) for _ in range(2000)]
    summ.append({"cue": cue, "axis": axis, "s_median": np.median(s),
                 "s_ci95_low": np.percentile(boots, 2.5), "s_ci95_high": np.percentile(boots, 97.5),
                 "dprime2_exponent_median": 2 * np.median(s)})
summ = pd.DataFrame(summ)
summ.to_csv(cp.OUT / "roughness_summary.csv", index=False)
print(summ.round(3).to_string(index=False))
