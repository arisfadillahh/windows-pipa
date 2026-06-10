@echo off
setlocal
set LOGDIR=C:\woa\resource-dump
set STARTUP=%ProgramData%\Microsoft\Windows\Start Menu\Programs\StartUp\PipaAutoDumpOnce.cmd
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo === Pipa auto dump once start %date% %time% === > "%LOGDIR%\AUTO-DUMP-STARTED.txt"
call C:\woa\pipa-resource-dump\run-resource-dump.cmd >> "%LOGDIR%\AUTO-DUMP-STARTED.txt" 2>&1
echo === Pipa auto dump once end %date% %time% === >> "%LOGDIR%\AUTO-DUMP-STARTED.txt"
del "%STARTUP%" >nul 2>nul
exit /b 0

