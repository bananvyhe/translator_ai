param(
  [Parameter(Mandatory=$true)][string]$VpsHost,
  [Parameter(Mandatory=$true)][string]$VpsUser,
  [int]$RemotePort = 19191,
  [string]$RemoteBindAddress = "127.0.0.1",
  [int]$LocalPort = 8008,
  [string]$SshKeyPath = "$HOME\.ssh\farmspot_vps_ed25519",
  [string]$TaskName = "farmspot-translation"
)

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Get-Location) 'scripts\run_windows_translation.ps1'
if (-not (Test-Path $scriptPath)) {
  throw "Launcher not found: $scriptPath"
}

$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -VpsHost `"$VpsHost`" -VpsUser `"$VpsUser`" -RemotePort $RemotePort -RemoteBindAddress $RemoteBindAddress -LocalPort $LocalPort -SshKeyPath `"$SshKeyPath`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Installed scheduled task '$TaskName'. It will start on logon and relaunch if it exits."





