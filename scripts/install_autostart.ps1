param(
  [Parameter(Mandatory=$true)][string]$VpsHost,
  [Parameter(Mandatory=$true)][string]$VpsUser,
  [int]$RemotePort = 19191,
  [string]$RemoteBindAddress = "",
  [int]$LocalPort = 8108,
  [string]$SshKeyPath = "",
  [string]$TaskName = "farmspot-translation"
)

$ErrorActionPreference = 'Stop'

function Import-DotEnv {
  param([string]$Path)

  if (-not (Test-Path $Path)) { return }

  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1)
    if (-not [string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
      [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
  }
}

function Get-EnvInt {
  param(
    [string]$Name,
    [int]$DefaultValue
  )

  $raw = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $DefaultValue
  }

  try {
    return [int]$raw
  } catch {
    return $DefaultValue
  }
}

$root = $PSScriptRoot | Split-Path -Parent
Import-DotEnv -Path (Join-Path $root '.env')

if ([string]::IsNullOrWhiteSpace($VpsHost)) { $VpsHost = $env:VPS_HOST }
if ([string]::IsNullOrWhiteSpace($VpsUser)) { $VpsUser = $env:VPS_USER }
if (-not $PSBoundParameters.ContainsKey('RemotePort')) { $RemotePort = Get-EnvInt -Name 'REMOTE_PORT' -DefaultValue 19191 }
if ([string]::IsNullOrWhiteSpace($RemoteBindAddress)) { $RemoteBindAddress = $env:REMOTE_BIND_ADDRESS }
if ([string]::IsNullOrWhiteSpace($RemoteBindAddress)) { $RemoteBindAddress = '127.0.0.1' }
if (-not $PSBoundParameters.ContainsKey('LocalPort')) { $LocalPort = Get-EnvInt -Name 'LOCAL_PORT' -DefaultValue 8108 }
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) { $SshKeyPath = $env:SSH_KEY_PATH }
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) { $SshKeyPath = "$HOME\.ssh\farmspot_vps_ed25519" }

$scriptPath = Join-Path $root 'scripts\run_windows_translation.ps1'
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
