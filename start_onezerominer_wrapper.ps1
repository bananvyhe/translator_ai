param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$minerRoot = 'C:\bbb\onezerominer-win64-1.7.4'

$logDir = Join-Path $root 'logs'
if (-not (Test-Path $logDir)) {
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$pidPath = Join-Path $logDir 'farmspot_miner.pid'

$batPath = Join-Path $minerRoot 'qubitcoin.bat'
$cmdArgs = @(
  '/d',
  '/c',
  "cd /d `"$minerRoot`" && call `"$batPath`""
)

$process = Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdArgs -WorkingDirectory $minerRoot -PassThru
Set-Content -LiteralPath $pidPath -Value $process.Id
