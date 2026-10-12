param([string]$IsccPath=(Join-Path $PSScriptRoot '../../../tools/vendor/inno-setup/ISCC.exe'))
$ErrorActionPreference='Stop'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $sourceRoot ('test-output/setup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$install=Join-Path $run 'Install'
[IO.Directory]::CreateDirectory($run)|Out-Null
$payload=Join-Path $run 'IronSunLauncher.exe'
$stub=@'
using System; using System.IO; using System.Reflection;
[assembly: AssemblyFileVersion("1.0.1.0")]
class SetupFixture { static void Main(string[] args) {
 File.WriteAllText(Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "opened.txt"),String.Join("\n",args));
} }
'@
$stubSource=Join-Path $run 'SetupFixture.cs'
[IO.File]::WriteAllText($stubSource,$stub)
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:winexe /platform:x64 ('/out:'+$payload) $stubSource
if($LASTEXITCODE -ne 0){throw 'Fixture compile failed'}
& $IsccPath ('/DLauncherPayload='+$payload) ('/DFixtureRoot='+$install) ('/DSetupOutput='+$run) (Join-Path $sourceRoot 'installer/IronSun.iss') | Out-File (Join-Path $run 'compile.log')
if($LASTEXITCODE -ne 0){throw 'Setup compile failed; inspect compile.log'}
# Compile the real production directives too, but only with this inert stub. Never distribute this fixture.
& $IsccPath ('/DLauncherPayload='+$payload) ('/DSetupOutput='+(Join-Path $run 'production-config-fixture')) (Join-Path $sourceRoot 'installer/IronSun.iss') | Out-File (Join-Path $run 'production-config-compile.log')
if($LASTEXITCODE -ne 0){throw 'Production setup configuration compile failed'}
$setup=Join-Path $run 'IRON-SUN-Setup.exe'
$checks=[Collections.Generic.List[object]]::new()
function Assert([bool]$Pass,[string]$Name){$checks.Add([pscustomobject]@{name=$Name;passed=$Pass});if(!$Pass){throw $Name}}
function InstallFixture([string]$Task){
 $log=Join-Path $run ('install-'+[Guid]::NewGuid().ToString('N')+'.log')
 $p=Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/TASKS="'+$Task+'"'),('/LOG="'+$log+'"')) -WindowStyle Hidden -Wait -PassThru
 return $p.ExitCode
}
function UninstallFixture {
 $exe=Join-Path $install 'Launcher/unins000.exe'
 $p=Start-Process -FilePath $exe -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -WindowStyle Hidden -Wait -PassThru
 Assert ($p.ExitCode -eq 0) 'Owned fixture uninstall succeeds'
}
# Use the real compiled Inno setup with an inert fixture payload. Never execute the blocked production launcher.
[IO.Directory]::CreateDirectory($install)|Out-Null
$foreign=Join-Path $install 'unrelated.txt';[IO.File]::WriteAllText($foreign,'keep')
Assert ((InstallFixture '') -ne 0 -and [IO.File]::ReadAllText($foreign) -ceq 'keep') 'Foreign nonempty root rejected without changing its data'
Remove-Item -LiteralPath $foreign
Assert ((InstallFixture 'desktopicon') -eq 0) 'Fresh per-user fixture setup succeeds'
$marker=Get-Content -LiteralPath (Join-Path $install 'managed-install.json') -Raw|ConvertFrom-Json
Assert ($marker.app_id -ceq 'IRON-SUN-LAN' -and $marker.root -ieq $install) 'Ownership marker identifies the exact installation root'
$shell=New-Object -ComObject WScript.Shell
try {
 $start=Join-Path $install 'Shortcuts/Start/IRON SUN Launcher.lnk'
 $desktop=Join-Path $install 'Shortcuts/Desktop/IRON SUN Launcher.lnk'
 foreach($linkPath in @($start,$desktop)){
  $link=$shell.CreateShortcut($linkPath)
  Assert ($link.TargetPath -ieq (Join-Path $install 'Launcher/IronSunLauncher.exe') -and $link.Arguments -ceq ('--install-root "'+$install+'" --no-shortcut')) ('Valid launcher shortcut: '+(Split-Path (Split-Path $linkPath) -Leaf))
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)|Out-Null
 }
} finally {[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)|Out-Null}
$uninstallKey='HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/IRON-SUN-SETUP-FIXTURE_is1'
Assert ((Get-ItemProperty -LiteralPath $uninstallKey).DisplayName -ceq 'IRON SUN Setup Fixture') 'Setup registers a removable app for the current user'
Start-Process -FilePath $desktop -WindowStyle Hidden
$opened=Join-Path $install 'Launcher/opened.txt'
$deadline=[DateTime]::UtcNow.AddSeconds(5)
while(!(Test-Path -LiteralPath $opened) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
Assert (Test-Path -LiteralPath $opened) 'Desktop shortcut opens the actual installed inert fixture app'
[IO.Directory]::CreateDirectory((Join-Path $install 'Game/Windows/Ridgefire/Saved/SaveGames'))|Out-Null
$save=Join-Path $install 'Game/Windows/Ridgefire/Saved/SaveGames/player.sav';[IO.File]::WriteAllText($save,'saved-run')
Assert ((InstallFixture 'desktopicon') -eq 0 -and [IO.File]::ReadAllText($save) -ceq 'saved-run') 'Setup repair accepts its owned folder and preserves game saves'
# Simulate the launcher's independent signed self-update, then run the older setup again.
$newSource=Join-Path $run 'NewerFixture.cs';[IO.File]::WriteAllText($newSource,$stub.Replace('1.0.1.0','1.0.2.0'))
$installedExe=Join-Path $install 'Launcher/IronSunLauncher.exe'
& $csc /nologo /target:winexe /platform:x64 ('/out:'+$installedExe) $newSource
if($LASTEXITCODE -ne 0){throw 'Newer fixture compile failed'}
$newHash=(Get-FileHash -LiteralPath $installedExe -Algorithm SHA256).Hash
Assert ((InstallFixture 'desktopicon') -eq 0 -and (Get-FileHash -LiteralPath $installedExe -Algorithm SHA256).Hash -ceq $newHash) 'Older setup preserves a newer self-updated launcher'
UninstallFixture
Assert (!(Test-Path -LiteralPath $start) -and !(Test-Path -LiteralPath $desktop) -and !(Test-Path -LiteralPath $uninstallKey) -and [IO.File]::ReadAllText($save) -ceq 'saved-run') 'Uninstall removes app registration and shortcuts while retaining game saves'
Assert ((InstallFixture '') -eq 0 -and !(Test-Path -LiteralPath $desktop) -and (Test-Path -LiteralPath $start)) 'Desktop shortcut is optional; Start menu app remains available'
UninstallFixture
$markerPath=Join-Path $install 'managed-install.json'
[IO.File]::WriteAllText($markerPath,'{"app_id":"IRON-SUN-LAN","root":"wrong","schema_version":1}')
Assert ((InstallFixture '') -ne 0 -and [IO.File]::ReadAllText($save) -ceq 'saved-run') 'Mismatched ownership rejected before any installation changes'
$result=[ordered]@{passed=$true;recorded_on=(Get-Date -Format 'yyyy-MM-dd');run=$run;setup_sha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash;checks=$checks;scope='Actual compiled Inno installer and uninstaller with inert fixture executable. Production payload remains Windows-blocked; no production setup, live download, game execution or post-install launcher-window acceptance.'}
$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'results.json') -Encoding UTF8
$result|ConvertTo-Json -Depth 6
