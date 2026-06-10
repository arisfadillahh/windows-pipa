@echo off
setlocal
set SCRIPT=C:\woa\install-drivers.ps1

if not exist "%SCRIPT%" (
  echo Missing %SCRIPT%
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -DriverRoot "C:\woa\drivers" -Mode allow
exit /b %ERRORLEVEL%

