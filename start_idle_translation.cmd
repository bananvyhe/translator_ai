@echo off
setlocal

set "MANAGE_MINER=true"
set "LAZY_MODEL_LOAD=true"
set "UNLOAD_MODEL_AFTER_REQUEST=true"
set "MINER_PROCESS_NAME=onezerominer.exe"
set "MINER_LAUNCH_PATH=C:\cofex\translation\start_onezerominer_wrapper.cmd"

tasklist /FI "IMAGENAME eq onezerominer.exe" | find /I "onezerominer.exe" >nul
if errorlevel 1 (
  if exist "%MINER_LAUNCH_PATH%" (
    start "" "%MINER_LAUNCH_PATH%"
  ) else (
    echo Miner launch path not found: %MINER_LAUNCH_PATH%
  )
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_visible_translation.ps1" -ManageMiner -LazyModelLoad -UnloadModelAfterRequest

endlocal
