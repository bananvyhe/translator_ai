@echo off
setlocal

set "MINER_BAT_PATH=C:\bbb\onezerominer-win64-1.7.4\qubitcoin.bat"
set "MINER_PROCESS_NAME=onezerominer.exe"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$bat = [regex]::Escape($env:MINER_BAT_PATH); " ^
  + "$cmds = Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'cmd.exe' -and $_.CommandLine -and $_.CommandLine -match $bat }; " ^
  + "foreach ($cmd in $cmds) { & taskkill /PID $cmd.ProcessId /T /F | Out-Null }; " ^
  + "Start-Sleep -Milliseconds 500; " ^
  + "& taskkill /IM $env:MINER_PROCESS_NAME /T /F | Out-Null"

exit /b 0
