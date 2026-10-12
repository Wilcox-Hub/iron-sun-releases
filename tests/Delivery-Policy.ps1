$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Delivery-Policy.ps1')
$run=Join-Path $PSScriptRoot ('../test-output/delivery-policy-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $run -Force|Out-Null
$setup=Join-Path $run 'setup.fixture';$launcher=Join-Path $run 'launcher.fixture'
[IO.File]::WriteAllText($setup,'INERT SETUP FIXTURE');[IO.File]::WriteAllText($launcher,'INERT LAUNCHER FIXTURE')
$record=@{schema_version=1;microsoft_submission_id='TEST-ONLY';setup_sha256=(Get-FileHash $setup).Hash;launcher_sha256=(Get-FileHash $launcher).Hash;security_review_status='ANALYST_DETECTION_REMOVED';delivery_scope='INTERNAL_ALPHA_BACKEND_AND_STARTUP';alpha_distribution_requested=$true;protected_download_install_accepted=$true;launcher_opened=$true;uninstall_accepted=$true;game_install_play_accepted=$false;live_backend_game_install_accepted=$true;live_backend_current_accepted=$true;installed_game_files_verified=32;installed_game_startup_accepted=$true;defender_scan_accepted=$true;defender_protection_enabled=$true}
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,$Data,[bool]$Expected){
 $path=Join-Path $run ([Guid]::NewGuid().ToString('N')+'.json');$Data|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding utf8
 $actual=$true;try {$accepted=Get-VerifiedDeliveryApproval -ApprovalPath $path -SetupPath $setup -LauncherPath $launcher}catch{$actual=$false}
 if($actual -ne $Expected){throw ('Unexpected delivery policy: '+$Name)}
 if($actual -and $Data.game_install_play_accepted -eq $false -and $accepted.game_install_play_accepted -ne $false){throw 'Policy fabricated GUI acceptance.'}
 $results.Add(@{name=$Name;passed=$true})
}
Check 'Explicit protected alpha accepts backend/startup while preserving unverified GUI field' $record $true
foreach($field in @('alpha_distribution_requested','protected_download_install_accepted','launcher_opened','uninstall_accepted','live_backend_game_install_accepted','live_backend_current_accepted','installed_game_startup_accepted','defender_scan_accepted','defender_protection_enabled')){$copy=$record.Clone();$copy[$field]=$false;Check ('Missing '+$field+' rejects alpha') $copy $false}
foreach($change in @(@{field='security_review_status';value='NOT_ACCEPTED'},@{field='delivery_scope';value='UNKNOWN'},@{field='installed_game_files_verified';value=0},@{field='setup_sha256';value=('0'*64)},@{field='launcher_sha256';value=('0'*64)})){$copy=$record.Clone();$copy[$change.field]=$change.value;Check ('Invalid '+$change.field+' rejects alpha') $copy $false}
$copy=$record.Clone();$copy.security_review_status='ACCEPTED';Check 'Review alone cannot fabricate full Install/Play acceptance' $copy $false
$copy.game_install_play_accepted=$true;Check 'Original full delivery remains compatible' $copy $true
$result=@{passed=$true;checks=$results.ToArray();scope='Actual production delivery-policy helper with inert file fixtures; no installation, keys, network or publication.'}
$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$result|ConvertTo-Json -Depth 6
