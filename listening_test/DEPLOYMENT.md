# Cloudflare deployment and data export

The public study is a Cloudflare Worker with static assets and a D1 database.
MATLAB is required only to rebuild the audio bank, not to serve the experiment.

## Live study

```text
https://fisher-rao-hrtf-2ifc.fr-hrtf-study.workers.dev/
```

The Worker is `fisher-rao-hrtf-2ifc`. Its `DB` binding points to
`fisher-rao-hrtf-2ifc-db`. Participant responses, pauses, and completions are
stored in D1; closing a browser does not remove submitted responses.

## Deploy

Run from `listening_test`:

```powershell
npm.cmd run check
npx.cmd wrangler deploy
```

The deployment uploads `public/`, including all files beneath
`public/audio/adaptive/`, and deploys `worker/sites-worker.js`.

## Protect response export

The CSV endpoint requires a Worker secret named `EXPORT_KEY`. Set or replace it
with:

```powershell
npx.cmd wrangler secret put EXPORT_KEY
```

Wrangler prompts for the value. Do not place the key in `wrangler.toml` or the
repository.

## Export every response

```powershell
$key = Read-Host "Export key"
$headers = @{ Authorization = "Bearer $key" }
Invoke-WebRequest `
  -Uri "https://fisher-rao-hrtf-2ifc.fr-hrtf-study.workers.dev/api/export.csv" `
  -Headers $headers `
  -OutFile ".\responses.csv"
```

## Extract one participant

```powershell
$code = "PARTICIPANT_CODE"
Import-Csv ".\responses.csv" |
  Where-Object participantCode -eq $code |
  Export-Csv ".\responses_$code.csv" -NoTypeInformation
```

## Check the deployment

```powershell
curl.exe "https://fisher-rao-hrtf-2ifc.fr-hrtf-study.workers.dev/api/health"
```

The health response should identify the Cloudflare D1 store. Test the complete
participant flow after every manifest deployment: consent, headphone check,
practice, one formal response, pause, and resume with the same participant
code.

## Data handling

Participant codes must not contain names or email addresses. Keep exported CSV
files in the approved university research-data location and limit access to the
researcher and authorised supervisors. Records from earlier pilot manifests
remain separable through the `manifestVersion` field.
