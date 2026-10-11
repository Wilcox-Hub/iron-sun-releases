param(
 [Parameter(Mandatory)][string]$InstallRoot,
 [ValidateSet('Check','Update','Repair','Rollback')][string]$Action='Update',
 [string]$FeedUrl='https://github.com/Wilcox-Hub/iron-sun-releases/releases/latest/download/game-manifest.json',
 [string]$PublicKeyPath='',
 [string]$FixtureRoot=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if(!$PublicKeyPath){$PublicKeyPath=Join-Path $PSScriptRoot 'ReleasePublicKey.xml'}
Import-Module (Join-Path $PSScriptRoot 'RidgefireUpdate.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'InternetFeed.psm1') -Force
$core=Get-Module RidgefireUpdate
function Emit($Value){Write-Output ('IRON_SUN_EVENT '+($Value|ConvertTo-Json -Depth 8 -Compress))}
try {
 $root=& $core {param($p) Get-OwnedRoot $p} $InstallRoot
 $game=Join-Path $root 'Game'
 $installed=& $core {param($p) Get-Installed $p} $game
 if($Action -eq 'Rollback'){
  $result=Invoke-RidgefireUpdate -FeedRoot (Join-Path $root 'InternetCache') -InstallRoot $root -Rollback -NoLaunch
  Emit @{type='result';data=$result};exit 0
 }
 Emit @{type='status';message='Checking the latest playtest release...'}
 try {$feed=Get-SignedGameFeed -FeedUrl $FeedUrl -PublicKeyPath $PublicKeyPath -FixtureRoot $FixtureRoot}
 catch {
  # An unavailable network can preserve an existing install; invalid release signatures fail closed.
  if(!$installed -or $_.Exception.Message -match 'signature|compatibility|HTTPS|exceeds'){throw}
  & $core {param($p,$m) Confirm-Payload $p $m -CriticalOnly} $game $installed
  Emit @{type='result';data=@{status='OFFLINE_CURRENT';version=$installed.version;warning='Could not reach updates. The installed game is available; co-op needs matching builds.';feed_available=$false}};exit 0
 }
 $manifest=& $core {param($m) Test-Manifest $m} $feed.manifest
 $check=@{status='AVAILABLE';version=$manifest.version;protocol=$manifest.protocol;archive_size=$manifest.archive_size;installed_version=$(if($installed){$installed.version}else{''});release_notes=$manifest.release_notes;feed_available=$true}
 if($Action -eq 'Check'){Emit @{type='result';data=$check};exit 0}
 $lock=$null
 try {
  # Serialize the shared download cache as well as the core install swap.
  try {$lock=[IO.File]::Open((Join-Path $root 'internet-update.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'Another IRON SUN launcher is already updating.'}
  & $core {param($p) Assert-GameClosed $p} $game
  $cache=Join-Path $root 'InternetCache'
  $cache=& $core {param($p) Assert-PlainPath $p} $cache
  [IO.Directory]::CreateDirectory($cache)|Out-Null
  $archive=& $core {param($r,$p) Resolve-Child $r $p} $cache $manifest.archive
  $needsDownload=!$installed -or $installed.version -cne $manifest.version -or $Action -eq 'Repair'
  if($needsDownload){
   $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($root))
   $expanded=[long]0;foreach($file in $manifest.files){$expanded += [long]$file.size}
   if($drive.AvailableFreeSpace -lt $expanded+2*[long]$manifest.archive_size+536870912){throw 'Free more disk space before installing IRON SUN.'}
   $cachedGood=(Test-Path -LiteralPath $archive) -and (Get-Item -LiteralPath $archive).Length -eq [long]$manifest.archive_size
   if($cachedGood){$cachedGood=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $manifest.archive_sha256}
   if(!$cachedGood){
    Emit @{type='status';message='Downloading IRON SUN...'}
    Receive-VerifiedArchive -Manifest $manifest -Destination $archive -FixtureRoot $FixtureRoot -Progress {param($percent,$bytes) Emit @{type='progress';percent=$percent;bytes=$bytes}}
   }
  }
  [IO.File]::WriteAllBytes((Join-Path $cache 'latest.json'),$feed.bytes)
  Emit @{type='status';message='Verifying game files...'}
  if($Action -eq 'Repair' -and $installed){
   # Same-version repair stages and verifies the replacement first, then uses the core swap.
   $stageName='Repair-'+[Guid]::NewGuid().ToString('N')
   $stage=Join-Path $root $stageName
   [IO.Directory]::CreateDirectory($stage)|Out-Null
   try {
    & $core {param($a,$s,$m) Expand-VerifiedPayload $a $s $m;Write-AtomicJson (Join-Path $s 'installed.json') $m} $archive $stage $manifest
    & $core {param($p) Assert-GameClosed $p} $game
    $previous=Join-Path $root 'Previous'
    if(Test-Path -LiteralPath $previous){& $core {param($r) $null=Get-Installed (Join-Path $r 'Previous');Remove-OwnedChild $r 'Previous'} $root}
    Move-Item -LiteralPath $game -Destination $previous
    try {Move-Item -LiteralPath $stage -Destination $game}catch{Move-Item -LiteralPath $previous -Destination $game;throw}
    $result=@{status='REPAIRED';version=$manifest.version;protocol=$manifest.protocol;feed_available=$true;warning=$null}
   } finally {& $core {param($r,$p) Remove-OwnedChild $r $p} $root $stageName}
  } else {$result=Invoke-RidgefireUpdate -FeedRoot $cache -InstallRoot $root -NoLaunch}
  # Keep only the current archive, so update caches do not grow without a bound.
  foreach($file in Get-ChildItem -LiteralPath $cache -Filter 'iron-sun-*.zip' -File){if($file.Name -cne $manifest.archive){Remove-Item -LiteralPath $file.FullName -Force}}
  if($result -is [Collections.IDictionary]){$result['release_notes']=$manifest.release_notes;$result['protocol']=$manifest.protocol}
  else {$result|Add-Member -NotePropertyName release_notes -NotePropertyValue $manifest.release_notes -Force;$result|Add-Member -NotePropertyName protocol -NotePropertyValue $manifest.protocol -Force}
  Emit @{type='result';data=$result}
 } finally {if($lock){$lock.Dispose()}}
} catch {Emit @{type='error';message=$_.Exception.Message};exit 1}
