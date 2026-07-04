param(
    [Parameter(Mandatory = $true)]
    [string]$SonicomRoot,
    [string]$Device = "cuda",
    [int]$Epochs = 1400,
    [switch]$Resume
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot
$Adapter = ".\ml_comparator_research\fsp_ae_sonicom\run_fsp_ae_sonicom.py"

$TrainArguments = @(
    $Adapter, "train",
    "--sonicom-root", $SonicomRoot,
    "--device", $Device,
    "--epochs", "$Epochs"
)
if ($Resume) { $TrainArguments += "--resume" }

python @TrainArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python $Adapter test --sonicom-root $SonicomRoot --device $Device
exit $LASTEXITCODE
