# Web 2IFC HRTF Discrimination Study

This folder contains the two-interval listening-test application developed for
behavioural validation of the Fisher-Rao/AIRM evaluation. It implements a true
two-interval forced-choice design: in each comparison the listener hears two
binaural intervals and identifies the interval displaced in a stated spatial
direction.

The current protocol is an **adaptive 2AFC bank**: each track starts at an easy
angular offset and narrows or widens the separation according to listener
responses. This estimates a behavioural angular threshold that can be compared after data
collection with the Fisher/CRB-predicted local MAA scale and AIRM discrepancy.
The synthetic `trials.demo.json` manifest remains available only as an
interface-development fallback.

The source code, configuration manifests and rendering scripts are versioned
here. The generated WAV bank, intermediate HRIR/tensor fields and participant
responses are not committed.

## Experiment Design

- Adaptive blocks contain separate lateral and polar discrimination tracks,
  avoiding an ambiguous "different location" judgement.
- Each formal track compares an anchor direction with a nearby displaced
  direction within one HRTF field: measured reference or one reconstructed
  method/retention condition.
- Angular separation is controlled by a hybrid staircase: rapid one-correct
  descent until the first reversal, followed by a two-down/one-up rule. The
  staircase is independent of the Fisher prediction; Fisher quantities are
  stored for later modelling.
- Target interval order is randomised from a server-issued seeded session.
- The displaced target side is also randomised in adaptive tracks. Hearing a
  residual target-rendering artefact therefore does not identify whether the
  correct response is the target or the fixed standard.
- Formal blocks do not provide feedback or replay. Practice blocks do.
- A common within-pair normalisation retains binaural cues. Optional
  interval-level roving discourages overall-level shortcuts.
- Adaptive comparisons are pre-rendered with SUpDEq barycentric interpolation,
  magnitude correction and minimum-phase reconstruction. RANF and FSP-AE use
  raw no-node-replacement fields for rendering to avoid discontinuities at the
  retained nodes.
- Each trial carries the local reference/reconstructed predicted
  discriminability, local AIRM distance, LSD and ILD metadata for subsequent
  behavioural modelling.

This tests whether interpolation alters discrimination performance relative
to the measured-HRTF condition, and whether those changes follow the proposed
local metric distortion.

## Files

- `public/`: participant-facing experiment and trial configuration.
- `public/consent.html`: participant information and consent wording.
- `server/server.js`: local Node server and append-only response store.
- `worker/sites-worker.js`: Cloudflare Worker used for the HTTPS deployment.
- `server/data/`: local session and response records, excluded from Git.
- `DEPLOYMENT.md`: notes for the Cloudflare Worker/D1 deployment.
- `matlab/build_adaptive_2ifc_stimulus_bank.m`: offline WAV and adaptive
  staircase-manifest generator.
- `matlab/adaptive_condition_plan_template.csv`: template for adaptive
  staircase levels.
- `matlab/analyse_2ifc_responses.m`: summary plots and optional mixed-effects
  model.
- `ADAPTIVE_PROTOCOL_PLAN.md`: recommended adaptive threshold protocol,
  staircase rule, representative subjects and compact method set.
- `public/researcher.html`: stimulus-bank readiness audit page.

## Run The Listening Study

From this folder in PowerShell, run:

```powershell
node server\server.js
```

Then open `http://127.0.0.1:4173`. Local responses are appended to
`server/data/responses.ndjson`. Download a CSV for analysis at:

```text
http://127.0.0.1:4173/api/export.csv
```

For local use beyond a controlled machine, set an export password before
starting the server:

```powershell
$env:EXPORT_KEY = "choose-a-strong-key"
```

The export URL then requires `?key=choose-a-strong-key`.

The researcher preparation view is available at:

```text
http://127.0.0.1:4173/researcher.html
```

Open the adaptive study with:

```text
http://127.0.0.1:4173/?config=config/experiment.adaptive.json
```

## Adaptive Stimulus Generation

The web application never spatialises audio in real time. This prevents
browser or network timing from entering the acoustic comparison. The adaptive
bank is built from the project root with one command:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1
```

If the SONICOM files are outside `dependencies\Sonicom_HRTFs`, pass their
root explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 `
  -SonicomRoot "<path-to-SONICOM-FreeFieldCompMinPhase-root>"
```

This exports the dense measured control plus `SUpDEq_MCA`, `RANF`, and
`FSP_AE` fields at `N=19` and `N=5` for the selected representative subjects,
recomputes fresh Fisher tensors, writes `matlab/adaptive_condition_plan.csv`,
renders WAVs to `public/audio/adaptive/`, writes
`public/config/trials.adaptive.json`, and audits the rendered adaptive
manifest.

The adaptive spatial coverage is restricted to avoid wrap-around judgements at
the ears and ambiguous over-the-head elevation judgements:

- lateral discrimination at `(az, el) = (-45,0), (0,0), (45,0)`;
- polar discrimination at `(-45,0), (0,0), (45,0)`, with azimuth held
  constant.

The current sub-grid protocol uses requested offsets of
`30, 20, 15, 10, 7, 5, 3.5, 2.5, 1.75, 1.25` degrees for lateral tracks and
`30, 20, 15, 10, 7, 5, 3.5, 2.5` degrees for polar tracks.

The rendered bank contains four representative SONICOM subjects: `P0100`,
`P0080`, `P0033`, and `P0104`. These subjects are mixed within each
participant's test rather than assigning one virtual HRTF subject to the whole
session. This reduces the risk that performance is dominated by a single
personalisation/depersonalisation mismatch.

The compact bank has 32 tracks: 16 lateral and 16 polar, split into four
8-track sections. Across the bank, `SUpDEq_MCA`, `RANF`, and `FSP_AE` each
appear at both `N=19` and `N=5`. The staircase descends after one correct
response until the first reversal, then switches to two-down/one-up. Tracks
stop after six reversals, strong performance at the finest available level, or
24 comparisons. Sections can be completed in separate sittings; a participant
who resumes later repeats the audio check before continuing.

The lower-level MATLAB call used after field export is:

```matlab
manifest = build_adaptive_2ifc_stimulus_bank( ...
    fullfile(studyRoot, "matlab", "adaptive_condition_plan.csv"), ...
    fullfile(studyRoot, "public"));
```

This writes WAVs to `public/audio/adaptive/` and the adaptive manifest to
`public/config/trials.adaptive.json`. The adaptive design is stated in
`ADAPTIVE_PROTOCOL_PLAN.md`.

## Analyse Responses

Export the response CSV, then run:

```matlab
results = analyse_2ifc_responses( ...
    fullfile(studyRoot, "responses.csv"), ...
    fullfile(studyRoot, "analysis_results"));
```

The analysis scripts report adaptive-track performance by axis, method and
retained-direction condition, and can relate behavioural thresholds to the
stored Fisher, AIRM, LSD and ILD metadata. Keep pilot and formal exports
separate; response files in `server/data/` are local working data and are not
versioned.

## Before Participants

Obtain the required ethics approval and informed-consent wording, choose
participant coding and secure data storage procedures, pilot the stimulus
spacing away from floor and ceiling performance, and document headphone,
quiet-room and hearing-screening requirements. Do not interpret responses
recorded using `trials.demo.json` as experimental data.
