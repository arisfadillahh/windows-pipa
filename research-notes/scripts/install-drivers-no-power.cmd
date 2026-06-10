@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\woa\install-drivers-no-power.ps1" -DriverRoot "C:\woa\drivers"
pause

