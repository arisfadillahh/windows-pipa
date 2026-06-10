@echo off
setlocal
set SCRIPT=C:\woa\i2c-trace-v1\run-i2c-trace-v1.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
endlocal

