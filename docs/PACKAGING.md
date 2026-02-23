# ShareStream Windows Packaging Guide

Complete guide for packaging ShareStream with all dependencies for Windows distribution.

## Quick Start

```powershell
# Build everything (installer + portable)
.\build_installer.ps1

# Build specific version
.\build_installer.ps1 -Version "1.2.0"
```

## Distribution Methods

| Method | Best For | File |
|--------|----------|------|
| **Installer (.exe)** | Most users | `ShareStream-Setup-1.0.0.exe` |
| **Portable ZIP** | Tech users | `ShareStream-Portable-1.0.0.zip` |
| **MSIX** | Windows Store | `ShareStream.msix` |

## What Gets Bundled

The build script automatically includes:

### Required Files
- `sharestream.exe` - Flutter application
- `sharestream-engine.exe` - P2P torrent engine
- `cloudflared.exe` - Cloudflare tunnel client
- `libstdc++-6.dll` - MinGW C++ runtime
- `libgcc_s_seh-1.dll` - MinGW GCC runtime
- `libwinpthread-1.dll` - MinGW pthread runtime

### Optional Files
- `sharestream-signal.exe` - Local signaling server
- `data/` - Engine data directory
- `.env.example` - Configuration template

## Building the Installer

### Prerequisites

1. **Inno Setup 6** - Download from https://jrsoftware.org/isdl.php
2. **MinGW** - Must be installed (see MINGW_SETUP.md)
3. **PowerShell 5.1+**

### Build Steps

1. Run the build script:
```powershell
.\build_installer.ps1 -Version "1.0.0"
```

2. Output files will be in `dist/`:
   - `ShareStream-Setup-1.0.0.exe` - Windows installer
   - `ShareStream-Portable-1.0.0.zip` - Portable version

### What the Installer Does

1. Installs to `C:\Program Files\ShareStream\`
2. Creates Start Menu shortcuts
3. Optionally creates Desktop shortcut
4. Adds uninstall entry in Control Panel
5. Includes all MinGW DLLs (no separate installation needed)

## Portable Version

The portable ZIP contains everything needed to run without installation:

```
ShareStream-Portable-1.0.0.zip
├── sharestream.exe
├── sharestream-engine.exe
├── libstdc++-6.dll
├── libgcc_s_seh-1.dll
├── libwinpthread-1.dll
└── data/
```

**Usage:**
1. Extract ZIP to any folder
2. Run `sharestream.exe`
3. No installation, no admin rights needed

## Customizing the Installer

Edit `installer.iss` to customize:

```pascal
#define AppName "ShareStream"
#define AppPublisher "Your Company"
#define AppURL "https://yoursite.com"
```

### Adding File Associations

```pascal
[Registry]
Root: HKA; Subkey: "Software\Classes\.sharestream"; ValueData: "ShareStream.Document"
Root: HKA; Subkey: "Software\Classes\ShareStream.Document\shell\open\command"; ValueData: """{app}\sharestream.exe"" ""%1"""
```

## MSIX Packaging (Windows Store)

Create MSIX for Microsoft Store distribution:

1. Build the app:
```powershell
.\build_installer.ps1 -CreateInstaller:$false
```

2. Create AppxManifest.xml (see full docs)

3. Package with MSIX tool:
```powershell
MakeAppx pack /d build\windows_package /p ShareStream.msix
SignTool sign /fd SHA256 /a /f certificate.pfx ShareStream.msix
```

## Automated CI/CD Build

### GitHub Actions Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      
      - uses: msys2/setup-msys2@v2
        with:
          msystem: UCRT64
          install: mingw-w64-ucrt-x86_64-gcc
      
      - name: Build
        shell: pwsh
        run: |
          $env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"
          .\build_installer.ps1 -Version "${{ github.ref_name }}"
      
      - name: Release
        uses: softprops/action-gh-release@v1
        with:
          files: dist/*
```

## Troubleshooting

### "DLL not found" errors

The MinGW DLLs weren't copied. Verify:

```powershell
# Check if MinGW is found
ls C:\msys64\ucrt64\bin\libstdc++-6.dll

# Rebuild with verbose output
.\build_installer.ps1 -Verbose
```

### Engine not found

Ensure `sharestream-engine.exe` is in the same folder as `sharestream.exe`.

### Installer creation fails

Install Inno Setup 6 and restart PowerShell:
https://jrsoftware.org/isdl.php

## Code Signing (Optional but Recommended)

Signed installers show "Verified Publisher":

```powershell
# Sign the installer
signtool sign /fd SHA256 /a /f cert.pfx /p password dist\ShareStream-Setup-1.0.0.exe

# Verify
signtool verify /pa dist\ShareStream-Setup-1.0.0.exe
```

## Summary Commands

| Task | Command |
|------|---------|
| Build all | `.\build_installer.ps1` |
| Specific version | `.\build_installer.ps1 -Version "1.2.0"` |
| Portable only | `.\build_installer.ps1 -CreateInstaller:$false` |
| Skip Flutter | `.\build_installer.ps1 -BuildFlutter:$false` |
