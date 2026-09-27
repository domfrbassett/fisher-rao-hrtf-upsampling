# Lateral 2AFC Threshold Protocol

## Purpose

The experiment estimates the angular separation producing 76% correct in a
two-alternative forced-choice (2AFC) lateral judgement. For unbiased 2AFC,
`d' = 1` gives `Phi(1/sqrt(2)) = 0.76025` proportion correct; 0.76 is used in
the implementation. Threshold estimation is
independent of the Fisher prediction; the predicted local threshold is used
only in the subsequent comparison with behaviour.

## Stimuli and task

Each trial contains two 650 ms binaural white-noise bursts separated by
400 ms. One uses the HRTF at a fixed horizontal-plane anchor and the other a
direction displaced by the selected angular separation. The participant clicks
the sound, A or B, that appeared farther to the left.

The following are independently randomised on every formal trial:

- whether the displaced direction is clockwise or anticlockwise from the
  anchor;
- whether the standard or displaced stimulus is presented as A;
- a common trial-level gain in the range +/-1.5 dB.

The same gain is applied to A and B. The two intervals at a given anchor and
separation are convolved with the same noise token. These controls prevent
interval order, displacement sign, source waveform, or absolute level from
identifying the response.

## Adaptive method

Stimulus placement follows a Bayesian adaptive method based on the psi/QUEST+
principle. The response model is a two-choice Weibull psychometric function.
After each answer, Bayes' rule updates a joint posterior over threshold, slope,
and lapse rate. The next separation is the available level with the lowest
expected posterior entropy.

Configuration:

- target performance: 0.76 proportion correct;
- 40 trials per track;
- candidate separations: 30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25,
  0.9, and 0.6 degrees;
- threshold prior: 51 equally weighted log-spaced values from 0.6 to
  15 degrees;
- slope values: 1.5, 2, 3, 4, 6, and 8;
- lapse rates: 0, 0.02, and 0.05;
- threshold estimate: posterior geometric mean;
- uncertainty interval: 95% equal-tailed posterior credible interval.

Tracks use a fixed 40-trial budget instead of a reversal stopping rule. This
avoids condition-dependent stopping and produces a posterior uncertainty
estimate for every completed track. Estimates at 0.6 or 15 degrees must be
reported as boundary-limited rather than as resolved thresholds beyond the
stimulus range.

The adaptive method follows the joint threshold-and-slope Bayesian procedure
of [Kontsevich and Tyler (1999)](https://doi.org/10.1016/S0042-6989(98)00285-5)
and the more general QUEST+ formulation of
[Watson (2017)](https://doi.org/10.1167/17.3.10). The 40-trial budget was also
checked by simulation over thresholds from 0.75 to 14 degrees, slopes from 1.5
to 8, and lapse rates from 0 to 0.05. The saved simulation report is
`audit/adaptive_simulation.json`.

## Conditions

The listening bank uses SONICOM subject P0033. This subject minimises the mean
absolute robust-standardised distance from the 41-subject median across LSD,
ILD error, and the lateral, local-polar, and quadrant localisation errors.
Fisher-derived quantities were excluded from subject selection.

Seven field conditions are tested:

- measured dense HRTF, N=793;
- SUpDEq-MCA, N=5 and N=19;
- RANF, N=5 and N=19;
- FSP-AE, N=5 and N=19.

RANF and FSP-AE use raw full-field outputs without retained-node replacement.
This avoids the phase discontinuities introduced when measured HRIRs are
stitched into an otherwise generated field.

Four anchor instances are used on the horizontal plane: -45, 0, +45, and a
second independent track at 0 degrees. Every participant completes all seven
conditions at every anchor instance, giving 28 threshold tracks. The repeated
frontal anchor permits a within-session reliability check.

Tracks are divided into four seven-track blocks. Both block order and track
order within each block are randomised per participant. Each block therefore
contains 280 formal responses and is expected to take approximately 12-18
minutes. Participants may stop between blocks and resume with the same code;
the left/right headphone check is repeated after a later resumption.
The block length follows the recommendation that uninterrupted listening
sessions should not exceed approximately 15-20 minutes in
[ITU-R BS.1679-1](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1679-1-201510-I%21%21PDF-E.pdf).

## Rendering

All formal audio is rendered offline at 48 kHz as stereo 24-bit WAV. A single
650 ms Gaussian white-noise token with 20 ms cosine onset and offset ramps is
used for each anchor/separation pair across all methods. HRTFs at intermediate
directions are rendered using the SUpDEq preprocessing, barycentric
interpolation, and magnitude-correction chain with a 6 dB maximum boost and
minimum-phase magnitude correction. Within each comparison, standard and
target signals share a common peak normalisation.

## Analysis

Only complete 40-trial tracks enter the primary analysis. The basic outcome is
the posterior threshold in degrees with its 95% credible interval. The primary
method comparison is the log threshold difference between each reconstructed
condition and the measured condition at the same anchor. A repeated-measures
model should use the seven-level field condition, anchor, and their interaction
as fixed effects, with participant as a random intercept and a participant
random slope when supported by the data. Planned contrasts compare each
reconstruction with the measured field at the matched anchor, with multiplicity
control declared before analysis. The association between behavioural
threshold error and local Fisher-predicted threshold error is the principal
validation analysis; AIRM, LSD, and ILD error are secondary predictors.

The frontal repeat should be analysed separately as a within-session
repeatability check. Boundary-limited estimates should be identified and
included in a sensitivity analysis rather than treated as measurements beyond
the tested range. Pilot records and tracks from earlier manifest versions must
not be pooled with the current protocol.

## Build

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 -SkipExport
```

The command writes the condition plan, renders the WAV bank, creates
`public/config/trials.adaptive.json`, and audits all tracks and file references.
