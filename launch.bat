@echo off
setlocal
title ShareStream
cd /d "%~dp0"

echo [Cleaning up older instances...]
taskkill /F /IM sharestream-signal.exe >nul 2>&1
taskkill /F /IM cloudflared.exe >nul 2>&1
taskkill /F /IM sharestream-engine.exe >nul 2>&1

:: Start the signal server in the background
echo Starting ShareStream Server...
start /B "" sharestream-signal.exe >nul 2>&1

:: Give the server a moment to start
timeout /t 2 /nobreak >nul

:: Launch the app and wait for it to close
echo Starting ShareStream...
start /WAIT "" sharestream.exe

echo [Cleaning up processes...]
taskkill /F /IM sharestream-signal.exe >nul 2>&1
taskkill /F /IM cloudflared.exe >nul 2>&1
taskkill /F /IM sharestream-engine.exe >nul 2>&1

endlocal
