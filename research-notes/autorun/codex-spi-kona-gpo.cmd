@echo off
setlocal
if not exist C:\woa\spi-kona-run mkdir C:\woa\spi-kona-run
echo [%DATE% %TIME%] GPO SYSTEM startup trigger>>C:\woa\spi-kona-run\gpo-startup.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\woa\install-spi-kona.ps1 >>C:\woa\spi-kona-run\gpo-startup.log 2>&1
echo [%DATE% %TIME%] GPO SYSTEM startup returned %ERRORLEVEL%>>C:\woa\spi-kona-run\gpo-startup.log
endlocal

