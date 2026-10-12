; One per-user Windows setup. The game updater remains responsible for game files.
#ifndef LauncherPayload
  #define LauncherPayload "..\build\IronSunLauncher.exe"
#endif
#ifndef LauncherVersion
  #define LauncherVersion "1.0.1"
#endif
#ifndef SetupOutput
  #define SetupOutput "..\build\setup"
#endif
#ifdef FixtureRoot
  #define SetupAppId "IRON-SUN-SETUP-FIXTURE"
  #define SetupName "IRON SUN Setup Fixture"
  #define InstallDir FixtureRoot + "\Launcher"
#else
  #define SetupAppId "{{47F9B5B4-36A4-46F6-B87C-1AC30C5CE690}"
  #define SetupName "IRON SUN Launcher"
  #define InstallDir "{localappdata}\IRON SUN\Launcher"
#endif

[Setup]
AppId={#SetupAppId}
AppName={#SetupName}
AppVersion={#LauncherVersion}
AppPublisher=Wilcox-Hub
AppPublisherURL=https://iron-sun-playtest.wilcoxwarrior4577.chatgpt.site
DefaultDirName={#InstallDir}
DisableDirPage=yes
DisableProgramGroupPage=yes
UsePreviousAppDir=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern dynamic
WizardImageFile=
WizardSmallImageFile=
SetupIconFile=..\assets\iron-sun.ico
UninstallDisplayIcon={app}\iron-sun.ico
UninstallDisplayName={#SetupName}
OutputDir={#SetupOutput}
OutputBaseFilename=IRON-SUN-Setup
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
CloseApplicationsFilter=IronSunLauncher.exe
RestartApplications=no
SetupLogging=yes
DisableWelcomePage=no
DisableReadyPage=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "IRON SUN Launcher:";

[Files]
; Respect file versions so an old setup cannot downgrade a self-updated launcher.
Source: "{#LauncherPayload}"; DestDir: "{app}"; DestName: "IronSunLauncher.exe"; Flags: uninsrestartdelete
Source: "..\assets\iron-sun.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
#ifdef FixtureRoot
Name: "{#FixtureRoot}\Shortcuts\Start\IRON SUN Launcher"; Filename: "{app}\IronSunLauncher.exe"; Parameters: "--install-root ""{#FixtureRoot}"" --no-shortcut"; WorkingDir: "{#FixtureRoot}"; IconFilename: "{app}\iron-sun.ico"
Name: "{#FixtureRoot}\Shortcuts\Desktop\IRON SUN Launcher"; Filename: "{app}\IronSunLauncher.exe"; Parameters: "--install-root ""{#FixtureRoot}"" --no-shortcut"; WorkingDir: "{#FixtureRoot}"; IconFilename: "{app}\iron-sun.ico"; Tasks: desktopicon
#else
Name: "{userprograms}\IRON SUN Launcher"; Filename: "{app}\IronSunLauncher.exe"; Parameters: "--no-shortcut"; WorkingDir: "{localappdata}\IRON SUN"; IconFilename: "{app}\iron-sun.ico"
Name: "{userdesktop}\IRON SUN Launcher"; Filename: "{app}\IronSunLauncher.exe"; Parameters: "--no-shortcut"; WorkingDir: "{localappdata}\IRON SUN"; IconFilename: "{app}\iron-sun.ico"; Tasks: desktopicon
#endif

[Run]
#ifdef FixtureRoot
Filename: "{app}\IronSunLauncher.exe"; Parameters: "--install-root ""{#FixtureRoot}"" --no-shortcut"; Description: "Open IRON SUN Launcher"; Flags: nowait postinstall skipifsilent
#else
Filename: "{app}\IronSunLauncher.exe"; Parameters: "--no-shortcut"; Description: "Open IRON SUN Launcher"; Flags: nowait postinstall skipifsilent
#endif

[Messages]
WelcomeLabel2=This installs IRON SUN Launcher for your Windows account.%n%nOpen the launcher to download the game and keep it updated. Setup adds IRON SUN Launcher to your Start menu and can create a desktop shortcut.
FinishedLabel=IRON SUN Launcher is installed.%n%nOpen it to install the game, then press Play. Future game updates are handled by the launcher.

[Code]
function FileAttributes(Path: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function GameRoot: String;
begin
#ifdef FixtureRoot
  Result := ExpandFileName('{#FixtureRoot}');
#else
  Result := ExpandConstant('{localappdata}\IRON SUN');
#endif
end;

function PlainPath(Path: String): Boolean;
var Parent: String;
begin
  Result := False;
  while Path <> '' do begin
    if (FileAttributes(Path) <> $FFFFFFFF) and ((FileAttributes(Path) and $400) <> 0) then Exit;
    Parent := ExtractFileDir(Path);
    if Parent = Path then Break;
    Path := Parent;
  end;
  Result := True;
end;

procedure SkipSpace(const S: String; var P: Integer);
begin
  while P <= Length(S) do begin
    if (S[P] <> ' ') and (S[P] <> #9) and (S[P] <> #13) and (S[P] <> #10) then Break;
    P := P + 1;
  end;
end;

function Consume(const S: String; var P: Integer; C: Char): Boolean;
begin
  SkipSpace(S, P);
  Result := False;
  if P > Length(S) then Exit;
  if S[P] <> C then Exit;
  P := P + 1;
  Result := True;
end;

function JsonString(const S: String; var P: Integer; var Value: String): Boolean;
var C: Char; Code: Integer;
begin
  Result := False; Value := '';
  if not Consume(S, P, '"') then Exit;
  while P <= Length(S) do begin
    C := S[P]; P := P + 1;
    if C = '"' then begin Result := True; Exit; end;
    if Ord(C) < 32 then Exit;
    if C = '\' then begin
      if P > Length(S) then Exit;
      C := S[P]; P := P + 1;
      case C of
        '"', '\', '/': ;
        'b': C := #8;
        'f': C := #12;
        'n': C := #10;
        'r': C := #13;
        't': C := #9;
        'u': begin
          if P + 3 > Length(S) then Exit;
          Code := StrToIntDef('$' + Copy(S, P, 4), -1);
          if Code < 0 then Exit;
          C := Chr(Code); P := P + 4;
        end;
      else Exit;
      end;
    end;
    Value := Value + C;
  end;
end;

function OwnedMarker(Path, ExpectedRoot: String): Boolean;
var Raw: AnsiString; S, Key, Value, AppId, Root: String; P, Fields: Integer;
begin
  Result := False;
  if not LoadStringFromFile(Path, Raw) then Exit;
  S := UTF8Decode(Raw); P := 1; Fields := 0;
  if not Consume(S, P, '{') then Exit;
  repeat
    if not JsonString(S, P, Key) then Exit;
    if not Consume(S, P, ':') then Exit;
    if Key = 'schema_version' then begin
      if (Fields and 4) <> 0 then Exit;
      if not Consume(S, P, '1') then Exit;
      Fields := Fields or 4;
    end else begin
      if not JsonString(S, P, Value) then Exit;
      if Key = 'app_id' then begin
        if (Fields and 1) <> 0 then Exit;
        AppId := Value; Fields := Fields or 1;
      end else if Key = 'root' then begin
        if (Fields and 2) <> 0 then Exit;
        Root := Value; Fields := Fields or 2;
      end else Exit;
    end;
    SkipSpace(S, P);
    if Consume(S, P, '}') then Break;
    if not Consume(S, P, ',') then Exit;
  until False;
  SkipSpace(S, P);
  Result := (P > Length(S)) and (Fields = 7) and (AppId = 'IRON-SUN-LAN') and (CompareText(Root, ExpectedRoot) = 0);
end;

function EmptyDirectory(Path: String): Boolean;
var F: TFindRec;
begin
  Result := True;
  if FindFirst(AddBackslash(Path) + '*', F) then begin
    try
      repeat
        if (F.Name <> '.') and (F.Name <> '..') then begin Result := False; Break; end;
      until not FindNext(F);
    finally FindClose(F); end;
  end;
end;

function ShortcutAvailable(Path: String): Boolean;
var Shell, Link: Variant;
begin
  Result := not FileExists(Path);
  if Result then Exit;
  try
    Shell := CreateOleObject('WScript.Shell'); Link := Shell.CreateShortcut(Path);
    Result := CompareText(Link.TargetPath, ExpandConstant('{app}\IronSunLauncher.exe')) = 0;
  except Result := False; end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Root, Marker: String;
begin
  Result := ''; Root := GameRoot; Marker := Root + '\managed-install.json';
  if CompareText(ExpandFileName(WizardDirValue), Root + '\Launcher') <> 0 then begin
    Result := 'Install IRON SUN Launcher in its standard folder. Custom /DIR overrides are not supported.'; Exit;
  end;
  if not PlainPath(Root + '\Launcher') then begin Result := 'Linked installation folders are not supported.'; Exit; end;
  if FileExists(Marker) then begin
    if not OwnedMarker(Marker, Root) then begin Result := 'This folder does not belong to this IRON SUN installation. No files were changed.'; Exit; end;
  end else if DirExists(Root) and not EmptyDirectory(Root) then begin
    Result := 'The IRON SUN folder contains an unrecognized installation. No files were changed.'; Exit;
  end;
#ifndef FixtureRoot
  if not ShortcutAvailable(ExpandConstant('{userprograms}\IRON SUN Launcher.lnk')) then begin Result := 'The existing Start menu shortcut belongs to another application.'; Exit; end;
  if WizardIsTaskSelected('desktopicon') and not ShortcutAvailable(ExpandConstant('{userdesktop}\IRON SUN Launcher.lnk')) then begin Result := 'The existing desktop shortcut belongs to another application.'; Exit; end;
#endif
end;

function EscapeJson(S: String): String;
begin
  StringChangeEx(S, '\', '\\', True);
  StringChangeEx(S, '"', '\"', True);
  Result := S;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Marker, Error: String; NeedsRestart: Boolean;
begin
  if CurStep <> ssInstall then Exit;
  Error := PrepareToInstall(NeedsRestart);
  if Error <> '' then RaiseException(Error);
  Marker := GameRoot + '\managed-install.json';
  if not FileExists(Marker) then begin
    if not ForceDirectories(GameRoot) then RaiseException('Cannot create the IRON SUN installation folder.');
    if not SaveStringToFile(Marker, UTF8Encode('{"app_id":"IRON-SUN-LAN","root":"' + EscapeJson(GameRoot) + '","schema_version":1}'), False) then RaiseException('Cannot register the IRON SUN installation folder.');
  end;
end;

// Intentionally no recursive uninstall delete: game data, rollback files and saves are retained.
