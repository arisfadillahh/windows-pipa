@echo off
setlocal
if not exist C:\woa\spi-kona-run mkdir C:\woa\spi-kona-run
echo [%DATE% %TIME%] RunOnce dump SPI status trigger>>C:\woa\spi-kona-run\dump-startup.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\woa\dump-spi-status.ps1 >>C:\woa\spi-kona-run\dump-startup.log 2>&1
echo [%DATE% %TIME%] RunOnce dump SPI status returned %ERRORLEVEL%>>C:\woa\spi-kona-run\dump-startup.log
endlocal

