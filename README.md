# Fisher Information for HRTF Upsampling Evaluation

This repository accompanies the paper *On Using Fisher Information to Evaluate
the Preservation of Spatial Discriminability in HRTF Upsampling*. It contains
the IEEE manuscript, the evaluation code, the summary data used in the paper,
and the scripts that generate its figures and tables.

## Repository contents

- `Fisher_Rao_HRTF_Evaluation_IEEE_ArXiv.tex` and `.pdf`: manuscript source and compiled paper.
- `run_hrtf_fisher_rao_evaluation.m`: signal, Bayesian localisation, and Fisher-tensor evaluation.
- `run_hrtf_fisher_rao_hu_protocol.m`: 41-subject SONICOM protocol wrapper.
- `scripts/`: figure, table, correlation, and analysis scripts.
- `results/`: manuscript summary data and derived results.
- `figures/evaluation/` and `tables/evaluation/`: manuscript figures and TeX table fragments.
- `ml_comparator_research/`: SONICOM adapters for RANF and FSP-AE. The upstream repositories are installed separately.
- `ss/`: supplementary software, including the archived lateral 2AFC study implementation. No listening-test results are reported in the manuscript.

## Regenerate the manuscript figures

Install the Python dependencies from the repository root:

```powershell
python -m pip install -r requirements.txt
```

The included summary CSV files and median tensor data support the following
figure and table builds:

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

Questions about the evaluation protocol can be directed to the authors.
Third-party datasets, toolboxes, and model repositories should be obtained from
their original sources.
