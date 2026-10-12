param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$SignaturePath,[Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference='Stop'
$repo='Wilcox-Hub/iron-sun-releases';$gh='C:/Program Files/GitHub CLI/gh.exe'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bytes=[IO.File]::ReadAllBytes($ManifestPath);$signature=[IO.File]::ReadAllBytes($SignaturePath)
$rsa=[Security.Cryptography.RSACryptoServiceProvider]::new();$rsa.PersistKeyInCsp=$false
try {
 $rsa.FromXmlString([IO.File]::ReadAllText((Join-Path $root 'src/ReleasePublicKey.xml')))
 if(!$rsa.VerifyData($bytes,'SHA256',$signature)){throw 'Setup feed signature did not verify.'}
} finally {$rsa.Dispose()}
$m=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
if($m.app_id -cne 'IRON-SUN-SETUP' -or $m.security_review_status -cne 'ACCEPTED' -or $m.delivery_verified -ne $true){throw 'Only accepted production setup delivery can enter the public feed.'}
$release=(& $gh api ('repos/'+$repo+'/releases/tags/'+$Tag)|Out-String)|ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or $release.draft -or $release.prerelease){throw 'Setup release is not publicly published.'}
$asset=@($release.assets|Where-Object name -ceq 'IRON-SUN-Setup.exe')
if($asset.Count -ne 1 -or $m.filename -cne 'IRON-SUN-Setup.exe' -or $m.url -cne ('https://github.com/'+$repo+'/releases/download/'+$Tag+'/IRON-SUN-Setup.exe') -or $asset[0].browser_download_url -cne $m.url -or $asset[0].size -ne $m.size_bytes -or $asset[0].digest -cne ('sha256:'+$m.sha256.ToLowerInvariant())){throw 'Published setup asset does not match its signed delivery metadata.'}
$feedPath='public/setup-feed.json'
$existing=& $gh api ('repos/'+$repo+'/contents/'+$feedPath) 2>$null
$old=$null;if($LASTEXITCODE -eq 0){$old=($existing|Out-String)|ConvertFrom-Json}
$envelope=[ordered]@{schema_version=1;manifest_base64=[Convert]::ToBase64String($bytes);signature_base64=[Convert]::ToBase64String($signature)}
$content=[Text.Encoding]::UTF8.GetBytes(($envelope|ConvertTo-Json))
$body=[ordered]@{message=('Publish verified Windows setup feed for '+$Tag);branch='main';content=[Convert]::ToBase64String($content)}
if($old){$body.sha=$old.sha}
$inputPath=Join-Path (Split-Path $ManifestPath) 'setup-feed-api-input.json'
[IO.File]::WriteAllText($inputPath,($body|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$response=(& $gh api --method PUT ('repos/'+$repo+'/contents/'+$feedPath) --input $inputPath|Out-String)|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw 'Setup release is published but the website feed update failed; the download button remains withheld. Retry this helper with the same signed metadata.'}
[ordered]@{published=$true;feed_path=$feedPath;commit=$response.commit.sha;setup_sha256=$m.sha256;scope='Small signed public metadata only; no private key, invite or token uploaded.'}|ConvertTo-Json
