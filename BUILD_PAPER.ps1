$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stem = "Fisher_Rao_HRTF_Evaluation_IEEE_ArXiv"
Set-Location $projectRoot

$pdflatex = Get-Command pdflatex -ErrorAction SilentlyContinue
if ($pdflatex) {
    $pdflatexPath = $pdflatex.Source
}
else {
    $fallback = Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\x64\pdflatex.exe"
    if (-not (Test-Path -LiteralPath $fallback)) {
        throw "pdflatex was not found. Install MiKTeX or add an existing installation to PATH."
    }
    $pdflatexPath = $fallback
}

$auxiliaryExtensions = @(
    ".aux", ".log", ".out", ".toc", ".lof", ".lot",
    ".fls", ".fdb_latexmk", ".synctex.gz"
)
foreach ($extension in $auxiliaryExtensions) {
    $path = Join-Path $projectRoot ($stem + $extension)
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

for ($pass = 1; $pass -le 3; $pass++) {
    Write-Host "Compiling $stem (pass $pass/3)..."
    & $pdflatexPath -interaction=nonstopmode -halt-on-error ($stem + ".tex")
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed on pass $pass."
    }
}

Write-Host "Built $stem.pdf successfully."
