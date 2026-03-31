param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$pidPath = Join-Path $root 'logs\farmspot_miner.pid'
$minerBatPath = 'C:\bbb\onezerominer-win64-1.7.4\qubitcoin.bat'

function Stop-TreeByPid {
  param([int]$ProcessId)

  if ($ProcessId -le 0) {
    return
  }

  try {
    & taskkill /PID $ProcessId /T /F | Out-Null
  } catch {
  }
}

function Stop-MatchingProcesses {
  $titleMatch = 'farmspot miner'
  $batPattern = [regex]::Escape($minerBatPath)

  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like "*$titleMatch*" } |
    ForEach-Object { Stop-TreeByPid -ProcessId $_.Id }

  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -ieq 'cmd.exe' -and
      $_.CommandLine -and
      $_.CommandLine -match $batPattern
    } |
    ForEach-Object { Stop-TreeByPid -ProcessId $_.ProcessId }

  try {
    & taskkill /FI "WINDOWTITLE eq farmspot miner" /T /F | Out-Null
  } catch {
  }

  try {
    & taskkill /IM onezerominer.exe /T /F | Out-Null
  } catch {
  }
}

if (Test-Path -LiteralPath $pidPath) {
  $rawPid = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
  $targetPid = 0
  if ([int]::TryParse(($rawPid | ForEach-Object { $_.Trim() }), [ref]$targetPid) -and $targetPid -gt 0) {
    Stop-TreeByPid -ProcessId $targetPid
  }

  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

Stop-MatchingProcesses
