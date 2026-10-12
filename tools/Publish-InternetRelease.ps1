param(
 [Parameter(Mandatory)][string]$PackageRoot,
 [Parameter(Mandatory)][string]$ArtifactManifest,
 [Parameter(Mandatory)][string]$LocalFeed,
 [Parameter(Mandatory)][ValidateRange(58,10000)][int]$Protocol,
 [string]$Repository='Wilcox-Hub/iron-sun-releases',
 [string]$ServerAlias='sidequest',
 [string]$ReleaseNotes='Private co-op server. Two weapon slots. Arena collision reliability.',
 [string]$DeliveryApproval,
 [switch]$PrepareOnly,
 [switch]$GameOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gh='C:/Program Files/GitHub CLI/gh.exe'
if($Repository -cne 'Wilcox-Hub/iron-sun-releases'){throw 'This publisher is scoped to the IRON SUN release repository.'}
$setup=Join-Path $sourceRoot 'build/setup/IRON-SUN-Setup.exe'
$delivery=$null
if(!$GameOnly -and !$PrepareOnly){
 if([string]::IsNullOrWhiteSpace($DeliveryApproval)){throw 'Supply the dated production delivery record before publishing.'}
 . (Join-Path $PSScriptRoot 'Delivery-Policy.ps1')
 $delivery=Get-VerifiedDeliveryApproval -ApprovalPath $DeliveryApproval -SetupPath $setup -LauncherPath (Join-Path $sourceRoot 'build/IronSunLauncher.exe')
}
$package=[IO.Path]::GetFullPath($PackageRoot)
$info=Get-Content -LiteralPath (Join-Path $package 'PackageInfo.json') -Raw|ConvertFrom-Json
if($info.Status -cne 'COMPLETE' -or $info.Configuration -cne 'Shipping'){throw 'Only a complete tested Shipping package may be published.'}
$proof=Get-Content -LiteralPath $ArtifactManifest -Raw|ConvertFrom-Json
$windows=Join-Path $package 'Windows'
if([IO.Path]::GetFullPath($proof.archive_absolute_path) -ine [IO.Path]::GetFullPath($windows) -or [int]$proof.protocol -ne $Protocol){throw 'Package proof identifies a different build.'}
$files=@(Get-ChildItem -LiteralPath $windows -Recurse -File)
if($files.Count -ne @($proof.artifacts).Count){throw 'Package inventory differs from its tested evidence.'}
foreach($item in $proof.artifacts){
 $path=Join-Path $windows $item.path
 if(!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -ne [long]$item.size_bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.sha256){throw ('Tested artifact changed: '+$item.path)}
}
$serverText=& 'C:/Windows/System32/OpenSSH/ssh.exe' -T -oBatchMode=yes -oClearAllForwardings=yes -oConnectTimeout=8 -oStrictHostKeyChecking=yes $ServerAlias 'cat /home/caiden/iron-sun-server/current/IronSunServer.json'
if($LASTEXITCODE -ne 0){throw 'Could not verify the live native server build.'}
$server=($serverText -join "`n")|ConvertFrom-Json
if([int]$server.protocol -ne $Protocol -or $server.engine -cne '5.8.3' -or $server.target -cne 'Server'){throw 'Deploy and test the matching native server before promoting this client release.'}
$version=Split-Path $package -Leaf
$manifest=Get-Content -LiteralPath (Join-Path $LocalFeed ('manifest-'+$version+'.json')) -Raw|ConvertFrom-Json
if($manifest.version -cne $version){throw 'Local feed does not identify this tested package.'}
$game=Join-Path $LocalFeed $manifest.archive
if((Get-Item -LiteralPath $game).Length -ne [long]$manifest.archive_size -or (Get-FileHash -LiteralPath $game -Algorithm SHA256).Hash -ne $manifest.archive_sha256){throw 'Game archive differs from the local verified feed.'}
$launcher=Join-Path $sourceRoot 'build/IronSunLauncher.exe'
if(!$GameOnly -and (!(Test-Path -LiteralPath $launcher) -or !(Test-Path -LiteralPath $setup))){throw 'Build and test the launcher and Windows setup first. Do not restore quarantined files or bypass protection.'}
# Preserve semantic version components; AssemblyFileVersion includes four parts.
$launcherVersion=$null
if(!$GameOnly){$parts=[Diagnostics.FileVersionInfo]::GetVersionInfo($launcher).FileVersion.Split('.');$launcherVersion=($parts[0..2]-join '.')}
$tag='playtest-vs'+$Protocol+'-'+$version+$(if($GameOnly){'-game'}else{'-launcher-'+$launcherVersion+'-setup-1'})
$output=Join-Path $sourceRoot ('build/releases/'+$tag)
[IO.Directory]::CreateDirectory($output)|Out-Null
$base='https://github.com/'+$Repository+'/releases/download/'+$tag+'/'
$manifest|Add-Member -NotePropertyName protocol -NotePropertyValue $Protocol -Force
$manifest|Add-Member -NotePropertyName archive_url -NotePropertyValue ($base+$manifest.archive) -Force
$manifest|Add-Member -NotePropertyName release_notes -NotePropertyValue $ReleaseNotes -Force
$keyPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IRON SUN Publishing/release-signing.key'
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
$rsa.PersistKeyInCsp=$false
try {
 $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($plain));[Array]::Clear($plain,0,$plain.Length)
 if($rsa.ToXmlString($false) -cne [IO.File]::ReadAllText((Join-Path $sourceRoot 'src/ReleasePublicKey.xml'))){throw 'Publisher signing identity differs from the embedded launcher key.'}
 function Write-Signed([string]$Name,$Data) {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Data|ConvertTo-Json -Depth 12))
  [IO.File]::WriteAllBytes((Join-Path $output ($Name+'.json')),$bytes)
  [IO.File]::WriteAllBytes((Join-Path $output ($Name+'.sig')),$rsa.SignData($bytes,'SHA256'))
 }
 Write-Signed 'game-manifest' $manifest
 if(!$GameOnly){
  $launchManifest=[ordered]@{schema_version=1;app_id='IRON-SUN-LAUNCHER';version=$launcherVersion;url=($base+'IronSunLauncher.exe');size_bytes=(Get-Item -LiteralPath $launcher).Length;sha256=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash}
  Write-Signed 'launcher-manifest' $launchManifest
  # ACCEPTED is this publisher's security acceptance, not a Microsoft case-completion claim.
  # Preserve the analyst disposition and validation scope explicitly in signed metadata.
  $setupManifest=[ordered]@{schema_version=1;app_id='IRON-SUN-SETUP';version=$launcherVersion;filename='IRON-SUN-Setup.exe';url=($base+'IRON-SUN-Setup.exe');size_bytes=(Get-Item -LiteralPath $setup).Length;sha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash;security_review_status=$(if($delivery){'ACCEPTED'}else{'NOT_ACCEPTED'});security_review_basis=$(if($delivery){$delivery.security_review_status}else{'NOT_ACCEPTED'});microsoft_submission_id=$(if($delivery){$delivery.microsoft_submission_id}else{''});delivery_verified=($null -ne $delivery);delivery_scope=$(if($delivery -and $delivery.PSObject.Properties['delivery_scope']){$delivery.delivery_scope}else{'FULL_FLOW'});normal_launcher_button_accepted=$(if($delivery){$delivery.game_install_play_accepted -eq $true}else{$false})}
  Write-Signed 'setup-manifest' $setupManifest
 }
} finally {$rsa.Dispose()}
$body="IRON SUN internal alpha / VS$Protocol`n`n$ReleaseNotes`n`nDownload IRON-SUN-Setup.exe. Open it once, install IRON SUN Launcher, and leave Open IRON SUN Launcher selected. Setup adds a Start menu app and offers a desktop shortcut. In the launcher, choose Install IRON SUN, then Play. Future published game updates are automatic.`n`nAll other assets below are updater payloads and metadata; friends do not need to open them. The game server invite is shared privately by your host.`n`nWindows x64. Launcher $launcherVersion. First launcher has no commercial Authenticode certificate.`n`nThis is a tested internal prototype, not beta approval. Different-Wi-Fi human combat and recovery acceptance remain open."
if($delivery -and $delivery.PSObject.Properties['delivery_scope'] -and $delivery.delivery_scope -ceq 'INTERNAL_ALPHA_BACKEND_AND_STARTUP'){$body+="`n`nDelivery validation: the exact reviewed launcher and setup pass Defender scans with protection enabled; production install/open/uninstall, live signed updater download/current and installed Shipping startup pass. Normal launcher-button interaction and a fresh friend-PC flow remain unverified because app control denied access. Microsoft's analyst removed the detection; its portal final field still says Pending. This is scoped alpha delivery, not a claim of completed Microsoft certification or whole-game beta readiness."}
if($GameOnly){$body="IRON SUN internal alpha / VS$Protocol`n`n$ReleaseNotes`n`nTemporary manual game download. Extract the COMPLETE ZIP, then run Windows/TP_FirstPerson.exe. Do not move the EXE out of its folder. Updates are manual for this download.`n`nThe custom launcher is withheld because Windows Defender blocked it. Do not disable protection or add exclusions to install it. It will only return after security review and a successful normal download/install check.`n`nThe game server invite is shared privately by your host. This is an internal prototype, not beta approval; different-Wi-Fi human combat and recovery acceptance remain open."}
$bodyPath=Join-Path $output 'release-notes.md';[IO.File]::WriteAllText($bodyPath,$body,[Text.UTF8Encoding]::new($false))
$assets=@($game,(Join-Path $output 'game-manifest.json'),(Join-Path $output 'game-manifest.sig'))
if(!$GameOnly){$assets+=@($setup,(Join-Path $output 'setup-manifest.json'),(Join-Path $output 'setup-manifest.sig'),$launcher,(Join-Path $output 'launcher-manifest.json'),(Join-Path $output 'launcher-manifest.sig'))}
$result=[ordered]@{prepared=$true;published=$false;mode=$(if($GameOnly){'manual-game-only'}else{'automatic-launcher'});repository=$Repository;tag=$tag;protocol=$Protocol;game_version=$version;launcher_version=$launcherVersion;assets=@($assets|ForEach-Object {@{name=(Split-Path $_ -Leaf);path=$_;size_bytes=(Get-Item -LiteralPath $_).Length;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})}
if(!$PrepareOnly){
 $existing=& $gh release view $tag --repo $Repository --json isDraft,tagName 2>$null
 if($LASTEXITCODE -eq 0){
  $state=($existing -join "`n")|ConvertFrom-Json
  if(!$state.isDraft){throw 'This immutable release is already published. Use a new tested game build ID or launcher version.'}
  $remoteNames=& $gh release view $tag --repo $Repository --json assets --jq '.assets[].name'
  foreach($asset in $assets){if((Split-Path $asset -Leaf) -notin @($remoteNames)){& $gh release upload $tag $asset --repo $Repository;if($LASTEXITCODE -ne 0){throw 'Draft upload failed; no release promoted.'}}}
 } else {
  & $gh release create $tag @assets --repo $Repository --draft --target main --title ('VS'+$Protocol+' / Internal Alpha') --notes-file $bodyPath
  if($LASTEXITCODE -ne 0){throw 'Draft release upload failed; no release promoted.'}
 }
 # Draft tags may not exist as Git refs yet; query the authenticated release list.
 $releases=(& $gh api ('repos/'+$Repository+'/releases?per_page=100') |Out-String)|ConvertFrom-Json
 if($LASTEXITCODE -ne 0){throw 'Could not verify draft release metadata.'}
 $candidates=@($releases|Where-Object tag_name -ceq $tag)
 if($candidates.Count -ne 1 -or !$candidates[0].draft){throw 'The expected draft release did not verify.'}
 $remote=$candidates[0]
 foreach($asset in $result.assets){
  $match=@($remote.assets|Where-Object name -ceq $asset.name)
  if($match.Count -ne 1 -or [long]$match[0].size -ne [long]$asset.size_bytes){throw 'Draft asset inventory did not verify; no release promoted.'}
  # GitHub supplies a SHA256 digest for newly uploaded release assets.
  if(!$match[0].PSObject.Properties['digest'] -or $match[0].digest -cne ('sha256:'+$asset.sha256.ToLowerInvariant())){throw 'Remote asset digest did not verify; no release promoted.'}
 }
 & $gh release edit $tag --repo $Repository --draft=false --latest
 if($LASTEXITCODE -ne 0){throw 'Release promotion could not be confirmed.'}
 $result.published=$true
 $result.url='https://github.com/'+$Repository+'/releases/tag/'+$tag
 if(!$GameOnly){
  $feedResult=& (Join-Path $PSScriptRoot 'Publish-SetupFeed.ps1') -ManifestPath (Join-Path $output 'setup-manifest.json') -SignaturePath (Join-Path $output 'setup-manifest.sig') -Tag $tag
  $result.website_setup_feed=($feedResult -join "`n")|ConvertFrom-Json
 }
}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $output 'publication-result.json') -Encoding UTF8
$result|ConvertTo-Json -Depth 8
