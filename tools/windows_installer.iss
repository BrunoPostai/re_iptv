; Windows installer for REIPTV. Build it with tools/build_windows_installer.ps1,
; which reads the version out of app/pubspec.yaml and hands it to this script as
; /DAppVersion - do not run ISCC on this file by hand unless you pass that.
;
; The AppId below is the installer's identity: keep it identical for every
; release so a new setup.exe upgrades an older install instead of sitting beside
; it. Change it and every copy on every machine becomes a separate application.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{3161D3B2-8996-4C15-957E-EF822CF048AF}
AppName=REIPTV
AppVersion={#AppVersion}
AppVerName=REIPTV {#AppVersion}
AppPublisher=REIPTV
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\REIPTV
DefaultGroupName=REIPTV
DisableProgramGroupPage=yes
; A per-user install by default - no UAC prompt, no administrator needed.
; The overrides let someone install for all users if they want to.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Flutter's Windows runner is x64 only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=re_iptv-{#AppVersion}-windows-x64-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\re_iptv.exe
LicenseFile=..\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs
; Microsoft's runtime, only unpacked on machines that have never had it: the
; Flutter runner links against the C++ runtime dynamically, so without it the
; app dies on start with "VCRUNTIME140.dll was not found".
Source: "..\dist\cache\VC_redist.x64.exe"; DestDir: "{tmp}"; \
    Flags: deleteafterinstall; Check: NeedsVCRuntime

[Icons]
Name: "{autoprograms}\REIPTV"; Filename: "{app}\re_iptv.exe"
Name: "{autodesktop}\REIPTV"; Filename: "{app}\re_iptv.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing the Microsoft C++ runtime..."; \
    Flags: waituntilterminated; Check: NeedsVCRuntime
Filename: "{app}\re_iptv.exe"; Description: "{cm:LaunchProgram,REIPTV}"; \
    Flags: nowait postinstall skipifsilent

[Code]
{ True when the 2015-2022 redistributable is not installed. Any version will do:
  a newer runtime is backwards compatible, and this file ships with all of them. }
function NeedsVCRuntime: Boolean;
begin
  Result := not FileExists(ExpandConstant('{sys}\msvcp140.dll'));
end;
