#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#define MyAppName "IEM Driver"
#define MyAppPublisher "IEM Driver"
#define MyAppExeName "iem_driver.exe"
#define MyAppReleaseDir "..\app\build\windows\x64\runner\Release"

#if FileExists(AddBackslash(SourcePath) + MyAppReleaseDir + "\" + MyAppExeName) == 0
  #error "Windows Release output is missing. Run 'flutter build windows --release' from app/ before compiling this installer."
#endif

[Setup]
AppId={{37D98D9A-7541-4ED4-AB46-76337A3C8E7E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/aantiosaputra11-glitch/Driver-Sound-HRB
AppSupportURL=https://github.com/aantiosaputra11-glitch/Driver-Sound-HRB/issues
AppUpdatesURL=https://github.com/aantiosaputra11-glitch/Driver-Sound-HRB/releases
DefaultDirName={autopf}\IEM Driver
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
OutputDir=..\dist
OutputBaseFilename=IEM-Driver-Setup-v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#MyAppReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  ApoInstallDir: string;
  ApoInstallDir32: string;
begin
  ApoInstallDir := ExpandConstant('{autopf}\EqualizerAPO');
  ApoInstallDir32 := ExpandConstant('{autopf32}\EqualizerAPO');
  if not DirExists(ApoInstallDir) and not DirExists(ApoInstallDir32) then
    MsgBox('Equalizer APO was not found in its default installation folders. IEM Driver can still run, but Windows system-wide EQ requires Equalizer APO to be installed and configured for the active playback device.', mbInformation, MB_OK);
  Result := True;
end;
