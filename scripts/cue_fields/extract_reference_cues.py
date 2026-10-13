"""Extract the whitened-cue inputs (PGE, ILD, transformed ITD) of the 41 test subjects' measured HRTFs.

Writes results/evaluation/analysis/cue_fields/reference_cues.npz (not tracked; derived from SONICOM data).
"""
import numpy as np

import cue_pipeline as cp

cp.OUT.mkdir(parents=True, exist_ok=True)
out = {}
for sid in cp.TEST_IDS:
    r, azel, q, fam = cp.extract_cues(sid)
    out[f"q_{sid}"] = q
    print(sid, end=" ", flush=True)
np.savez_compressed(cp.OUT / "reference_cues.npz", r=r, azel=azel, fam=fam, **out)
print("\nwrote", cp.OUT / "reference_cues.npz")
