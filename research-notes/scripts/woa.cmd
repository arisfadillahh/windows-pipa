@echo off
setlocal
set SCRIPT=C:\woa\woa-fix.ps1

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo Requesting administrator permission...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/d /c ""%~f0""' -Verb RunAs"
  exit /b 0
)

if not exist "%SCRIPT%" (
  echo Missing %SCRIPT%
  echo This command must be installed from the PC side first.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%

