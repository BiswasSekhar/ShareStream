@echo off
setlocal enabledelayedexpansion

:: ShareStream Windows Launcher
:: Usage: run.bat [--no-tunnel] [--build-go]

echo [=== ShareStream Launcher ===]

:: Parse arguments
set BUILD_GO=false
set NO_TUNNEL=false
set SERVER_ARGS=

:parse_args
if "%~1"=="" goto :done_parsing
if "%~1"=="--build-go" set BUILD_GO=true
if "%~1"=="--no-tunnel" (
    set NO_TUNNEL=true
    set SERVER_ARGS=--no-tunnel
)
shift
goto :parse_args
:done_parsing

echo [Detected: Windows]

:: Check for Go
where go >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Go is not installed or not in PATH
    exit /b 1
)

:: Check for Flutter
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter is not installed or not in PATH
    exit /b 1
)

set GO_DIR=go\sharestream-signal
set GO_SOURCE=%GO_DIR%\cmd\main.go
set GO_OUTPUT=%GO_DIR%\sharestream-signal.exe

:: Check if Go server needs building
set NEEDS_BUILD=false
if "%BUILD_GO%"=="true" set NEEDS_BUILD=true
if not exist "%GO_OUTPUT%" set NEEDS_BUILD=true

:: Check if source is newer than binary (requires PowerShell)
if exist "%GO_OUTPUT%" (
    powershell -Command "if ((Get-Item '%GO_SOURCE%').LastWriteTime -gt (Get-Item '%GO_OUTPUT%').LastWriteTime) { exit 1 }" 2>nul
    if errorlevel 1 set NEEDS_BUILD=true
)

if "%NEEDS_BUILD%"=="true" (
    echo [Building Go signal server...]
    cd "%GO_DIR%"
    go mod tidy
    if errorlevel 1 (
        echo [ERROR] go mod tidy failed
        cd ..\..
        exit /b 1
    )
    go build -o sharestream-signal.exe ./cmd/main.go
    if errorlevel 1 (
        echo [ERROR] go build failed
        cd ..\..
        exit /b 1
    )
    cd ..\..
    echo [OK] Go server built
) else (
    echo [OK] Go server is up to date
)

:: Get Flutter dependencies
echo [Fetching Flutter dependencies...]
flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get failed
    exit /b 1
)

:: Start Go server in background
echo [Starting signal server...]
if "%NO_TUNNEL%"=="true" (
    echo [Tunnel disabled - local only]
)

start /B "" "%GO_OUTPUT%" %SERVER_ARGS%
set SERVER_PID=%ERRORLEVEL%

:: Wait for server
echo [Waiting for server...]
timeout /t 2 /nobreak >nul

:: Check if server is running
tasklist | findstr sharestream-signal >nul
if errorlevel 1 (
    echo [ERROR] Server failed to start
    exit /b 1
)

echo [OK] Server running

:: Run Flutter app
echo [Starting Flutter app on Windows...]
echo [Press Ctrl+C to stop]
echo.

flutter run -d windows %*

:: Cleanup
echo [Cleaning up...]
taskkill /F /IM sharestream-signal.exe >nul 2>&1
echo [Server stopped]

endlocal
