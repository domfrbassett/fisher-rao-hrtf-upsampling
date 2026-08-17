# HTTPS Deployment Notes

This listening study is designed for deployment as a static web application
with API routes for session and response storage. The browser plays
pre-rendered WAV files; no MATLAB code is required on the server.

The current deployment uses Cloudflare Workers, static assets, and D1:

```text
https://fisher-rao-hrtf-2ifc.fr-hrtf-study.workers.dev/
```

## Requirements

For participant testing, use a university-approved or supervisor-approved
hosting route where:

- the site is served over HTTPS;
- response data are stored persistently, for example in D1;
- access to `/api/export.csv` is protected with `EXPORT_KEY`;
- generated WAV stimuli in `public/audio/adaptive/` are included in the
  deployed artifact;
- institutional data-protection and ethics requirements are satisfied.

## Files That Must Be Deployed

Deploy the `listening_test` folder with:

- `package.json`
- `worker/sites-worker.js`
- `public/`
- `public/audio/adaptive/*.wav`
- `public/config/trials.adaptive.json`
- `public/config/experiment.adaptive.json`

The `.mat` files in `fields/` are not needed by participants. They are needed
only when rebuilding the stimulus bank or running MATLAB-side checks, and are
therefore excluded from Git.

## Cloudflare Setup

Create a D1 database and insert the resulting database ID into
`wrangler.toml`:

```powershell
npx.cmd wrangler d1 create fisher-rao-hrtf-2ifc-db
```

The Worker creates the required D1 tables and indexes on first request.

Set the export key:

```powershell
npx.cmd wrangler secret put EXPORT_KEY
```

Deploy:

```powershell
npx.cmd wrangler deploy
```

## Data Export

The CSV export endpoint is:

```text
https://<worker-url>/api/export.csv?key=<EXPORT_KEY>
```

For a direct D1 backup:

```powershell
npx.cmd wrangler d1 export fisher-rao-hrtf-2ifc-db --remote --output ".\exports\d1_backup.sql"
```

For local testing without Cloudflare, run `node server\server.js`; responses
are written to `server/data/`.

## Remote-Testing Caveats

Remote participation is technically possible but less controlled than a
supervised lab session. The participant information and ethics application
should account for:

- headphone requirement and left/right channel checking;
- quiet-room self-report;
- inability to verify exact headphone model and playback level;
- browser/device variability;
- withdrawal and deletion procedures for coded response data.
