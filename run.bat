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

:: ── Build Signal Server ──────────────────────────────────────────────────────
set GO_SIGNAL_DIR=go\sharestream-signal
set GO_SIGNAL_EXE=%GO_SIGNAL_DIR%\sharestream-signal.exe
set GO_SIGNAL_SRC=%GO_SIGNAL_DIR%\cmd\main.go

set NEEDS_SIGNAL_BUILD=false
if "%BUILD_GO%"=="true" set NEEDS_SIGNAL_BUILD=true
if not exist "%GO_SIGNAL_EXE%" set NEEDS_SIGNAL_BUILD=true
if exist "%GO_SIGNAL_EXE%" (
    powershell -Command "if ((Get-Item '%GO_SIGNAL_SRC%').LastWriteTime -gt (Get-Item '%GO_SIGNAL_EXE%').LastWriteTime) { exit 1 }" 2>nul
    if errorlevel 1 set NEEDS_SIGNAL_BUILD=true
)

if "%NEEDS_SIGNAL_BUILD%"=="true" (
    echo [Building Go signal server...]
    call :build_go_project "%GO_SIGNAL_DIR%" "sharestream-signal.exe"
    if errorlevel 1 exit /b 1
    echo [OK] Go signal server built
) else (
    echo [OK] Go signal server is up to date
)

:: ── Build Torrent Engine ─────────────────────────────────────────────────────
set GO_ENGINE_DIR=go\sharestream-engine
set GO_ENGINE_EXE=%GO_ENGINE_DIR%\sharestream-engine.exe
set GO_ENGINE_SRC=%GO_ENGINE_DIR%\cmd\main.go

set NEEDS_ENGINE_BUILD=false
if "%BUILD_GO%"=="true" set NEEDS_ENGINE_BUILD=true
if not exist "%GO_ENGINE_EXE%" set NEEDS_ENGINE_BUILD=true
if exist "%GO_ENGINE_EXE%" (
    powershell -Command "if ((Get-Item '%GO_ENGINE_SRC%').LastWriteTime -gt (Get-Item '%GO_ENGINE_EXE%').LastWriteTime) { exit 1 }" 2>nul
    if errorlevel 1 set NEEDS_ENGINE_BUILD=true
)

if "%NEEDS_ENGINE_BUILD%"=="true" (
    echo [Building Go torrent engine...]
    call :build_go_project "%GO_ENGINE_DIR%" "sharestream-engine.exe"
    if errorlevel 1 exit /b 1
    echo [OK] Go torrent engine built
) else (
    echo [OK] Go torrent engine is up to date
)

:: ── Flutter Dependencies ─────────────────────────────────────────────────────
echo [Fetching Flutter dependencies...]
flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get failed
    exit /b 1
)

:: ── Start Signal Server ──────────────────────────────────────────────────────
echo [Starting signal server...]
if "%NO_TUNNEL%"=="true" echo [Tunnel disabled - local only]

start /B "" "%GO_SIGNAL_EXE%" %SERVER_ARGS%

:: Wait for server
echo [Waiting for server...]
timeout /t 2 /nobreak >nul

tasklist | findstr sharestream-signal >nul
if errorlevel 1 (
    echo [ERROR] Server failed to start
    exit /b 1
)

echo [OK] Server running

:: ── Run Flutter App ──────────────────────────────────────────────────────────
echo [Starting Flutter app on Windows...]
echo [Press Ctrl+C to stop]
echo.

flutter run -d windows %*

:: Cleanup
echo [Cleaning up...]
taskkill /F /IM sharestream-signal.exe >nul 2>&1
echo [Done]

endlocal
goto :eof

:: ── Subroutine: build_go_project ─────────────────────────────────────────────
:: Usage: call :build_go_project <dir> <output.exe>
:build_go_project
pushd "%~1"
go mod tidy
if errorlevel 1 (
    echo [ERROR] go mod tidy failed in %~1
    popd
    exit /b 1
)
go build -o "%~2" ./cmd/main.go
if errorlevel 1 (
    echo [ERROR] go build failed in %~1
    popd
    exit /b 1
)
popd
exit /b 0
