param(
  [Parameter(Mandatory=$true)][string]$VpsHost,
  [Parameter(Mandatory=$true)][string]$VpsUser,
  [int]$RemotePort = 19191,
  [string]$RemoteBindAddress = "",
  [int]$LocalPort = 8008,
  [string]$SshKeyPath = ""
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
if (-not $PSBoundParameters.ContainsKey('LocalPort')) { $LocalPort = Get-EnvInt -Name 'LOCAL_PORT' -DefaultValue 8008 }
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) { $SshKeyPath = $env:SSH_KEY_PATH }
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) { $SshKeyPath = "$HOME\.ssh\farmspot_vps_ed25519" }

$powershellExe = Join-Path $PSHOME 'powershell.exe'
$cwd = $root

Start-Process -FilePath cmd.exe -ArgumentList @('/c','start','"farmspot service"',$powershellExe,'-NoLogo','-NoExit','-ExecutionPolicy','Bypass','-File','scripts\start_service.ps1') -WorkingDirectory $cwd
Start-Sleep -Seconds 4
Start-Process -FilePath cmd.exe -ArgumentList @('/c','start','"farmspot tunnel"',$powershellExe,'-NoLogo','-NoExit','-ExecutionPolicy','Bypass','-File','scripts\start_tunnel.ps1','-VpsHost',$VpsHost,'-VpsUser',$VpsUser,'-RemotePort',$RemotePort,'-RemoteBindAddress',$RemoteBindAddress,'-LocalPort',$LocalPort,'-SshKeyPath',$SshKeyPath) -WorkingDirectory $cwd

Write-Host "Started translation service on 127.0.0.1:$LocalPort and reverse tunnel to VPS ${RemoteBindAddress}:$RemotePort."
