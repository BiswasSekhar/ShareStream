@echo off
REM Build script for sharestream-signal (Windows)
REM Usage: build.bat [windows|all]

setlocal

set PROJECT_ROOT=%~dp0
set SIGNAL_DIR=%PROJECT_ROOT%sharestream-signal
set OUTPUT_DIR=%PROJECT_ROOT%bin

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

set GOOS=windows
set GOARCH=amd64

echo Building for %GOOS%/%GOARCH%...

cd /d "%SIGNAL_DIR%"
go build -o "%OUTPUT_DIR%\sharestream-signal-windows-amd64.exe" .\cmd\main.go

if exist "%OUTPUT_DIR%\sharestream-signal-windows-amd64.exe" (
    copy /Y "%OUTPUT_DIR%\sharestream-signal-windows-amd64.exe" "%OUTPUT_DIR%\sharestream-signal.exe"
    echo Build complete!
    dir "%OUTPUT_DIR%"
) else (
    echo Build failed!
    exit /b 1
)
