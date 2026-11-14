#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#define MyAppName "IEM Driver"
#define MyAppPublisher "IEM Driver"
#define MyAppExeName "iem_driver.exe"

[Setup]
AppId={{37D98D9A-7541-4ED4-AB46-76337A3C8E7E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\IEM Driver
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesInstallIn64BitMode=x64
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
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  ApoConfig: string;
begin
  ApoConfig := ExpandConstant('{autopf}\EqualizerAPO\config\config.txt');
  if not FileExists(ApoConfig) then
    MsgBox('Equalizer APO was not detected. IEM Driver can still run, but Windows system-wide EQ requires Equalizer APO to be installed and configured for the active playback device.', mbInformation, MB_OK);
  Result := True;
end;
