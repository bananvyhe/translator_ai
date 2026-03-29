@echo off
setlocal

set "ROOT=%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%stop_visible_translation.ps1"

endlocal
