@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-Edge.ps1" -Preset Independent
if errorlevel 1 pause
