# Fisher-Rao HRTF Upsampling Evaluation

This repository contains the manuscript source and reproducibility code for a Fisher-information-based evaluation of HRTF spatial upsampling methods.

The repository includes the paper source, compiled PDFs, figures and tables used in the manuscript, evaluation scripts, plotting scripts, compatibility shims, and wrapper code for the learning-based comparators. Large datasets, generated SOFA files, MATLAB tensor checkpoints, third-party toolbox distributions, trained model checkpoints, and cloned upstream repositories are not included.

## Contents

- `Fisher_Rao_HRTF_Evaluation_IEEE_ArXiv.tex` and `Fisher_Rao_HRTF_Evaluation_IEEE_ArXiv.pdf`: two-column manuscript.
- `run_hrtf_fisher_rao_evaluation.m`: MATLAB evaluation pipeline for signal metrics, Barumerli-style localisation metrics, and Fisher tensor discrepancy.
- `run_hrtf_fisher_rao_hu_protocol.m`: wrapper for the 41-subject sparse-mask protocol used for the machine-learning comparator evaluation.
- `scripts/`: Python scripts used to regenerate manuscript figures and tables from summary CSVs.
- `figures/evaluation/` and `tables/evaluation/`: paper figures and table fragments used by the TeX source.
- `ml_comparator_research/comparator_protocol/`: shared SONICOM protocol tools and the first-party RANF adapter. The upstream RANF repository is required separately.
- `ml_comparator_research/fsp_ae_sonicom/`: first-party FSP-AE SONICOM adaptation wrapper. The upstream FSP-AE source tree is required separately.
- `barumerli_compatibility/` and `sfs_compatibility/`: small compatibility shims used by the MATLAB evaluation scripts.

## External Data And Dependencies

The evaluation expects local copies of:

- SONICOM HRTF SOFA files.
- AMT / SOFA Toolbox for MATLAB.
- SUpDEq and its third-party MATLAB dependencies.
- A Python environment with `numpy`, `pandas`, and `matplotlib` for figure regeneration.
- The public RANF repository when reproducing RANF outputs.
- The public FSP-AE repository code path used by `ml_comparator_research/fsp_ae_sonicom`.

Configure local paths through the environment variables documented in the scripts, or mirror the directory layout used in the comments of `run_hrtf_fisher_rao_evaluation.m`.

## Rebuilding Paper Figures

From the repository root:

```powershell
python scripts/generate_paper_assets.py
python scripts/calculate_metric_correlations.py
python scripts/regenerate_local_threshold_plausibility_table.py
```

The included summary CSVs regenerate the manuscript figures and TeX table fragments. Full recomputation from SOFA files requires the external datasets and MATLAB toolboxes listed above.

## Data Availability

If you are a researcher seeking to reproduce or extend the work, please contact the author. Generated outputs such as reconstructed SOFA files can be shared where licensing and dataset terms permit. Third-party datasets, toolbox code, and external model repositories should be obtained from their original sources.
