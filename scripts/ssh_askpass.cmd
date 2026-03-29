@echo off
setlocal enabledelayedexpansion
if not defined SSH_PASSWD exit /b 1
echo %SSH_PASSWD%