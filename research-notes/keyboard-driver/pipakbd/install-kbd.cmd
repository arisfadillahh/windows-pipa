@echo off
REM Installs the pipa keyboard driver (test cert + driver) on the running v31 Windows.
REM Run from C:\woa\pipakbd\ . Self-elevates.
powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\woa\pipakbd\install-kbd.ps1'"
echo Klik Yes di UAC. Tunggu Notepad (install-kbd-log). Lalu RESTART Windows sekali, colok keyboard, tes ketik.
