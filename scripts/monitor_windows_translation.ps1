param(
  [string]$ServiceLogPattern = 'logs\service-*.log',
  [string]$TunnelLogPattern = 'logs\tunnel-*.log'
)

$ErrorActionPreference = 'Stop'

function Get-LatestFile {
  param([string]$Pattern)
  Get-ChildItem $Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$service = Get-LatestFile $ServiceLogPattern
$tunnel = Get-LatestFile $TunnelLogPattern

if (-not $service -and -not $tunnel) {
  Write-Host 'No logs found yet. Start the service and tunnel first.'
  exit 1
}

$positions = @{}
if ($service) { $positions[$service.FullName] = 0 }
if ($tunnel) { $positions[$tunnel.FullName] = 0 }

Write-Host 'Monitoring logs. Press Ctrl+C to stop.'
Write-Host ''

while ($true) {
  foreach ($path in @($service.FullName, $tunnel.FullName)) {
    if (-not $path) { continue }
    if (-not (Test-Path $path)) { continue }

    $content = Get-Content $path
    $start = $positions[$path]
    if ($content.Length -gt $start) {
      $newLines = $content[$start..($content.Length - 1)]
      foreach ($line in $newLines) {
        Write-Host "[$([IO.Path]::GetFileNameWithoutExtension($path))] $line"
      }
      $positions[$path] = $content.Length
    }
  }
  Start-Sleep -Seconds 2
}
