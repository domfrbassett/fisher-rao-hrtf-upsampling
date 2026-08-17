param(
    [string]$SonicomRoot = "",
    [string]$SofaFilePattern = "*_FreeFieldCompMinPhase_48kHz.sofa",
    [string]$MatlabCommand = "matlab",
    [switch]$SkipExport,
    [switch]$Subgrid,
    [string]$RenderInterpolation = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProtocolJson = Join-Path $ProjectRoot "ml_comparator_research\comparator_protocol\outputs\hu_hrtfformer_protocol.json"
$Runner = Join-Path $ProjectRoot "listening_test\matlab\run_adaptive_2ifc_export_and_build.m"

if (-not (Test-Path $ProtocolJson)) {
    throw "Comparator protocol JSON not found: $ProtocolJson"
}
if (-not (Test-Path $Runner)) {
    throw "Adaptive MATLAB runner not found: $Runner"
}

$env:FISHER_RAO_BEHAVIOURAL_EXPORT_ONLY = "true"
$env:FISHERRAO_COMPARATOR_PROTOCOL_JSON = $ProtocolJson
$env:FISHERRAO_METHODS = "SUpDEq_MCA,RANF,FSP_AE"
$env:FISHERRAO_SOFA_FILE_PATTERN = $SofaFilePattern
$env:FISHERRAO_USE_RANF_RAW_FOR_RENDERING = "true"
$env:FISHERRAO_USE_FSP_AE_RAW_FOR_RENDERING = "true"
if ($RenderInterpolation.Trim().Length -gt 0) {
    $env:FISHERRAO_ADAPTIVE_RENDER_INTERPOLATION = $RenderInterpolation
}
elseif ($Subgrid) {
    $env:FISHERRAO_ADAPTIVE_RENDER_INTERPOLATION = "SUpDEq_Bary_MCA_6dB"
}

if ($SonicomRoot.Trim().Length -gt 0) {
    if (-not (Test-Path $SonicomRoot)) {
        throw "SONICOM root does not exist: $SonicomRoot"
    }
    $env:FISHERRAO_DATASET_ROOT = $SonicomRoot
}

try {
    $MatlabPath = Join-Path $ProjectRoot "listening_test\matlab"
    $SkipExportValue = if ($SkipExport) { "true" } else { "false" }
    & $MatlabCommand -batch "addpath('$MatlabPath','-begin'); run_adaptive_2ifc_export_and_build('$ProjectRoot', $SkipExportValue)"
    if ($LASTEXITCODE -ne 0) {
        throw "MATLAB exited with status $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:FISHER_RAO_BEHAVIOURAL_EXPORT_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:FISHERRAO_COMPARATOR_PROTOCOL_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:FISHERRAO_METHODS -ErrorAction SilentlyContinue
    Remove-Item Env:FISHERRAO_SOFA_FILE_PATTERN -ErrorAction SilentlyContinue
    Remove-Item Env:FISHERRAO_ADAPTIVE_RENDER_INTERPOLATION -ErrorAction SilentlyContinue
    Remove-Item Env:FISHERRAO_USE_RANF_RAW_FOR_RENDERING -ErrorAction SilentlyContinue
    Remove-Item Env:FISHERRAO_USE_FSP_AE_RAW_FOR_RENDERING -ErrorAction SilentlyContinue
    if ($SonicomRoot.Trim().Length -gt 0) {
        Remove-Item Env:FISHERRAO_DATASET_ROOT -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Adaptive listening-test build complete."
Write-Host "Open:"
Write-Host "  http://127.0.0.1:4173/?config=config/experiment.adaptive.json"
