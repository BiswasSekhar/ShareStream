# ShareStream Windows Build & Package Script
# This script builds the application and creates an installer with all dependencies

param(
    [switch]$BuildEngine = $true,
    [switch]$BuildFlutter = $true,
    [switch]$CreateInstaller = $true,
    [switch]$Portable = $false,
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"

Write-Host "=== ShareStream Windows Build Script ===" -ForegroundColor Cyan
Write-Host "Version: $Version" -ForegroundColor White

# Paths
$ProjectRoot = $PSScriptRoot
$EngineDir = "$ProjectRoot\go\sharestream-engine"
$SignalDir = "$ProjectRoot\go\sharestream-signal"
$BuildDir = "$ProjectRoot\build\windows_package"
$OutputDir = "$ProjectRoot\dist"

# Find MinGW
$MingwPaths = @(
    "C:\msys64\ucrt64\bin",
    "C:\msys64\mingw64\bin",
    "C:\mingw64\bin",
    "C:\mingw\bin"
)

$MingwBin = $null
foreach ($path in $MingwPaths) {
    if (Test-Path "$path\gcc.exe") {
        $MingwBin = $path
        Write-Host "Found MinGW at: $path" -ForegroundColor Green
        break
    }
}

if (-not $MingwBin) {
    Write-Host "ERROR: MinGW not found! Install MSYS2 or MinGW-w64 first." -ForegroundColor Red
    exit 1
}

# Create directories
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# ============================================
# Step 1: Build Engine
# ============================================
if ($BuildEngine) {
    Write-Host "" 
    Write-Host "=== Building ShareStream Engine ===" -ForegroundColor Cyan
    
    Set-Location $EngineDir
    
    # Clean previous builds
    Remove-Item -Path "sharestream-engine.exe" -ErrorAction SilentlyContinue
    
    # Build with static flags where possible
    $env:CGO_ENABLED = "1"
    $env:CC = "$MingwBin\gcc.exe"
    $env:CXX = "$MingwBin\g++.exe"
    
    Write-Host "Building engine..." -ForegroundColor Yellow
    go build -ldflags="-s -w" -o sharestream-engine.exe ./cmd
    
    if (-not (Test-Path "sharestream-engine.exe")) {
        Write-Host "ERROR: Engine build failed!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Engine built successfully!" -ForegroundColor Green
    
    # Copy to build directory
    Copy-Item "sharestream-engine.exe" "$BuildDir\" -Force
    
    # Copy required MinGW DLLs
    Write-Host "Copying MinGW runtime DLLs..." -ForegroundColor Yellow
    $RequiredDlls = @(
        "libstdc++-6.dll",
        "libgcc_s_seh-1.dll",
        "libwinpthread-1.dll"
    )
    
    foreach ($dll in $RequiredDlls) {
        $dllPath = "$MingwBin\$dll"
        if (Test-Path $dllPath) {
            Copy-Item $dllPath "$BuildDir\" -Force
            Write-Host "  [OK] $dll" -ForegroundColor Green
        } else {
            Write-Host "  [MISSING] $dll" -ForegroundColor Yellow
        }
    }
    
    Set-Location $ProjectRoot
}

# ============================================
# Step 2: Build Signal Server
# ============================================
if ($BuildEngine) {
    Write-Host "" 
    Write-Host "=== Building ShareStream Signal ===" -ForegroundColor Cyan
    
    Set-Location $SignalDir
    
    # Clean and build
    Remove-Item -Path "sharestream-signal.exe" -ErrorAction SilentlyContinue
    
    Write-Host "Building signal server..." -ForegroundColor Yellow
    go build -ldflags="-s -w" -o sharestream-signal.exe ./cmd
    
    if (Test-Path "sharestream-signal.exe") {
        Copy-Item "sharestream-signal.exe" "$BuildDir\" -Force
        Write-Host "Signal server built successfully!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Signal server build failed (optional)" -ForegroundColor Yellow
    }
    
    Set-Location $ProjectRoot
}

# ============================================
# Step 3: Build Flutter App
# ============================================
if ($BuildFlutter) {
    Write-Host "" 
    Write-Host "=== Building Flutter App ===" -ForegroundColor Cyan
    
    # Clean previous build
    flutter clean
    flutter pub get
    
    Write-Host "Building Windows release..." -ForegroundColor Yellow
    flutter build windows --release
    
    $flutterBuildDir = "build\windows\x64\runner\Release"
    if (-not (Test-Path $flutterBuildDir)) {
        Write-Host "ERROR: Flutter build failed!" -ForegroundColor Red
        exit 1
    }
    
    # Copy Flutter build to package directory
    Write-Host "Copying Flutter app files..." -ForegroundColor Yellow
    Copy-Item "$flutterBuildDir\*" "$BuildDir\" -Recurse -Force
    
    Write-Host "Flutter app built successfully!" -ForegroundColor Green
}

# ============================================
# Step 4: Download Cloudflared
# ============================================
Write-Host "" 
Write-Host "=== Downloading Cloudflared ===" -ForegroundColor Cyan

$cloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$cloudflaredPath = "$BuildDir\cloudflared.exe"

try {
    Write-Host "Downloading cloudflared from GitHub..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $cloudflaredUrl -OutFile $cloudflaredPath -UseBasicParsing
    
    if (Test-Path $cloudflaredPath) {
        $fileSize = (Get-Item $cloudflaredPath).Length / 1MB
        Write-Host "Downloaded cloudflared.exe ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Failed to download cloudflared" -ForegroundColor Yellow
    }
} catch {
    Write-Host "WARNING: Could not download cloudflared: $_" -ForegroundColor Yellow
    Write-Host "The signal server will try to download it on first run." -ForegroundColor Yellow
}

# ============================================
# Step 5: Additional Files
# ============================================
Write-Host "" 
Write-Host "=== Packaging Additional Files ===" -ForegroundColor Cyan

# Create data directory for engine
New-Item -ItemType Directory -Force -Path "$BuildDir\data" | Out-Null

# Copy README
if (Test-Path "README.md") {
    Copy-Item "README.md" "$BuildDir\" -Force
}

# Create .env template
$envTemplate = @"# ShareStream Configuration
# Server URL (use localhost for local server, or your cloud URL)
SERVER_URL=http://localhost:3001

# Optional: TURN server for WebRTC
# TURN_URL=turn:your-turn-server.com:3478
# TURN_USERNAME=your_username
# TURN_CREDENTIAL=your_password
"@
$envTemplate | Out-File -FilePath "$BuildDir\.env.example" -Encoding UTF8

# ============================================
# Step 6: Create Installer
# ============================================
if ($CreateInstaller) {
    Write-Host "" 
    Write-Host "=== Creating Installer ===" -ForegroundColor Cyan
    
    # Check for Inno Setup
    $InnoSetupPath = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $InnoSetupPath)) {
        $InnoSetupPath = "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    }
    
    if (Test-Path $InnoSetupPath) {
        Write-Host "Building installer with Inno Setup..." -ForegroundColor Yellow
        & $InnoSetupPath "/DAppVersion=$Version" "installer.iss"
        
        if (Test-Path "$OutputDir\ShareStream-Setup-$Version.exe") {
            Write-Host "Installer created successfully!" -ForegroundColor Green
            Write-Host "Location: $OutputDir\ShareStream-Setup-$Version.exe" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Inno Setup not found. Skipping installer creation." -ForegroundColor Yellow
        Write-Host "Download Inno Setup from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    }
    
    # Create portable ZIP
    Write-Host "Creating portable ZIP archive..." -ForegroundColor Yellow
    $zipPath = "$OutputDir\ShareStream-Portable-$Version.zip"
    
    # Remove old zip if exists
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    # Create zip using Compress-Archive
    Compress-Archive -Path "$BuildDir\*" -DestinationPath $zipPath -Force
    
    Write-Host "Portable ZIP created!" -ForegroundColor Green
    Write-Host "Location: $zipPath" -ForegroundColor Cyan
}

# ============================================
# Summary
# ============================================
Write-Host "" 
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "Output directory: $OutputDir" -ForegroundColor White
Write-Host "" 

Get-ChildItem $OutputDir | ForEach-Object {
    Write-Host "  - $($_.Name) ($([math]::Round($_.Length/1MB, 2)) MB)" -ForegroundColor Gray
}

Write-Host "" 
Write-Host "Bundled Components:" -ForegroundColor White
Write-Host "  - ShareStream App (Flutter)" -ForegroundColor Gray
Write-Host "  - ShareStream Engine (Go + BitTorrent)" -ForegroundColor Gray
Write-Host "  - ShareStream Signal (Go + Socket.IO)" -ForegroundColor Gray
Write-Host "  - Cloudflared (for tunnel URLs)" -ForegroundColor Gray
Write-Host "  - MinGW Runtime DLLs" -ForegroundColor Gray
Write-Host "" 
Write-Host "To install ShareStream:" -ForegroundColor Cyan
Write-Host "  1. Run ShareStream-Setup-$Version.exe for normal installation" -ForegroundColor White
Write-Host "  2. Or extract ShareStream-Portable-$Version.zip for portable use" -ForegroundColor White
Write-Host "" 
Write-Host "Note: Cloudflared is included for automatic tunnel URLs." -ForegroundColor DarkGray
