@echo off
set "PIDFILE=%~dp0panel1-layout.pid"
if not exist "%PIDFILE%" exit /b 0
for /f %%I in (%PIDFILE%) do taskkill /PID %%I /F >nul 2>&1
del "%PIDFILE%" >nul 2>&1
