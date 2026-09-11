# Fisher Information for HRTF Upsampling Evaluation

This repository accompanies the paper *On Using Fisher Information to Evaluate
the Preservation of Spatial Discriminability in HRTF Upsampling*. It contains
the IEEE manuscript, the evaluation code, the summary data used in the paper,
and the scripts that generate its figures and tables.

## Repository contents

- `Fisher_Rao_HRTF_Evaluation_IEEE_ArXiv.tex` and `.pdf`: manuscript source and compiled paper.
- `run_hrtf_fisher_rao_evaluation.m`: signal, Bayesian localisation, and Fisher-tensor evaluation.
- `run_hrtf_fisher_rao_hu_protocol.m`: 41-subject SONICOM protocol wrapper.
- `scripts/`: figure, table, correlation, and audit scripts.
- `results/`: manuscript summary data and compact audit outputs.
- `figures/evaluation/` and `tables/evaluation/`: manuscript figures and TeX table fragments.
- `ml_comparator_research/`: SONICOM adapters for RANF and FSP-AE. The upstream repositories are installed separately.
- `listening_test/`: source and protocol documentation for the lateral 2AFC study. Stimulus WAVs and participant responses are excluded from Git.

The large source datasets, reconstructed SOFA files, per-direction MATLAB
tensors, trained model checkpoints, third-party toolboxes, and cloned upstream
repositories are not included.

## Regenerate the manuscript figures

The committed summary CSV files are sufficient to rebuild the figures and TeX
tables used by the paper:

```powershell
python scripts/plot_median_crb_ellipses.py
python scripts/plot_barumerli_sonicom41_map_ellipses.py
python scripts/generate_paper_assets.py
python scripts/calculate_metric_correlations.py
python scripts/regenerate_local_threshold_plausibility_table.py
```

To compile the IEEE manuscript with MiKTeX:

```powershell
powershell -ExecutionPolicy Bypass -File .\BUILD_PAPER.ps1
```

## Full evaluation

Recomputing the results from HRIRs requires the 48-kHz SONICOM
`FreeFieldCompMinPhase` SOFA files, MATLAB, AMT with the SOFA Toolbox, SUpDEq,
and the external RANF and FSP-AE repositories. Local paths and optional
environment overrides are described in `EXTERNAL_DEPENDENCIES.md` and in the
entry-point scripts.

The final machine-learning comparison uses the complete model-generated RANF
and FSP-AE fields without replacing retained nodes with measured HRIRs. FSP-AE
LSD is evaluated up to its configured 16-kHz output limit; the other reported
LSD values use the common LAP/SAM band up to 20 kHz.

## Data access

Researchers seeking to reproduce or extend the work are welcome to contact the
authors. Generated outputs, including reconstructed SOFA files, can be shared
where the licences and dataset terms permit. Third-party datasets, toolboxes,
and model repositories should be obtained from their original sources.
