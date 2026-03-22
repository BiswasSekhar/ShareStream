; ShareStream Windows Installer Script
; Requires Inno Setup 6: https://jrsoftware.org/isdl.php

#define AppName "ShareStream"
#define AppPublisher "ShareStream Team"
#define AppURL "https://github.com/yourusername/sharestream"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{12345678-1234-1234-1234-123456789012}
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
UninstallDisplayIcon={app}\sharestream.exe
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; All application files from build directory (recursive)
Source: "build\windows_package\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\launch.bat"; IconFilename: "{app}\sharestream.exe"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\launch.bat"; IconFilename: "{app}\sharestream.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\launch.bat"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec

[Dirs]
Name: "{localappdata}\ShareStream"; Permissions: users-modify
