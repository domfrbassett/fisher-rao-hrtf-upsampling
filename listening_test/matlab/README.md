# Adaptive 2IFC Stimulus Preparation

The browser study plays pre-rendered stereo WAV files. MATLAB prepares the
HRIR fields, Fisher tensors, adaptive track plan, and rendered stimulus bank
so that the web application itself remains simple and auditable.

## Export HRIR Fields And Build The Bank

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 `
  -SonicomRoot "<path-to-SONICOM-FreeFieldCompMinPhase-root>" -Subgrid
```

If `listening_test/fields` already contains the current exported
fields and tensors, rebuild only the plan/config/audio:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 -SkipExport
```

For the formal sub-grid bank, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 -SkipExport -Subgrid
```

This uses `SUpDEq_Bary_MCA_6dB` for continuous rendering. RANF and FSP-AE
stimulus rendering expect raw no-node-replacement fields named
`RANF_raw_N005_hrir_field.mat`, `RANF_raw_N019_hrir_field.mat`,
`FSP_AE_raw_N005_hrir_field.mat`, and `FSP_AE_raw_N019_hrir_field.mat` for
the representative subjects. The method labels and metric tensors remain the
standard evaluation outputs.

The runner sets:

- `FISHER_RAO_BEHAVIOURAL_EXPORT_ONLY=true`
- `FISHERRAO_COMPARATOR_PROTOCOL_JSON` to the LAP/Hu protocol JSON
- `FISHERRAO_METHODS=SUpDEq_MCA,RANF,FSP_AE`
- `FISHERRAO_USE_RANF_RAW_FOR_RENDERING=true`
- `FISHERRAO_USE_FSP_AE_RAW_FOR_RENDERING=true`

The exported acoustic fields are written under:

```text
listening_test/fields/
```

The adaptive web-study configuration and WAV files are written under:

```text
listening_test/public/config/
listening_test/public/audio/
```

## Current Listening-Test Structure

The adaptive task compares a fixed anchor against a displaced source using
two-interval forced choice. Each participant hears a balanced mixture of
representative virtual subjects from the median-subject bank, split into four
short sections: two lateral and two vertical. The same participant code can
resume later.

The current public entry point is:

```text
http://127.0.0.1:4173/?config=config/experiment.adaptive.json
```

## Analyse Responses

Response CSV files are saved by the local Node server under:

```text
listening_test/server/data/
```

Use the MATLAB/Python analysis scripts in `listening_test/matlab` and
`scripts/` for pilot summaries. Formal participant data should be exported and
versioned separately from the repository unless ethics approval explicitly
allows otherwise.
