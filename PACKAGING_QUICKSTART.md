# ShareStream Packaging Quick Start

## What You Need to Do

### Step 1: Install Prerequisites

1. **Install MSYS2** (if not already installed)
   - Download: https://www.msys2.org/
   - Run installer
   - Open "MSYS2 UCRT64" terminal
   - Run: `pacman -S mingw-w64-ucrt-x86_64-gcc`

2. **Install Inno Setup** (for creating .exe installer)
   - Download: https://jrsoftware.org/isdl.php
   - Run installer

### Step 2: Build the Package

Open PowerShell in your project folder and run:

```powershell
.\build_installer.ps1 -Version "1.0.0"
```

This will:
- Build the Flutter app
- Build the Go engine
- Copy all required MinGW DLLs
- Create an installer (.exe)
- Create a portable ZIP

### Step 3: Distribute

Find your files in the `dist\` folder:
- `ShareStream-Setup-1.0.0.exe` - Give this to users for installation
- `ShareStream-Portable-1.0.0.zip` - For users who want portable version

## How It Works

The script automatically:
1. Finds your MinGW installation
2. Builds the Go engine with CGO
3. Builds the Flutter app
4. Downloads `cloudflared.exe` (for tunnel URLs)
5. **Copies these DLLs** next to the engine:
   - `libstdc++-6.dll` (C++ standard library)
   - `libgcc_s_seh-1.dll` (GCC runtime)
   - `libwinpthread-1.dll` (POSIX threads)
   - `cloudflared.exe` (Cloudflare tunnel)
5. Creates installer that includes everything

## For End Users

After you distribute the installer:

1. User downloads `ShareStream-Setup-1.0.0.exe`
2. Double-clicks to run installer
3. Clicks "Next" a few times
4. **No need to install MinGW or anything else!**
5. ShareStream works immediately

## Troubleshooting

**Error: "MinGW not found"**
→ Install MSYS2 and GCC as shown in Step 1

**Error: "Inno Setup not found"**
→ Download and install Inno Setup 6

**Missing DLLs in output**
→ Run `fix_dll.ps1` first to verify DLLs can be found

## Files Created for You

| File | Purpose |
|------|---------|
| `build_installer.ps1` | Main build script (now includes cloudflared) |
| `installer.iss` | Inno Setup configuration |
| `fix_dll.ps1` | Fix DLL issues |
| `docs/PACKAGING.md` | Detailed packaging documentation |
| `docs/MINGW_SETUP.md` | MinGW installation guide |

## Need Help?

See full documentation:
- `docs/PACKAGING.md` - Complete packaging guide
- `docs/MINGW_SETUP.md` - MinGW troubleshooting
- `docs/TROUBLESHOOTING.md` - General issues
