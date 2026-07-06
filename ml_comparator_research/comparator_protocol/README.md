# Comparator Protocol Wrappers

This folder contains first-party wrappers used to align learning-based comparators with the shared SONICOM evaluation protocol used in the manuscript.

Included files:

- `shared_hu_protocol.py`: shared sparse masks, seeded 162/41 SONICOM train/test split, and SONICOM source-position mapping utilities.
- `write_hu_protocol.py`: regenerates `outputs/hu_hrtfformer_protocol.json` from local SONICOM SOFA files.
- `prepare_sonicom_layout.py`: creates local work layouts expected by HRTFformer-style loaders and RANF.
- `run_ranf_hu_comparator.py`: runs RANF using the shared split, sparse masks, retrieval matrices, and output conventions.

The generated `outputs/` and `work/` folders are excluded from version control.

## RANF Upstream Code

Do not commit `ml_comparator_research/repos/RANF_HRTF/`. Clone the upstream MERL RANF repository separately and point `run_ranf_hu_comparator.py --repo-root` at that checkout.

The wrapper expects a lightly patched RANF checkout so that SONICOM masks, retrieval matrices, and evaluation output paths can be controlled externally. In the PC reproduction run, the upstream-side compatibility changes were confined to:

- `ranf/utils/util.py`
- `ranf/compute_spec_ild_itd_for_sonicom_datasets.py`
- `ranf/utils/sonicom_dataset_retrieval.py`

Those changes are not included here because they modify the external method implementation. If reproducing the exact run, apply the compatibility patch to a local RANF checkout, then keep that patched checkout outside this repository.

## Typical Order

```powershell
python ml_comparator_research/comparator_protocol/prepare_sonicom_layout.py --source-root <SONICOM_ROOT>
python ml_comparator_research/comparator_protocol/write_hu_protocol.py --sofa-root <SONICOM_ROOT>
python ml_comparator_research/comparator_protocol/run_ranf_hu_comparator.py all --retention 19 --repo-root <RANF_CHECKOUT>
```

Repeat the final command for `100`, `19`, `5`, and `3` retained directions as required.
