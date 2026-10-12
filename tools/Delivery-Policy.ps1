function Get-VerifiedDeliveryApproval {
 param([Parameter(Mandatory)][string]$ApprovalPath,[Parameter(Mandatory)][string]$SetupPath,[Parameter(Mandatory)][string]$LauncherPath)
 $ErrorActionPreference='Stop'
 if(!(Test-Path -LiteralPath $ApprovalPath)){throw 'Supply dated production delivery evidence before publishing.'}
 $record=Get-Content -LiteralPath $ApprovalPath -Raw|ConvertFrom-Json
 function Field([string]$Name){$property=$record.PSObject.Properties[$Name];if($null -eq $property){return $null};return $property.Value}
 if((Field 'schema_version') -ne 1 -or [string]::IsNullOrWhiteSpace((Field 'microsoft_submission_id')) -or (Field 'protected_download_install_accepted') -ne $true -or (Field 'launcher_opened') -ne $true -or (Field 'uninstall_accepted') -ne $true){throw 'Production install/open/uninstall evidence is incomplete.'}
 $full=(Field 'security_review_status') -ceq 'ACCEPTED' -and (Field 'game_install_play_accepted') -eq $true
 $alpha=(Field 'delivery_scope') -ceq 'INTERNAL_ALPHA_BACKEND_AND_STARTUP' -and (Field 'alpha_distribution_requested') -eq $true -and (Field 'security_review_status') -ceq 'ANALYST_DETECTION_REMOVED' -and (Field 'live_backend_game_install_accepted') -eq $true -and (Field 'live_backend_current_accepted') -eq $true -and (Field 'installed_game_files_verified') -ge 5 -and (Field 'installed_game_startup_accepted') -eq $true -and (Field 'defender_scan_accepted') -eq $true -and (Field 'defender_protection_enabled') -eq $true
 if(!$full -and !$alpha){throw 'Neither full delivery nor explicitly requested, protected internal-alpha delivery has been accepted.'}
 foreach($item in @(@{path=$SetupPath;hash=(Field 'setup_sha256')},@{path=$LauncherPath;hash=(Field 'launcher_sha256')})){
  if($item.hash -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash -ine $item.hash){throw 'Delivery approval identifies different binaries.'}
 }
 return $record
}
