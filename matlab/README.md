# MATLAB evaluation engine

`run_evaluation.m` (repository root) is the entry point. It builds the configuration with
`fisher_rao_config.m` and passes it to `run_fisher_rao_evaluation.m`, which loads the toolboxes and
then evaluates one subject x retention x method row at a time, checkpointing after each row.

```
fisher_rao_config.m          every setting of the reported evaluation, plus the run options
run_fisher_rao_evaluation.m  toolbox set-up, first subject, methods, sparse masks, run loop
private/                     the engine's functions (visible only to the two files above)
compatibility/               two shims for current MATLAB (see compatibility/README.md)
postprocessing/              merge_worker_runs.m (parallel workers -> results/evaluation),
                             compute_barumerli_response_covariance.m (ellipse figure input)
```

The helpers are in `private/` so that they always take precedence over identically named functions
in the third-party toolboxes on the path, and the toolboxes never pick them up. Each file holds one
function and, below it, the local functions used only by that function.

## Order of a run

| Stage | File in `private/` | Local functions |
|---|---|---|
| Toolbox paths and checks | `configure_toolbox_paths`, `verify_configured_dependencies`, `activate_barumerli_compatibility` | |
| Load and preprocess a subject | `load_dense_hrtf_dataset`, `read_sofa_hrtf_field`, `preprocess_hrtf_dataset`, `refresh_field_spectra` | `read_sofa_hrtf_field`: delay, position and duplicate handling |
| Methods and sparse masks | `initialise_upsampling_methods`, `create_sampling_conditions`, `subset_spatial_field` | |
| Run loop, resume, checkpoint | `run_streaming_evaluation` | subject loading, row keys, checkpoint, progress log |
| Reconstruction | `reconstruct_hrtf_field` (SUpDEq), `load_external_comparator_reconstruction` (RANF, FSP-AE), `guard_finite_reconstruction`, `unavailable_reconstruction` | SUpDEq input/output conversion, hull test; SOFA lookup and grid matching |
| Signal metrics | `evaluate_signal_metrics` | LSD, ILD error |
| Common cue band | `apply_cue_band_limit`, `cue_band_fhigh`, `convert_field_to_dtf_sofa` | |
| Fisher tensors | `evaluate_fisher_tensor_airm`, `real_sh_basis_cartesian`, `assert_barumerli_target_coordinates`, `unavailable_fisher_result`, `write_metric_tensor_files` | cue extraction, SH fit, tangent basis, AIRM comparison |
| Bayesian observer | `create_barumerli_template`, `evaluate_barumerli_model`, `not_run_perceptual_result`, `saved_self_reference_result`, `attach_self_reference_metrics`, `apply_self_reference_to_existing_rows`, `replace_perceptual_summary_row` | |
| Summary table | `build_airm_summary_table`, `ensure_results_folder` | |

## Outputs (in `results/<name>/`)

- `full_evaluation_summary.csv`: one row per subject x method x retention level.
- `metric_tensors/subject_####/`: `reference_metric_tensor.mat` and one
  `<METHOD>_N###_metric_tensor.mat` per row, with the tensors, per-cue-family Gram matrices at SH
  orders 4, 6 and 8 and the reference-reconstruction cross terms (read by `scripts/fisher_lib.py`).
- `full_evaluation_checkpoint.mat`, `full_evaluation_progress.log`, `evaluation_subject_ids.csv`.
