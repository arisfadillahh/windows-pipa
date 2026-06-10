@echo off
set ROOT=C:\woa\kbd-i2c-dump
if exist "%ROOT%\DONE.txt" exit /b 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ROOT%\pipa-i2c-keyboard-dump.ps1"

