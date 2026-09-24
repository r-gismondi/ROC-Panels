@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-Layout.ps1" -Preset Focus
if errorlevel 1 pause
