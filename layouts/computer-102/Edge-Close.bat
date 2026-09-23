@echo off
set "PIDFILE=%~dp0edge-layout.pids"
if not exist "%PIDFILE%" exit /b 0
for /f %%I in (%PIDFILE%) do taskkill /PID %%I /T /F >nul 2>&1
del "%PIDFILE%" >nul 2>&1
