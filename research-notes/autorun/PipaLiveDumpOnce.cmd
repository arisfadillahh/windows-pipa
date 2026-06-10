@echo off
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\woa\v19-live-dump\live-v19-dump.ps1
ping 127.0.0.1 -n 6 >nul
del "%~f0" >nul 2>nul
exit /b 0

