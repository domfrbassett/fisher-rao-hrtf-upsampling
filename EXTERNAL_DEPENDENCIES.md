# External Dependencies

This repository does not vendor third-party datasets or toolboxes.

## Required For Full MATLAB Evaluation

- SONICOM HRTF SOFA files, preferably the `*_FreeFieldCompMinPhase_48kHz.sofa` variants used in the manuscript evaluation.
- MATLAB with the Statistics and Machine Learning Toolbox.
- AMT, including the SOFA toolbox path used by AMT.
- SUpDEq and its distributed third-party dependencies.

The evaluation script supports the following environment overrides:

- `FISHERRAO_DATASET_ROOT`: root folder containing SONICOM SOFA files.
- `FISHERRAO_SOFA_FILE_PATTERN`: SOFA filename pattern.
- `FISHERRAO_RESULTS_NAME`: output folder name under `results/`.
- `FISHERRAO_METHODS`: comma-separated method subset.
- `FISHERRAO_PERCEPTUAL_METHODS`: comma-separated method subset for the Barumerli-style localisation evaluation.
- `FISHERRAO_PERCEPTUAL_NUM_EXPERIMENTS`: number of Monte Carlo repetitions.
- `FISHERRAO_PERCEPTUAL_ONLY`: set to `true` to resume/run only localisation metrics where supported.

## Required For Machine-Learning Comparator Outputs

The public paper repository contains wrappers, not cloned upstream repositories or trained outputs. Clone the external repositories separately and point the wrappers at them:

- RANF: Masuyama et al., Retrieval-Augmented Neural Field for HRTF upsampling/personalisation.
- FSP-AE: Ito et al., spatial upsampling of HRTFs using a neural network conditioned on source position and frequency.

Generated SOFA files, model checkpoints, and local training work directories should remain outside git.

