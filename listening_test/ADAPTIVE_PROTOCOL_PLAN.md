# Adaptive 2AFC Direction-Discrimination Protocol

## Aim

The adaptive study estimates angular discrimination thresholds rather than
accuracy at a fixed offset. This gives a behavioural threshold that can be
compared after collection with the Fisher/CRB-predicted local scale and with
reconstruction-induced AIRM discrepancy.

The adaptive staircase itself is not driven by the Fisher prediction. Fisher
tensors are used only to select sensible starting regions and to interpret the
resulting threshold estimates.

## Participant Task

Each comparison contains two sounds, A and B, rendered from the same HRTF
field. One sound is the standard direction and the other is displaced along one
local tangent axis. The formal sub-grid bank uses SUpDEq barycentric rendering
with magnitude correction and minimum-phase reconstruction. RANF and FSP-AE
stimuli use raw full-field inference outputs for rendering, not the LAP-style
retained-node-replaced SOFAs, because stitching measured retained nodes into a
generated dense field introduced artificial discontinuities under continuous
interpolation.

- lateral blocks: choose whether A or B sounded farther left;
- polar blocks: choose whether A or B sounded higher.

The A/B order is randomised independently for every comparison.
For formal adaptive tracks, the displaced sound is also randomised across
the two sides of the standard direction. Thus the displaced HRTF may be either
farther left or farther right in lateral tracks, and either above or below in
polar tracks. This prevents any residual timbral difference between the
standard and displaced renderings from predicting the correct response.

## Staircase Rule

The browser implements a hybrid staircase:

- before the first reversal, one correct response makes the next comparison
  harder, so easy separations are crossed quickly;
- after the first reversal, two consecutive correct responses make the next
  comparison harder;
- one incorrect response makes the next comparison easier;
- the angular separation levels are pre-rendered WAV pairs sorted from easy
  to difficult;
- the default stopping rule is 6 reversals after at least 14 comparisons, or
  24 comparisons maximum;
- the provisional threshold estimate stored with the response is the median
  reversal separation after the first two reversals, falling back to the
  median of the latter half of the track if there are too few reversals.

This rule converges near 70.7% correct. If a later protocol requires the
2AFC equivalent of \(d'=1\), the rule can be changed to a QUEST/weighted
staircase targeting approximately 76% correct.

## Compact Formal Set

Use a small number of virtual HRTF identities and methods. The adaptive
procedure multiplies trial count by the number of tracks, so the first formal
study should not mirror the entire objective benchmark.

Representative virtual identities:

- `P0100`
- `P0080`
- `P0033`
- `P0104`

These were selected as a compact subject bank close to the 41-subject cohort
median over the listening-test methods and retention conditions. Selection
used aggregate AIRM, LSD, ILD, and relative Barumerli localisation errors for
`SUpDEq-MCA`, `RANF`, and `FSP-AE` at `N=19` and `N=5`.

Recommended fields:

- `Measured`, `N=793`
- `SUpDEq_MCA`, `N=19` and `N=5`
- `RANF`, `N=19` and `N=5`
- `FSP_AE`, `N=19` and `N=5`

The compact sub-grid bank samples a balanced subset of these conditions rather than
the full Cartesian product. Lateral discrimination is sampled within the
frontal hemifield on the horizontal plane. Polar discrimination is sampled at
frontal-hemifield azimuths with azimuth held constant and elevation displaced
upward:

```text
lateral anchors: (-45,0), (0,0), (45,0)
polar anchors:   (-45,0), (0,0), (45,0)
```

The rendered bank contains all four virtual HRTF identities within each
participant's test, avoiding a whole-session dependence on one non-individual
HRTF. The current compact bank has 32 adaptive tracks, split into four
8-track sections:

```text
2 lateral sections + 2 polar sections
```

Across the full bank, `SUpDEq_MCA`, `RANF`, and `FSP_AE` each appear at both
`N=19` and `N=5`, alongside measured-reference tracks for the same virtual
subjects. Sections may be completed in separate sittings; if the participant
resumes later, the audio check is repeated before continuing.

## Build Command

From the project root, build the adaptive bank with:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1
```

The command exports the selected HRIR fields and fresh Fisher tensors,
generates the adaptive condition plan, renders the offline WAV levels, writes
`public/config/trials.adaptive.json`, and audits the manifest. Open the study
with:

```text
http://127.0.0.1:4173/?config=config/experiment.adaptive.json
```

## Angular Levels

Lateral tracks use the following requested angular offsets:

```text
lateral: 30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25 deg
```

Polar tracks use:

```text
polar: 30, 20, 15, 10, 7, 5, 3.5, 2.5 deg
```

The same requested standard/target directions are used for every method within
a subject, axis, anchor, and level.

## Analysis

For each listener and adaptive track, estimate a threshold in degrees. Primary
comparisons:

1. dense measured threshold versus dense Fisher/CRB prediction;
2. reconstructed threshold minus dense measured threshold;
3. threshold change versus local AIRM discrepancy;
4. threshold change versus LSD and Bayesian-observer summaries.

The main behavioural claim should concern preservation of local
discriminability, not absolute localisation accuracy.
