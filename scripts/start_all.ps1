param(
  [Parameter(Mandatory=$true)][string]$VpsHost,
  [Parameter(Mandatory=$true)][string]$VpsUser,
  [int]$RemotePort = 19191,
  [string]$RemoteBindAddress = "127.0.0.1",
  [int]$LocalPort = 8008,
  [string]$SshKeyPath = "$HOME\.ssh\farmspot_vps_ed25519"
)

$powershellExe = Join-Path $PSHOME 'powershell.exe'
$cwd = (Get-Location).Path

Start-Process -FilePath cmd.exe -ArgumentList @('/c','start','"farmspot service"',$powershellExe,'-NoLogo','-NoExit','-ExecutionPolicy','Bypass','-File','scripts\start_service.ps1') -WorkingDirectory $cwd
Start-Sleep -Seconds 4
Start-Process -FilePath cmd.exe -ArgumentList @('/c','start','"farmspot tunnel"',$powershellExe,'-NoLogo','-NoExit','-ExecutionPolicy','Bypass','-File','scripts\start_tunnel.ps1','-VpsHost',$VpsHost,'-VpsUser',$VpsUser,'-RemotePort',$RemotePort,'-RemoteBindAddress',$RemoteBindAddress,'-LocalPort',$LocalPort,'-SshKeyPath',$SshKeyPath) -WorkingDirectory $cwd

Write-Host "Started service and tunnel in separate PowerShell windows."
