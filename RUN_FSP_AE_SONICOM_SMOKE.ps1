param(
    [Parameter(Mandatory = $true)]
    [string]$SonicomRoot,
    [string]$Device = "cuda"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

python -c "import torch, torchaudio, numpy, scipy, netCDF4, sofa, yaml; print('torch', torch.__version__); print('torchaudio', torchaudio.__version__); print('CUDA', torch.cuda.is_available()); print('GPU', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Missing FSP-AE dependencies. Install ml_comparator_research\fsp_ae_sonicom\requirements.txt without replacing the working CUDA torch build."
    exit $LASTEXITCODE
}

python .\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py validate `
    --sonicom-root $SonicomRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python .\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py smoke `
    --sonicom-root $SonicomRoot --device $Device
exit $LASTEXITCODE
