# External Dependencies

The full evaluation requires datasets and toolboxes that are not part of this repository.

## Required For Full MATLAB Evaluation

- SONICOM HRTF SOFA files, preferably the `*_FreeFieldCompMinPhase_48kHz.sofa` variants used in the manuscript evaluation.
- MATLAB with the Signal Processing and Statistics and Machine Learning Toolboxes (developed with R2025a).
- AMT 1.6, including the SOFA toolbox path used by AMT.
- SUpDEq and its distributed third-party dependencies.

Expected locations, relative to the project root (all set in `matlab/fisher_rao_config.m`):

- `dependencies/Sonicom_HRTFs/` (searched recursively for `*_FreeFieldCompMinPhase_48kHz.sofa`)
- `dependencies/amtoolbox-full-1.6.0/amtoolbox-1.6.0/`
- `dependencies/SOFA Toolbox for Matlab and Octave 2.2.0/SOFAtoolbox/`
- `dependencies/AuditoryToolbox/`
- `dependencies/SUpDEq-master/SUpDEq-master/` with its `thirdParty/` folder (AKtools, SOFiA, SFS,
  TriangleRayIntersection)
- `ml_sofas_without_node_replacement/<METHOD>/N###/Sonicom_<id>.sofa` for RANF and FSP-AE

The dataset and comparator folders can be moved with the `DatasetRoot` and `ComparatorRoot`
options of `fisher_rao_config`. The toolbox installations are used unmodified; two compatibility
shims for current MATLAB are described in `matlab/compatibility/README.md`.

## Required For Machine-Learning Comparator Outputs

The repository provides wrappers for the comparator protocol. The external method repositories and generated outputs are kept outside git:

- RANF: Masuyama et al., Retrieval-Augmented Neural Field for HRTF upsampling/personalisation.
- FSP-AE: Ito et al., spatial upsampling of HRTFs using a neural network conditioned on source position and frequency.

Generated SOFA files, model checkpoints, and local training work directories should remain outside git.

For the reported evaluation, each model is trained on the 162 training subjects of
`ml_comparator_research/comparator_protocol/outputs/hu_hrtfformer_protocol.json` and its complete
predicted fields (no retained-node replacement) are staged with

```bash
python ml_comparator_research/comparator_protocol/stage_raw_ml_comparator_sofas.py --out-root ml_sofas_without_node_replacement
```

which gives `ml_sofas_without_node_replacement/<METHOD>/N###/Sonicom_<id>.sofa`, the layout read by
`run_evaluation.m`.
