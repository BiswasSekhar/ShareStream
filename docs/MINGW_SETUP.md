# MinGW Setup for ShareStream (Windows)

This guide fixes the "libstdc++-6.dll not found" and related DLL errors on Windows.

## The Problem

When building the Go engine with CGO enabled, it links against MinGW's C++ runtime libraries. These DLLs need to be available at runtime.

## Solution 1: Install MinGW and Add to PATH (Recommended)

### Step 1: Download MinGW

1. Go to https://www.mingw-w64.org/downloads/
2. Download **MSYS2** (recommended) or MingW-W64-builds

### Step 2: Install MSYS2

1. Run the MSYS2 installer
2. Install to `C:\msys64` (default)
3. Complete the installation wizard

### Step 3: Install GCC in MSYS2

Open **MSYS2 UCRT64** terminal (from Start Menu) and run:

```bash
pacman -S mingw-w64-ucrt-x86_64-gcc
```

Type `Y` when prompted to proceed with installation.

### Step 4: Add to PATH

Add this to your Windows PATH environment variable:

```
C:\msys64\ucrt64\bin
```

**How to add to PATH:**
1. Search "Environment Variables" in Windows search
2. Click "Edit the system environment variables"
3. Click "Environment Variables" button
4. Under "System variables", find and edit "Path"
5. Click "New" and add `C:\msys64\ucrt64\bin`
6. Click OK on all dialogs
7. **Restart your terminal/IDE**

### Step 5: Verify Installation

Open a new PowerShell/CMD window and run:

```powershell
gcc --version
```

You should see GCC version information.

## Solution 2: Static Linking (No DLLs Needed)

Build the engine with static linking so it doesn't need external DLLs:

```powershell
cd go/sharestream-engine

# Build with static linking
go build -ldflags="-s -w -extldflags=-static" -o sharestream-engine.exe ./cmd
```

**Note:** Static linking may not work for all CGO dependencies.

## Solution 3: Bundle DLLs with Executable

Copy the required DLLs next to your executable:

### Find Required DLLs

```powershell
# List dependencies
cd go/sharestream-engine

# Use dumpbin (if you have Visual Studio)
dumpbin /dependents sharestream-engine.exe

# Or use ldd from MinGW
C:\msys64\ucrt64\bin\ldd.exe sharestream-engine.exe
```

### Copy DLLs

Common DLLs needed:
- `libstdc++-6.dll`
- `libgcc_s_seh-1.dll`
- `libwinpthread-1.dll`

Copy from `C:\msys64\ucrt64\bin\` to your executable's folder.

## Solution 4: Use Pre-built Engine (No CGO)

If you don't need torrent functionality for testing, you can temporarily disable CGO:

```powershell
cd go/sharestream-engine

# Build without CGO (limited functionality)
$env:CGO_ENABLED="0"
go build -o sharestream-engine.exe ./cmd
```

**Warning:** This disables BitTorrent functionality. Only for testing!

## Quick Fix Script

Save this as `fix-mingw.ps1` and run it as Administrator:

```powershell
# Check if MSYS2 is installed
$msysPath = "C:\msys64\ucrt64\bin"

if (-not (Test-Path $msysPath)) {
    Write-Host "MSYS2 not found at C:\msys64"
    Write-Host "Please install MSYS2 from https://www.msys2.org/"
    exit 1
}

# Check if gcc exists
$gccPath = Join-Path $msysPath "gcc.exe"
if (-not (Test-Path $gccPath)) {
    Write-Host "GCC not found. Please run in MSYS2 terminal:"
    Write-Host "pacman -S mingw-w64-ucrt-x86_64-gcc"
    exit 1
}

# Add to user PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$msysPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$msysPath", "User")
    Write-Host "Added MinGW to PATH. Please restart your terminal."
} else {
    Write-Host "MinGW is already in PATH."
}

# Copy DLLs to engine directory
$engineDir = "go\sharestream-engine"
$dlls = @("libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll")

foreach ($dll in $dlls) {
    $source = Join-Path $msysPath $dll
    $dest = Join-Path $engineDir $dll
    
    if (Test-Path $source) {
        Copy-Item $source $dest -Force
        Write-Host "Copied $dll"
    } else {
        Write-Host "Warning: $dll not found"
    }
}

Write-Host "Done! Try running the engine again."
```

## Verification

After fixing, test the engine:

```powershell
.\go\sharestream-engine\sharestream-engine.exe -http :42069
```

You should see:
```
{"event":"ready","port":42069}
```

Without any DLL errors!

## Common Errors

### "libstdc++-6.dll was not found"
→ Install MinGW and add to PATH, or copy DLLs

### "libgcc_s_seh-1.dll was not found"
→ Same fix as above

### "The code execution cannot proceed"
→ Missing multiple DLLs, use Solution 1 or 3

### "0xc000007b" error
→ 32-bit/64-bit mismatch. Ensure you're using 64-bit MinGW with 64-bit Go.

## Alternative: Use MinGW-w64 without MSYS2

If you prefer not to use MSYS2:

1. Download MinGW-w64 from: https://github.com/niXman/mingw-builds-binaries/releases
2. Choose `x86_64-14.2.0-release-win32-seh-ucrt-rt_v12-rev0.7z`
3. Extract to `C:\mingw64`
4. Add `C:\mingw64\bin` to PATH
5. Restart terminal

## Still Having Issues?

1. Ensure you're using 64-bit everything (Windows, Go, MinGW)
2. Check Go version: `go version` should show `windows/amd64`
3. Try building in a fresh terminal after PATH changes
4. Reboot your computer to ensure PATH changes take effect
