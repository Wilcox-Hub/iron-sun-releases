Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:AppId = 'IRON-SUN-LAN'
$script:RequiredFiles = @('Windows/TP_FirstPerson.exe','Windows/Ridgefire/Binaries/Win64/TP_FirstPerson-Win64-Shipping.exe','Windows/Ridgefire/Content/Paks/Ridgefire-Windows.pak','Windows/Ridgefire/Content/Paks/Ridgefire-Windows.ucas','Windows/Ridgefire/Content/Paks/Ridgefire-Windows.utoc')

function Assert-PlainPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked paths are not allowed: $cursor" }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if (!$parent) { break }
        $cursor = $parent.FullName
    }
    return $full.TrimEnd('\','/')
}
function Resolve-Child([string]$Root,[string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) { throw 'Invalid update path.' }
    $parts = $Relative.Replace('\','/').Split('/')
    foreach ($part in $parts) {
        if (!$part -or $part -in @('.','..') -or $part -match '[<>:"|?*\x00-\x1f]' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw "Unsafe update path: $Relative" }
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath((Join-Path $base ($parts -join '\')))
    if (!$full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Update path escapes its directory.' }
    return $full
}
function Write-AtomicJson([string]$Path,$Value) {
    $temporary = $Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    $backup = $Path+'.'+[Guid]::NewGuid().ToString('N')+'.bak'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    try {
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,$backup) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
    }
}
function Read-Json([string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -gt 16777216) { throw 'Update metadata is too large.' }
    return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}
function Test-Manifest($Manifest) {
    if ($Manifest.schema_version -ne 1 -or $Manifest.app_id -cne $script:AppId -or $Manifest.version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Unsupported update manifest.' }
    if ($Manifest.archive -cne ('iron-sun-'+$Manifest.version+'.zip') -or $Manifest.archive_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [long]$Manifest.archive_size -le 0 -or [long]$Manifest.archive_size -gt 10737418240) { throw 'Invalid update archive metadata.' }
    $files = @($Manifest.files)
    if ($files.Count -lt 5 -or $files.Count -gt 20000) { throw 'Invalid update file inventory.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $total = [long]0
    foreach ($file in $files) {
        $path = [string]$file.path
        if (!$path.StartsWith('Windows/',[StringComparison]::Ordinal) -or $path -match '(?i)(^|/)(Saved|SaveGames)(/|$)') { throw 'Payload includes an invalid game path or save data.' }
        $null = Resolve-Child 'C:\IRON-SUN-validation' $path
        if (!$seen.Add($path) -or $file.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [long]$file.size -lt 0) { throw 'Invalid or duplicate payload entry.' }
        $total += [long]$file.size
        if ($total -gt 21474836480) { throw 'Update payload exceeds the supported size.' }
    }
    foreach ($required in $script:RequiredFiles) { if (!$seen.Contains($required)) { throw "Missing required game file: $required" } }
    return $Manifest
}
function Confirm-Payload([string]$Root,$Manifest,[switch]$CriticalOnly) {
    $null = Test-Manifest $Manifest
    foreach ($file in @($Manifest.files)) {
        if ($CriticalOnly -and $file.path -notin $script:RequiredFiles) { continue }
        $path = Resolve-Child $Root $file.path
        $null = Assert-PlainPath $path
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne [long]$file.size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { throw "Game verification failed: $($file.path)" }
    }
}
function Expand-VerifiedPayload([string]$Archive,[string]$Destination,$Manifest) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $expected = @{}
        foreach ($file in @($Manifest.files)) { $expected[$file.path] = $file }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if ($name.EndsWith('/')) {
                $null = Resolve-Child $Destination $name.TrimEnd('/')
                continue
            }
            $target = Resolve-Child $Destination $name
            if (!$seen.Add($name) -or (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'Duplicate or linked ZIP entry.' }
            if (!$expected.ContainsKey($name)) {
                if ($name -in @('READ-ME-FIRST.txt','PackageInfo.json','package-artifacts.json')) { continue }
                throw "Unexpected ZIP entry: $name"
            }
            if ($entry.Length -ne [long]$expected[$name].size) { throw "ZIP size mismatch: $name" }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
        foreach ($name in $expected.Keys) { if (!$seen.Contains($name)) { throw "ZIP entry missing: $name" } }
    } finally { $zip.Dispose() }
    Confirm-Payload $Destination $Manifest
}
function Get-OwnedRoot([string]$Root) {
    $full = Assert-PlainPath $Root
    if ($full.Length -lt 6 -or $full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\') -or $full.StartsWith('\\')) { throw 'Install root must be a dedicated local folder.' }
    $marker = Join-Path $full 'managed-install.json'
    if (Test-Path -LiteralPath $full) {
        if (!(Test-Path -LiteralPath $marker)) {
            if (@(Get-ChildItem -LiteralPath $full -Force).Count) { throw 'Refusing to manage a nonempty folder without an IRON SUN ownership marker.' }
        } else {
            $owner = Read-Json $marker
            if ($owner.app_id -cne $script:AppId -or $owner.root -ine $full) { throw 'Install ownership marker does not match.' }
        }
    } else { [IO.Directory]::CreateDirectory($full) | Out-Null }
    if (!(Test-Path -LiteralPath $marker)) { Write-AtomicJson $marker ([ordered]@{app_id=$script:AppId;root=$full;schema_version=1}) }
    return $full
}
function Remove-OwnedChild([string]$Root,[string]$Relative) {
    $full = Resolve-Child $Root $Relative
    $null = Assert-PlainPath $full
    if (Test-Path -LiteralPath $full -PathType Container) {
        foreach ($item in Get-ChildItem -LiteralPath $full -Recurse -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to remove a directory containing linked paths.' }
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    } elseif (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
}
function Get-Installed([string]$GameRoot) {
    $record = Join-Path $GameRoot 'installed.json'
    if (!(Test-Path -LiteralPath $GameRoot)) { return $null }
    if (!(Test-Path -LiteralPath $record)) { throw 'Existing game folder has no installation record.' }
    $null = Assert-PlainPath $record
    return (Test-Manifest (Read-Json $record))
}
function Assert-GameClosed([string]$GameRoot) {
    foreach ($process in @(Get-Process -Name 'TP_FirstPerson','TP_FirstPerson-Win64-Shipping' -ErrorAction SilentlyContinue)) {
        try { $path = $process.Path } catch { $path = $null }
        if (!$path -or $path.StartsWith($GameRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Close IRON SUN before installing an update or rolling back.' }
    }
}
function Repair-InterruptedSwap([string]$Root) {
    $game = Join-Path $Root 'Game'
    $previous = Join-Path $Root 'Previous'
    if (!(Test-Path -LiteralPath $game) -and (Test-Path -LiteralPath $previous)) {
        $old = Get-Installed $previous
        Confirm-Payload $previous $old -CriticalOnly
        Move-Item -LiteralPath $previous -Destination $game
    }
}
function Invoke-RidgefireUpdate {
    param([Parameter(Mandatory)][string]$FeedRoot,[Parameter(Mandatory)][string]$InstallRoot,[switch]$NoLaunch,[switch]$Rollback)
    $root = Get-OwnedRoot $InstallRoot
    $lock = $null
    try {
        try { $lock = [IO.File]::Open((Join-Path $root 'update.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
        catch { throw 'Another IRON SUN launcher is already updating. Please wait.' }
        Repair-InterruptedSwap $root
        $game = Join-Path $root 'Game'
        $previous = Join-Path $root 'Previous'
        $installed = Get-Installed $game
        $result = [ordered]@{app_id=$script:AppId;status='CURRENT';version=$null;install_root=$root;launch_requested=(!$NoLaunch);feed_available=$false;warning=$null}
        if ($Rollback) {
            Assert-GameClosed $game
            $blockedVersion = $(if ($installed) {$installed.version} else {''})
            $prior = Get-Installed $previous
            if (!$prior) { throw 'There is no previous version to restore.' }
            Confirm-Payload $previous $prior
            $swapName = 'Rollback-'+[Guid]::NewGuid().ToString('N')
            $swap = Resolve-Child $root $swapName
            try {
                if ($installed) { Move-Item -LiteralPath $game -Destination $swap }
                Move-Item -LiteralPath $previous -Destination $game
                if (Test-Path -LiteralPath $swap) { Move-Item -LiteralPath $swap -Destination $previous }
            } catch {
                if (!(Test-Path -LiteralPath $game) -and (Test-Path -LiteralPath $swap)) { Move-Item -LiteralPath $swap -Destination $game }
                throw
            }
            $installed = $prior
            Write-AtomicJson (Join-Path $root 'rollback-hold.json') ([ordered]@{version=$prior.version;feed_version=$blockedVersion})
            $result.status='ROLLED_BACK'
        } else {
            $manifest=$null
            try {
                $feed = Assert-PlainPath $FeedRoot
                $manifest = Test-Manifest (Read-Json (Join-Path $feed 'latest.json'))
                $result.feed_available=$true
            } catch {
                if (!$installed) { throw 'The update folder is unavailable or invalid, and no game is installed yet.' }
                $result.status='OFFLINE_CURRENT'
                $result.warning='Could not check updates. Using the installed build; your partner may have a newer version.'
            }
            $held = $false
            $holdPath = Join-Path $root 'rollback-hold.json'
            if ($manifest -and (Test-Path -LiteralPath $holdPath)) {
                $hold = Read-Json $holdPath
                # Keep a rolled-back build until the publisher selects a different build.
                if ($installed -and $hold.version -eq $installed.version -and $hold.feed_version -eq $manifest.version) { $held=$true;$result.status='ROLLBACK_HELD' }
            }
            if ($manifest -and !$held -and (!$installed -or $installed.version -cne $manifest.version)) {
                Assert-GameClosed $game
                $stageName='Staging-'+[Guid]::NewGuid().ToString('N')
                $stage=Resolve-Child $root $stageName
                [IO.Directory]::CreateDirectory($stage) | Out-Null
                try {
                    $archiveSource=Resolve-Child $feed $manifest.archive
                    $null=Assert-PlainPath $archiveSource
                    $archive=Join-Path $stage 'download.zip'
                    Copy-Item -LiteralPath $archiveSource -Destination $archive
                    if ((Get-Item -LiteralPath $archive).Length -ne [long]$manifest.archive_size -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $manifest.archive_sha256) { throw 'Downloaded update checksum does not match.' }
                    $payload=Join-Path $stage 'Payload'
                    [IO.Directory]::CreateDirectory($payload) | Out-Null
                    Expand-VerifiedPayload $archive $payload $manifest
                    Write-AtomicJson (Join-Path $payload 'installed.json') $manifest
                    Assert-GameClosed $game
                    if (Test-Path -LiteralPath $previous) { $null=Get-Installed $previous;Remove-OwnedChild $root 'Previous' }
                    $movedOld=$false
                    try {
                        if ($installed) { Move-Item -LiteralPath $game -Destination $previous;$movedOld=$true }
                        Move-Item -LiteralPath $payload -Destination $game
                    } catch {
                        if ($movedOld -and !(Test-Path -LiteralPath $game)) { Move-Item -LiteralPath $previous -Destination $game }
                        throw
                    }
                    $installed=$manifest
                    $result.status='UPDATED'
                    if (Test-Path -LiteralPath $holdPath) { Remove-OwnedChild $root 'rollback-hold.json' }
                } finally { Remove-OwnedChild $root $stageName }
            }
        }
        if (!$installed) { throw 'No complete installed game is available.' }
        Confirm-Payload $game $installed -CriticalOnly
        $result.version=$installed.version
        Write-AtomicJson (Join-Path $root 'last-update.json') $result
        if (!$NoLaunch) {
            Assert-GameClosed $game
            if ($result.warning) { Write-Host $result.warning -ForegroundColor Yellow }
            Write-Host ('IRON SUN / build '+$installed.version)
            $windows=Join-Path $game 'Windows'
            Start-Process -FilePath (Join-Path $windows 'TP_FirstPerson.exe') -WorkingDirectory $windows -ArgumentList '/Game/Variant_Shooter/Lvl_Shooter?RidgefireMenu' -WindowStyle Normal
        }
        return [pscustomobject]$result
    } finally { if ($lock) {$lock.Dispose()} }
}

function Publish-RidgefireUpdate {
    param([Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$FeedRoot,[Parameter(Mandatory)][string]$ArtifactManifest,[string]$ExistingZip='')
    $package = Assert-PlainPath $PackageRoot
    $feed = Assert-PlainPath $FeedRoot
    if ($feed -eq [IO.Path]::GetPathRoot($feed).TrimEnd('\') -or $feed -eq $package -or $feed.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Choose a separate dedicated update feed folder.' }
    $info = Read-Json (Join-Path $package 'PackageInfo.json')
    if ($info.Status -cne 'COMPLETE' -or $info.Configuration -cne 'Shipping' -or $info.ProductStatus -cne 'Prototype' -or $info.Executable -cne 'Windows/TP_FirstPerson.exe') { throw 'Only a COMPLETE Shipping Prototype package can be published.' }
    $proof = Read-Json $ArtifactManifest
    $windows = Join-Path $package 'Windows'
    foreach ($required in $script:RequiredFiles) {
        $relative=$required.Substring('Windows/'.Length)
        $entries=@($proof.artifacts | Where-Object {$_.path -ceq $relative})
        if ($entries.Count -ne 1) { throw 'Recorded package evidence lacks a required artifact.' }
        $actual=Resolve-Child $windows $relative
        $null=Assert-PlainPath $actual
        if ((Get-Item -LiteralPath $actual).Length -ne [long]$entries[0].size_bytes -or (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash -ne $entries[0].sha256) { throw 'Package does not match recorded tested artifacts.' }
    }
    $version = Split-Path $package -Leaf
    if ($version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Package directory is not a valid build identifier.' }
    [IO.Directory]::CreateDirectory($feed) | Out-Null
    $feedMarker = Join-Path $feed 'managed-feed.json'
    if (Test-Path -LiteralPath $feedMarker) {
        $owner=Read-Json $feedMarker
        if($owner.app_id -cne $script:AppId -or $owner.root -ine $feed){throw 'Feed ownership marker does not match.'}
    } else {
        if(@(Get-ChildItem -LiteralPath $feed -Force).Count){throw 'Choose an empty dedicated feed folder.'}
        Write-AtomicJson $feedMarker ([ordered]@{app_id=$script:AppId;root=$feed;schema_version=1})
    }
    $lock=$null
    try {
        try {$lock=[IO.File]::Open((Join-Path $feed 'publish.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'Another publisher is using this update feed.'}
        $inventory=@()
        foreach ($file in Get-ChildItem -LiteralPath $windows -Recurse -File) {
            $null=Assert-PlainPath $file.FullName
            $relative='Windows/'+$file.FullName.Substring($windows.Length+1).Replace('\','/')
            $inventory += [ordered]@{path=$relative;size=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
        }
        $archiveName='iron-sun-'+$version+'.zip'
        $temporaryName='Publishing-'+[Guid]::NewGuid().ToString('N')
        $temporary=Resolve-Child $feed $temporaryName
        [IO.Directory]::CreateDirectory($temporary) | Out-Null
        try {
            $zipPath=Join-Path $temporary $archiveName
            if ($ExistingZip) {Copy-Item -LiteralPath (Assert-PlainPath $ExistingZip) -Destination $zipPath}
            else {
                $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
                try {foreach($file in $inventory){$null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Resolve-Child $package $file.path),$file.path,[IO.Compression.CompressionLevel]::Optimal)}}finally{$zip.Dispose()}
            }
            $manifest=[ordered]@{schema_version=1;app_id=$script:AppId;version=$version;build_time_utc=[string]$info.BuildTimeUtc;published_at_utc=[DateTime]::UtcNow.ToString('o');archive=$archiveName;archive_size=(Get-Item -LiteralPath $zipPath).Length;archive_sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash;files=$inventory;validation='Original executable/content hashes match the explicitly supplied dated package evidence; this is an internal prototype, not beta approval.'}
            $null=Test-Manifest $manifest
            $verify=Join-Path $temporary 'Verify'
            [IO.Directory]::CreateDirectory($verify) | Out-Null
            Expand-VerifiedPayload $zipPath $verify $manifest
            $final=Resolve-Child $feed $archiveName
            if (Test-Path -LiteralPath $final) {
                if ((Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash -ne $manifest.archive_sha256) { throw 'A different archive already uses this build identifier.' }
            } else { Move-Item -LiteralPath $zipPath -Destination $final }
            Write-AtomicJson (Join-Path $feed ('manifest-'+$version+'.json')) $manifest
            Write-AtomicJson (Join-Path $feed 'latest.json') $manifest
            return [pscustomobject]@{status='PUBLISHED_LOCAL_FEED';version=$version;feed_root=$feed;archive=$final;archive_sha256=$manifest.archive_sha256;file_count=$inventory.Count;network_shared=$false}
        } finally { Remove-OwnedChild $feed $temporaryName }
    } finally {if($lock){$lock.Dispose()}}
}
function Install-RidgefireLauncher {
    param([Parameter(Mandatory)][string]$FeedRoot,[Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$ToolsRoot,[switch]$DesktopShortcut)
    $root=Get-OwnedRoot $InstallRoot
    $tools=Join-Path $root 'Tools'
    [IO.Directory]::CreateDirectory($tools) | Out-Null
    foreach($name in @('RidgefireUpdate.psm1','Update-IRON-SUN.ps1','Configure-LANFirewall.ps1')){
        $source=Join-Path $ToolsRoot $name
        $target=Join-Path $tools $name
        $null=Assert-PlainPath $source
        if([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $source -Destination $target -Force}
    }
    $feed=Assert-PlainPath $FeedRoot
    Write-AtomicJson (Join-Path $root 'client.json') ([ordered]@{schema_version=1;app_id=$script:AppId;feed_root=$feed})
    $launcher='@echo off'+"`r`n"+'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Update-IRON-SUN.ps1"'+"`r`n"+'if errorlevel 1 pause'+"`r`n"
    [IO.File]::WriteAllText((Join-Path $root 'Play-IRON-SUN.cmd'),$launcher,[Text.Encoding]::ASCII)
    $rollback='@echo off'+"`r`n"+'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Update-IRON-SUN.ps1" -Rollback -NoLaunch'+"`r`n"+'pause'+"`r`n"
    [IO.File]::WriteAllText((Join-Path $root 'Rollback-IRON-SUN.cmd'),$rollback,[Text.Encoding]::ASCII)
    $update=Invoke-RidgefireUpdate -FeedRoot $feed -InstallRoot $root -NoLaunch
    $shortcut=$null
    if($DesktopShortcut){
        $shortcut=Join-Path ([Environment]::GetFolderPath('Desktop')) 'IRON SUN.lnk'
        $shell=New-Object -ComObject WScript.Shell
        try{
            $link=$shell.CreateShortcut($shortcut)
            if((Test-Path -LiteralPath $shortcut) -and $link.TargetPath -ine (Join-Path $root 'Play-IRON-SUN.cmd')){throw 'IRON SUN.lnk belongs to another install; refusing to replace it.'}
            $link.TargetPath=Join-Path $root 'Play-IRON-SUN.cmd'
            $link.WorkingDirectory=$root
            $link.IconLocation=Join-Path $root 'Game\Windows\TP_FirstPerson.exe'
            $link.Description='IRON SUN - check approved LAN updates before playing'
            $link.Save()
        } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
    }
    return [pscustomobject]@{status='INSTALLED';version=$update.version;install_root=$root;launcher=(Join-Path $root 'Play-IRON-SUN.cmd');shortcut=$shortcut;stable_runtime=(Join-Path $root 'Game\Windows\Ridgefire\Binaries\Win64\TP_FirstPerson-Win64-Shipping.exe');feed_root=$feed;game_launched=$false;firewall_changed=$false}
}
Export-ModuleMember -Function Invoke-RidgefireUpdate,Publish-RidgefireUpdate,Install-RidgefireLauncher
