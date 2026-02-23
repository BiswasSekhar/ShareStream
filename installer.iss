; ShareStream Windows Installer Script
; Requires Inno Setup 6: https://jrsoftware.org/isdl.php

#define AppName "ShareStream"
#define AppPublisher "ShareStream Team"
#define AppURL "https://github.com/yourusername/sharestream"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{12345678-1234-1234-1234-123456789012}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=ShareStream-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=assets\icon\app_icon.ico
UninstallDisplayIcon={app}\sharestream.exe
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode

[Files]
; Main application files from build directory
Source: "build\windows_package\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

; Ensure cloudflared is included
Source: "build\windows_package\cloudflared.exe"; DestDir: "{app}"; Flags: ignoreversion

; Visual C++ Redistributable (optional but recommended)
; Source: "vc_redist.x64.exe"; DestDir: {tmp}; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\sharestream.exe"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\sharestream.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\sharestream.exe"; Tasks: quicklaunchicon; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode

[Run]
Filename: "{app}\sharestream.exe"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Dirs]
Name: "{app}\data"; Permissions: users-modify
Name: "{localappdata}\ShareStream"; Permissions: users-modify

[Registry]
; Register .sharestream file extension (optional)
; Root: HKA; Subkey: "Software\Classes\.sharestream"; ValueType: string; ValueName: ""; ValueData: "ShareStream.Document"; Flags: uninsdeletevalue
; Root: HKA; Subkey: "Software\Classes\ShareStream.Document"; ValueType: string; ValueName: ""; ValueData: "ShareStream Room Link"; Flags: uninsdeletekey
; Root: HKA; Subkey: "Software\Classes\ShareStream.Document\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\sharestream.exe,0"
; Root: HKA; Subkey: "Software\Classes\ShareStream.Document\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\sharestream.exe"" ""%1"""

[Code]
function InitializeSetup(): Boolean;
begin
  Result := true;
  
  ; Check for Windows 10 or later (recommended)
  if not IsWindows10OrGreater() then begin
    MsgBox('Warning: ShareStream is designed for Windows 10 or later. Older versions may not work correctly.', mbWarning, MB_OK);
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := true;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    ; Post-install steps
    Log('ShareStream installation completed');
  end;
end;
