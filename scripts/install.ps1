$ErrorActionPreference = 'Stop'

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
  throw 'Python launcher (py) not found. Install Python 3.11 first.'
}

$versions = py -0p
if ($versions -notmatch '3\.11') {
  throw 'Python 3.11 is not installed. Install it with: winget install --id Python.Python.3.11 -e'
}

if (-not (Test-Path .venv)) {
  py -3.11 -m venv .venv
}

$python = Join-Path (Get-Location) '.venv\\Scripts\\python.exe'

& $python -m pip install --upgrade pip
& $python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
& $python -m pip install -r requirements.txt bitsandbytes

Write-Host 'Installation complete.'
Write-Host 'Next: copy .env.example to .env and set TRANSLATION_TOKEN + (optionally) HUGGINGFACE_HUB_TOKEN.'