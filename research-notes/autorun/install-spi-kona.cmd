@echo off
setlocal
title Codex SPI Kona Admin Launcher
if not exist C:\woa\spi-kona-run mkdir C:\woa\spi-kona-run
echo [%DATE% %TIME%] Startup SPI Kona trigger>>C:\woa\spi-kona-run\startup.log
echo.
echo Codex SPI Kona installer
echo.
echo This window is intentionally visible.
echo Wait 30 seconds, then Windows should ask for admin permission.
echo If UAC appears, press Alt+Y or select Yes.
echo.
timeout /t 30 /nobreak

:retry
echo [%DATE% %TIME%] Requesting UAC>>C:\woa\spi-kona-run\startup.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File C:\woa\install-spi-kona.ps1'" >>C:\woa\spi-kona-run\startup.log 2>&1
echo.
echo If nothing happened, press R to request UAC again.
echo Press Q to quit this launcher.
choice /c RQ /n /m "Retry or quit? [R/Q] "
if errorlevel 2 goto end
goto retry

:end
echo [%DATE% %TIME%] Startup SPI Kona launcher quit>>C:\woa\spi-kona-run\startup.log
endlocal

