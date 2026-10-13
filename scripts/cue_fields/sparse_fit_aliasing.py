"""Aliasing of fine-scale cue variation into sparse spherical-harmonic fits.

The reference cue fields are fitted by least squares at order L = min(6, floor(sqrt(N)) - 1) from the
N retained directions of each sparse mask, and compared with (i) the dense order-6 reference fit and
(ii) its spectral truncation to order L. The mean Fisher trace (mean squared spatial gradient of the
whitened cues over the sphere) of a field with SH coefficients c is sum_l l(l+1)|c_l|^2 / (4 pi).
Truncation can only lower it; fitting sparse samples of a field with unresolved fine structure can
raise it above the dense reference.

Output: results/evaluation/analysis/cue_fields/sparse_fit_energy.csv
"""
import json

import numpy as np
import pandas as pd

import cue_pipeline as cp

PROTOCOL = cp.REPO / "ml_comparator_research" / "comparator_protocol" / "outputs" / "hu_hrtfformer_protocol.json"
masks = {int(k): np.array(v) for k, v in json.load(open(PROTOCOL))["sonicomDirectionIndices"].items()}
d = np.load(cp.OUT / "reference_cues.npz")
r, fam = d["r"], d["fam"]
sig = cp.sigma_vec(fam)
Y6, deg6 = cp.real_sh(r, 6)


def mean_trace(coef, deg):
    return float(sum(l * (l + 1) * np.sum(coef[deg == l] ** 2) for l in range(deg.max() + 1)) / (4 * np.pi))


rows = []
for sid in cp.TEST_IDS:
    q = d[f"q_{sid}"] / sig
    cref = cp.fit_sh(r, q, 6, Y=Y6)
    e_ref = mean_trace(cref, deg6)
    for N, ix in masks.items():
        L = min(6, int(np.floor(np.sqrt(N))) - 1)
        YL, degL = cp.real_sh(r, L)
        c_sparse = np.linalg.lstsq(YL[ix], q[ix], rcond=None)[0]
        rows.append({"subjectId": sid, "N": N, "L": L, "rank": int(np.linalg.matrix_rank(YL[ix])),
                     "trace_reference_order6": e_ref,
                     "trace_truncated_reference": mean_trace(cref[:(L + 1) ** 2], degL),
                     "trace_sparse_fit": mean_trace(c_sparse, degL)})
df = pd.DataFrame(rows)
df.to_csv(cp.OUT / "sparse_fit_energy.csv", index=False)
df["ratio_sparse"] = df.trace_sparse_fit / df.trace_reference_order6
df["ratio_truncated"] = df.trace_truncated_reference / df.trace_reference_order6
print(df[df.N > 3].groupby("N").agg(L=("L", "first"), ratio_truncated=("ratio_truncated", "median"),
                                    ratio_sparse=("ratio_sparse", "median"),
                                    frac_above_reference=("ratio_sparse", lambda x: (x > 1).mean())).round(3))
