# HRTF Lateral Discrimination Study

This folder contains the listening experiment used to test whether HRTF
upsampling preserves local lateral discrimination. On each trial, the listener
hears two binaural white-noise sounds and selects A or B according to which
appeared farther to the left.

The current experiment uses Bayesian adaptive 2AFC tracks targeting 76%
correct (0.76025 before rounding), the 2AFC equivalent of `d' = 1`. See
`ADAPTIVE_PROTOCOL_PLAN.md` for the full design and analysis specification.

## Current formal bank

- SONICOM subject P0033, selected using non-Fisher evaluation metrics.
- Measured HRTFs and SUpDEq-MCA, RANF, and FSP-AE reconstructions.
- N=5 and N=19 for each reconstruction method.
- Horizontal-plane anchors at -45, 0, and +45 degrees, with an independent
  repeated frontal track.
- Seven conditions at four anchor instances: 28 tracks in four blocks.
- Forty trials per track and 280 formal responses per block.
- Candidate separations from 30 to 0.6 degrees.
- Raw, non-node-replaced RANF and FSP-AE fields.
- Offline SUpDEq barycentric rendering with magnitude correction.

Block order, track order, target side, and A/B order are randomised. A common
trial-level gain rove is applied to both intervals. Participants may pause
between blocks and resume with the same participant code.

## Main files

- `public/`: participant interface, configuration, and WAV bank.
- `public/adaptive.js`: Bayesian psychometric update and stimulus selection.
- `server/server.js`: local server and append-only response store.
- `worker/sites-worker.js`: Cloudflare Worker and D1 response storage.
- `matlab/`: condition selection, rendering, audit, and response analysis.
- `audit/`: traceable median-subject and condition-plan reports.
- `DEPLOYMENT.md`: Cloudflare deployment and response-export instructions.

## Run locally

From this folder:

```powershell
node server\server.js
```

Open:

```text
http://127.0.0.1:4173/
```

Local responses are appended beneath `server/data/`, which is excluded from
version control.

## Rebuild the formal bank

From the project root, when the current exported HRIR fields are already
present:

```powershell
powershell -ExecutionPolicy Bypass -File .\RUN_ADAPTIVE_2IFC_EXPORT.ps1 -SkipExport
```

To export fields again, omit `-SkipExport` and provide `-SonicomRoot` if the
SONICOM dataset is outside the configured dependency folder. The build writes
the condition plan, 24-bit WAVs, the JSON manifest, and a stimulus-bank audit.

## Check the application

```powershell
npm.cmd run check
```

This checks the local server, Worker, browser scripts, and Bayesian adaptive
implementation.

## Analyse responses

Export the response CSV and run:

```matlab
results = analyse_2ifc_responses( ...
    fullfile(studyRoot, "responses.csv"), ...
    fullfile(studyRoot, "analysis_results"));
```

The primary analysis includes complete 40-trial tracks from manifest
`adaptive-v9-lateral-psi-dprime1-raw-ml`. Earlier pilots remain identifiable
by manifest version and are excluded.
