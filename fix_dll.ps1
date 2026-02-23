# ShareStream DLL Fix Script
# Run this in PowerShell to copy required MinGW DLLs

Write-Host "=== ShareStream DLL Fix Script ===" -ForegroundColor Green

# Check for MSYS2 MinGW
$msysPath = "C:\msys64\ucrt64\bin"
$mingwPath = "C:\mingw64\bin"

$gccPath = $null
if (Test-Path "$msysPath\gcc.exe") {
    $gccPath = $msysPath
    Write-Host "Found MSYS2 MinGW at $msysPath" -ForegroundColor Green
} elseif (Test-Path "$mingwPath\gcc.exe") {
    $gccPath = $mingwPath
    Write-Host "Found MinGW-w64 at $mingwPath" -ForegroundColor Green
} else {
    Write-Host "MinGW not found! Please install MSYS2:" -ForegroundColor Red
    Write-Host "1. Download from https://www.msys2.org/" -ForegroundColor Yellow
    Write-Host "2. Install and run: pacman -S mingw-w64-ucrt-x86_64-gcc" -ForegroundColor Yellow
    Write-Host "" 
    Write-Host "Or download MinGW-w64 from:" -ForegroundColor Yellow
    Write-Host "https://github.com/niXman/mingw-builds-binaries/releases" -ForegroundColor Yellow
    exit 1
}

# Check engine directory
$engineDir = "go\sharestream-engine"
if (-not (Test-Path $engineDir)) {
    Write-Host "Engine directory not found at $engineDir" -ForegroundColor Red
    exit 1
}

# Copy required DLLs
$dlls = @("libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll")
$copied = 0

Write-Host "" 
Write-Host "Copying DLLs..." -ForegroundColor Cyan

foreach ($dll in $dlls) {
    $source = Join-Path $gccPath $dll
    $dest = Join-Path $engineDir $dll
    
    if (Test-Path $source) {
        Copy-Item $source $dest -Force
        Write-Host "  [OK] $dll" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  [MISSING] $dll" -ForegroundColor Yellow
    }
}

Write-Host "" 
if ($copied -gt 0) {
    Write-Host "=== Fix applied successfully! ===" -ForegroundColor Green
    Write-Host "Copied $copied DLL(s) to $engineDir" -ForegroundColor White
    Write-Host "" 
    Write-Host "Now try running: flutter run -d windows" -ForegroundColor Cyan
} else {
    Write-Host "No DLLs were copied. Please check your MinGW installation." -ForegroundColor Red
}

Write-Host "" 
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
