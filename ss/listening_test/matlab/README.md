# MATLAB stimulus preparation

MATLAB prepares the HRTF fields, condition plan, rendered WAV bank, and bank
audit. The browser plays only pre-rendered audio.

## Build from existing fields

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 -SkipExport
```

The sub-grid build uses `SUpDEq_Bary_MCA_6dB`. RANF and FSP-AE are read from
raw, non-node-replaced fields:

```text
RANF_raw_N005_hrir_field.mat
RANF_raw_N019_hrir_field.mat
FSP_AE_raw_N005_hrir_field.mat
FSP_AE_raw_N019_hrir_field.mat
```

Generated files are written under:

```text
ss/listening_test/matlab/adaptive_condition_plan.csv
ss/listening_test/audit/
ss/listening_test/public/config/
ss/listening_test/public/audio/adaptive/
```

## Export fields and rebuild

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 `
  -SonicomRoot "<SONICOM-FreeFieldCompMinPhase-root>"
```

The wrapper selects SUpDEq-MCA, RANF, and FSP-AE, uses the shared SONICOM
protocol, and requests raw ML fields for listening-test rendering.

## Current bank

The formal bank contains 28 lateral adaptive tracks for P0033: seven field
conditions at four anchor instances. Each track has 12 pre-rendered angular
levels from 30 to 0.6 degrees. The browser runs 40-trial Bayesian adaptive
tracks targeting 76% correct.

## Analysis

`analyse_2ifc_responses.m` accepts a CSV exported by either server. It excludes
incomplete tracks and prior manifest versions, then writes condition summaries,
posterior threshold estimates and 95% credible intervals, plots, and the
optional mixed-effects analysis.
