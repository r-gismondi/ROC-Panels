@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-Edge.ps1" -Preset DualFocus3
if errorlevel 1 pause
