# FSP-AE SONICOM comparator

This adapter trains the verified official FSP-AE implementation on the same
SONICOM protocol used by the other comparators:

- seeded 162/41 subject split from `hu_hrtfformer_protocol.json`;
- deterministic evaluation masks at 100, 19, 5, and 3 directions;
- `FreeFieldCompMinPhase_48kHz` input SOFAs by default;
- native FSP-AE joint magnitude and ITD prediction;
- retained-node replacement in magnitude/ITD space before HRIR synthesis;
- minimum-phase reconstruction with the model-predicted ITD;
- 48 kHz SOFA export on the original 793-direction SONICOM grid.

Nine deterministic subjects from the 162-subject training pool are reserved
for checkpoint selection. The 41 test subjects remain untouched. Training
uses random direction subsets of sizes 3, 5, 19, and 100, plus the full grid;
test inference uses the exact shared masks.

The official source tree at `_fsp_ae_inspect` is treated as an external
dependency and is not edited.

## PC commands

From the project root in an Anaconda PowerShell prompt, set the SONICOM path
once and reuse it:

```powershell
conda activate hrtf-ml
$SonicomRoot = "<path-to-SONICOM-FreeFieldCompMinPhase-root>"

python .\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py validate `
  --sonicom-root $SonicomRoot

python .\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py smoke `
  --sonicom-root $SonicomRoot `
  --device cuda

python .\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py train `
  --sonicom-root $SonicomRoot `
  --device cuda --epochs 1400

python .\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py test `
  --sonicom-root $SonicomRoot `
  --device cuda
```

Use `--resume` to continue an interrupted training run. Exported evaluation
SOFAs are written to:

```text
ml_comparator_research/comparator_protocol/work/ml_lap_aligned/
  FSP_AE/N003/Sonicom_<subject>.sofa
  FSP_AE/N005/Sonicom_<subject>.sofa
  FSP_AE/N019/Sonicom_<subject>.sofa
  FSP_AE/N100/Sonicom_<subject>.sofa
```

