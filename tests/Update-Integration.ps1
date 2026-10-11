param([string]$OutputRoot=(Join-Path $PSScriptRoot '../test-output'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$run=Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ('checks-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
[IO.Directory]::CreateDirectory($run)|Out-Null
$tools=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src'))
$fixture=Join-Path $run 'feed';[IO.Directory]::CreateDirectory($fixture)|Out-Null
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(2048)
$rsa.PersistKeyInCsp=$false
$pub=Join-Path $run 'TestPublicKey.xml';[IO.File]::WriteAllText($pub,$rsa.ToXmlString($false))
$root=Join-Path $run 'install'
$results=New-Object Collections.Generic.List[object]
$required=@('Windows/TP_FirstPerson.exe','Windows/Ridgefire/Binaries/Win64/TP_FirstPerson-Win64-Shipping.exe','Windows/Ridgefire/Content/Paks/Ridgefire-Windows.pak','Windows/Ridgefire/Content/Paks/Ridgefire-Windows.ucas','Windows/Ridgefire/Content/Paks/Ridgefire-Windows.utoc')
function Publish-Fixture([string]$Version) {
 $payload=Join-Path $run $Version;[IO.Directory]::CreateDirectory($payload)|Out-Null
 $inventory=@()
 foreach($relative in $required){
  $path=Join-Path $payload $relative;[IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
  [IO.File]::WriteAllText($path,'NONEXECUTABLE FIXTURE '+$Version+' '+$relative)
  $inventory+=@{path=$relative;size=(Get-Item $path).Length;sha256=(Get-FileHash $path -Algorithm SHA256).Hash}
 }
 $archive='iron-sun-'+$Version+'.zip';$zip=Join-Path $fixture $archive
 [IO.Compression.ZipFile]::CreateFromDirectory($payload,$zip)
 $manifest=[ordered]@{schema_version=1;app_id='IRON-SUN-LAN';version=$Version;protocol=58;release_notes='Fixture release';archive=$archive;archive_url=('https://github.com/Wilcox-Hub/iron-sun-releases/releases/download/test/'+$archive);archive_size=(Get-Item $zip).Length;archive_sha256=(Get-FileHash $zip -Algorithm SHA256).Hash;files=$inventory}
 Write-Fixture $manifest
 return $manifest
}
function Write-Fixture($Manifest) {
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Manifest|ConvertTo-Json -Depth 10))
 [IO.File]::WriteAllBytes((Join-Path $fixture 'game-manifest.json'),$bytes)
 [IO.File]::WriteAllBytes((Join-Path $fixture 'game-manifest.sig'),$rsa.SignData($bytes,'SHA256'))
}
function Invoke-TestEngine([string]$Action='Update',[string]$Root=$root) {
 $lines=& (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $tools 'InternetUpdate.ps1') -InstallRoot $Root -Action $Action -FixtureRoot $fixture -PublicKeyPath $pub
 $code=$LASTEXITCODE
 $items=@($lines|Where-Object {$_ -like 'IRON_SUN_EVENT *'}|ForEach-Object {$_.Substring(15)|ConvertFrom-Json})
 $final=$items|Where-Object type -eq result|Select-Object -Last 1
 return @{code=$code;items=$items;result=$(if($final){$final.data}else{$null});errors=@($items|Where-Object type -eq error)}
}
function Pass([string]$Name,[bool]$Condition) {if(!$Condition){throw ('FAILED: '+$Name)};$results.Add(@{name=$Name;passed=$true})}
function Version-In([string]$Folder){return (Get-Content (Join-Path $Folder 'installed.json') -Raw|ConvertFrom-Json).version}
try {
 $v1=Publish-Fixture 'fixture-v1'
 $check=Invoke-TestEngine 'Check';Pass 'Check announces signed release without installing game' ($check.code -eq 0 -and $check.result.status -eq 'AVAILABLE' -and !(Test-Path (Join-Path $root 'Game')))
 $first=Invoke-TestEngine;Pass 'Fresh signed release installs complete payload' ($first.code -eq 0 -and $first.result.status -eq 'UPDATED' -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v1')
 $save=Join-Path $root 'PlayerSave.sav';[IO.File]::WriteAllText($save,'KEEP PLAYER PROGRESS')
 $current=Invoke-TestEngine;Pass 'Repeated check stays CURRENT' ($current.code -eq 0 -and $current.result.status -eq 'CURRENT')
 $v2=Publish-Fixture 'fixture-v2'
 $second=Invoke-TestEngine;Pass 'New build updates and retains previous' ($second.code -eq 0 -and (Version-In (Join-Path $root 'Previous')) -eq 'fixture-v1' -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v2')
 $back=Invoke-TestEngine 'Rollback';Pass 'Rollback restores previous build' ($back.code -eq 0 -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v1')
 $held=Invoke-TestEngine;Pass 'Rolled-back build holds against same rejected release' ($held.code -eq 0 -and $held.result.status -eq 'ROLLBACK_HELD' -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v1')
 $v3=Publish-Fixture 'fixture-v3'
 $next=Invoke-TestEngine;Pass 'Newer release clears rollback hold' ($next.code -eq 0 -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v3')
 $damaged=Join-Path $root $required[2];$damaged=Join-Path (Join-Path $root 'Game') $required[2]
 [IO.File]::WriteAllText($damaged,'DAMAGED')
 $repair=Invoke-TestEngine 'Repair';Pass 'Repair replaces corrupt same-version game' ($repair.code -eq 0 -and $repair.result.status -eq 'REPAIRED' -and (Get-FileHash $damaged -Algorithm SHA256).Hash -eq $v3.files[2].sha256)
 Pass 'Player saves survive update, rollback, and repair' ([IO.File]::ReadAllText($save) -eq 'KEEP PLAYER PROGRESS')
 $signed=Join-Path $fixture 'game-manifest.json';$good=[IO.File]::ReadAllBytes($signed)
 [IO.File]::WriteAllText($signed,'{"schema_version":1,"version":"tampered"}')
 $tamper=Invoke-TestEngine;Pass 'Unsigned metadata mutation rejected; installed game preserved' ($tamper.code -ne 0 -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v3')
 [IO.File]::WriteAllBytes($signed,$good)
 $unsafe=($v3|ConvertTo-Json -Depth 12|ConvertFrom-Json);$unsafe.version='unsafe-v4';$unsafe.archive='iron-sun-unsafe-v4.zip';$unsafe.files[0].path='Windows/../../outside.exe';Write-Fixture $unsafe
 $badPath=Invoke-TestEngine;Pass 'Signed path traversal rejected before extraction' ($badPath.code -ne 0 -and !(Test-Path (Join-Path $run 'outside.exe')) -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v3')
 $v4=Publish-Fixture 'fixture-v4';[IO.File]::AppendAllText((Join-Path $fixture $v4.archive),'CORRUPT')
 $badZip=Invoke-TestEngine;Pass 'Corrupt archive rejected; previous installation intact' ($badZip.code -ne 0 -and (Version-In (Join-Path $root 'Game')) -eq 'fixture-v3')
 $foreign=Join-Path $run 'foreign';[IO.Directory]::CreateDirectory($foreign)|Out-Null;[IO.File]::WriteAllText((Join-Path $foreign 'keep.txt'),'NOT OUR FOLDER')
 $badRoot=Invoke-TestEngine 'Update' $foreign;Pass 'Foreign nonempty folder refused' ($badRoot.code -ne 0 -and [IO.File]::ReadAllText((Join-Path $foreign 'keep.txt')) -eq 'NOT OUR FOLDER')
 Write-Fixture $v3
 # Simulate interruption between moving the current install aside and activating a new payload.
 $interrupt=Join-Path $run 'interrupted';$install=Invoke-TestEngine 'Update' $interrupt
 Move-Item -LiteralPath (Join-Path $interrupt 'Game') -Destination (Join-Path $interrupt 'Previous')
 $recover=Invoke-TestEngine 'Update' $interrupt;Pass 'Interrupted directory swap recovers verified install' ($recover.code -eq 0 -and (Version-In (Join-Path $interrupt 'Game')) -eq 'fixture-v3')
 $output=@{passed=$true;checks=$results.ToArray();run=$run;scope='Actual Windows PowerShell 5.1 production internet-update driver with RSA-signed local fixtures. No live HTTPS or game execution.'}
 $output|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding UTF8
 $output|ConvertTo-Json -Depth 8
} finally {$rsa.Dispose()}
