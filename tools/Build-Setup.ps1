param(
 [string]$IsccPath=(Join-Path $PSScriptRoot '../../../tools/vendor/inno-setup/ISCC.exe')
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher=Join-Path $root 'build/IronSunLauncher.exe'
if(!(Test-Path -LiteralPath $IsccPath)){throw 'Install the official Inno Setup compiler, then supply -IsccPath.'}
if(!(Test-Path -LiteralPath $launcher)){throw 'Build the launcher first. Do not restore a quarantined file or bypass Windows protection.'}
# A security-blocked payload must fail here, before packaging. Building an installer is not clearance.
$hash=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash
$parts=[Diagnostics.FileVersionInfo]::GetVersionInfo($launcher).FileVersion.Split('.')
$version=$parts[0..2]-join '.'
& $IsccPath ('/DLauncherVersion='+$version) (Join-Path $root 'installer/IronSun.iss')
if($LASTEXITCODE -ne 0){throw 'Windows setup compilation failed. Do not disable antivirus or use exclusions.'}
$output=Join-Path $root 'build/setup/IRON-SUN-Setup.exe'
[ordered]@{built=$true;version=$version;executable=$output;size_bytes=(Get-Item -LiteralPath $output).Length;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;launcher_sha256=$hash;distribution_approved=$false;scope='Setup compilation only; protected download, install, opening and uninstall must pass before publication.'}|ConvertTo-Json
