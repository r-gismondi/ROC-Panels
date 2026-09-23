@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-Edge.ps1" -Preset DualFocus2
if errorlevel 1 pause
