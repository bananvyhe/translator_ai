param()

$ErrorActionPreference = 'Stop'

$title = 'farmspot miner'
$windowProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq $title }

if ($windowProcesses) {
  $ids = ($windowProcesses | Select-Object -ExpandProperty Id) -join ','
  Write-Host "[miner] closing window title='$title' pids=$ids"
  foreach ($process in $windowProcesses) {
    try {
      Stop-Process -Id $process.Id -Force -ErrorAction Stop
    } catch {
      Write-Warning ("[miner] failed to stop window pid {0}: {1}" -f $process.Id, $_.Exception.Message)
    }
  }
} else {
  Write-Host "[miner] window title '$title' not found"
}

try {
  $minerProcesses = Get-Process -Name 'onezerominer' -ErrorAction SilentlyContinue
  if ($minerProcesses) {
    $ids = ($minerProcesses | Select-Object -ExpandProperty Id) -join ','
    Write-Host "[miner] closing onezerominer pids=$ids"
    foreach ($process in $minerProcesses) {
      try {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
      } catch {
        Write-Warning ("[miner] failed to stop miner pid {0}: {1}" -f $process.Id, $_.Exception.Message)
      }
    }
  }
} catch {
  Write-Warning ("[miner] miner stop check failed: {0}" -f $_.Exception.Message)
}
