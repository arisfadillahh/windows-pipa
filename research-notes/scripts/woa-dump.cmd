@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\woa\woa-dump.ps1
exit /b %ERRORLEVEL%

