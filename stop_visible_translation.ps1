param(
  [string]$TaskName = 'farmspot-translation',
  [switch]$DisableAutostart
)

$ErrorActionPreference = 'Stop'

& "$PSScriptRoot\scripts\stop_windows_translation.ps1" -TaskName $TaskName -DisableAutostart:$DisableAutostart
