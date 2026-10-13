# PGE spectral-noise calibration (σ_mon = 2.85 dB)

The paper's sensitivity analysis uses σ_mon = 2.85 dB, the median effective noise of the positive
spectral-gradient (PGE) cues, estimated from localisation responses with the two-stage
maximum-likelihood procedure of Barumerli et al. (2026). This folder documents that estimate; the
per-participant results are in `results/pge_calibration/`.

## What was fitted

- **Model and procedure.** The Bayesian observer of Barumerli et al. (2023) with the two-stage fit
  of Barumerli et al. (2026): σ_ITD = 0.569 and σ_ILD = 1 dB fixed; stage 1 estimates residual
  response scatter (σ_motor) from ITD + ILD on targets within ±30° lateral angle; stage 2 fits
  σ_spectral and the prior width σ_prior jointly by BADS, with σ_motor fixed. SHMAX template
  interpolation, 200 Monte Carlo samples in each stage, seed 42.
- **Features.** PGE cues (Barumerli et al., 2023): positive differences of adjacent 1-ERB gammatone
  band levels, computed at the measured directions and then spatially interpolated (gradients first,
  because half-wave rectification does not commute with interpolation). The band is the package
  default, 0.7–18 kHz; the Fisher analysis uses 0.7–16 kHz.
- **Data.** SONICOM Multi-Experiment Auditory Localisation Dataset
  (<https://ecosystem.sonicom.eu/databases/58>), file `AXD_full_dataset_20260202.csv`, condition
  `Measured`: 5,742 trials from all 34 participants, 33 target directions (one experiment's
  210–330° azimuths mapped to −150 to −30°), each participant's own SONICOM
  `FreeFieldCompMinPhase_48kHz` HRTF. The data are not redistributed here.

## Code

The fit uses the released `bayesian_listener` package
(<https://github.com/robaru/bayesian_listener>, commit `7961faa`, v0.2.0), in which the PGE
convention is a stub. `bayesian_listener_pge.patch` implements it, passes the convention through
both fitting stages, and fixes an overflow of I0(κ) in the stage-1 likelihood at large κ. The
patch is distributed under the EUPL-1.2, the package's licence.

| Script | Purpose |
|---|---|
| `run_pge_population_fit.py` | resumable participant-wise fits → per-participant CSV |
| `summarise_pge_population_fit.py` | population summary, bootstrap intervals, leave-one-out sensitivity, parameter-bound flags |
| `audit_pge_local_identifiability.py` | optional: local finite-difference check of σ_spectral / σ_prior separability at each solution |

To reproduce, check out the package at `7961faa`, `git apply bayesian_listener_pge.patch`, copy
the three scripts into its `scripts/` folder, place the response table in `data/` and the 34 SOFA
files in `data/sonicom_hrtf/`, and run `run_pge_population_fit.py` (about 5 min per participant)
followed by `summarise_pge_population_fit.py`.

## Results (34 participants, all fits converged)

| Parameter | Median | IQR | Range |
|---|---|---|---|
| σ_spectral (PGE), dB | **2.85** | 2.27–3.51 | 1.30–6.54 |
| σ_motor, deg | 7.0 | 5.3–13.6 | 1.8–37.8 |
| σ_prior, deg | 68 | 38–118 | 7–180 |

- Bootstrap 95% interval of the σ_spectral median: 2.52–3.29 dB; leave-one-out medians:
  2.80–2.91 dB.
- Five fits lie near a parameter bound (P0003, P0172, P0224, P0259, P0348; prior or motor bound,
  none on σ_spectral). Excluding them gives a median of 2.80 dB.
- Correlation between σ_spectral and σ_prior across participants: Pearson r = 0.02
  (Spearman −0.08).

## Interpretation

The estimate is an effective PGE observation noise for this observer (cue extraction, template
interpolation, prior, response model, target set and likelihood), calibrated to localisation
behaviour. It is not a PGE discrimination threshold. The two-stage fit reduces, but does not
remove, the trade-off between spectral noise and prior width, and the parameter-recovery study of
Barumerli et al. (2026) used spectral amplitudes, so recovery for PGE features is not established.
The dataset lists 34 participants and Barumerli et al. report fits for 33, without a stated
exclusion; all 34 are used here.

## References

- R. Barumerli et al., "A Bayesian model for human directional localization of broadband static
  sound sources," *Acta Acust.*, vol. 7, Art. no. 12, 2023.
- R. Barumerli et al., "Statistical validation and full-sphere extension of a Bayesian model for
  human static sound localisation," *Acta Acust.*, vol. 10, Art. no. 89, 2026,
  doi:10.1051/aacus/2026084.
