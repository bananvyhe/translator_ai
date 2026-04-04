param()

$ErrorActionPreference = 'Stop'

$wrapperPath = 'C:\cofex\translation\start_onezerominer_wrapper.cmd'
$titleHint = 'farmspot miner'

try {
  $cmdProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -ieq 'cmd.exe' -and
    $_.CommandLine -and
    $_.CommandLine -match [regex]::Escape($wrapperPath)
  }

  if (-not $cmdProcesses) {
    Write-Host "[miner] wrapper cmd not found"
    return
  }

  foreach ($process in $cmdProcesses) {
    $windowTitle = $null
    try {
      $windowTitle = (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue).MainWindowTitle
    } catch {
    }

    if ($windowTitle -and $windowTitle -notlike "*$titleHint*") {
      Write-Host "[miner] skip pid $($process.ProcessId); title='$windowTitle'"
      continue
    }

    try {
      & taskkill /PID $process.ProcessId /T /F | Out-Null
      Write-Host "[miner] stopped wrapper pid $($process.ProcessId)"
    } catch {
      Write-Warning ("[miner] failed to stop wrapper pid {0}: {1}" -f $process.ProcessId, $_.Exception.Message)
    }
  }
} catch {
  Write-Warning ("[miner] wrapper stop check failed: {0}" -f $_.Exception.Message)
}
