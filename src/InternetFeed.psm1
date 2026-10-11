Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

function Read-BoundedHttps([string]$Url,[int]$MaxBytes=16777216) {
 $uri=[Uri]$Url
 if(!$uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' -or $uri.UserInfo){throw 'Update metadata must use HTTPS.'}
 $handler=New-Object Net.Http.HttpClientHandler
 $client=New-Object Net.Http.HttpClient($handler)
 $client.Timeout=[TimeSpan]::FromSeconds(35)
 $client.DefaultRequestHeaders.UserAgent.ParseAdd('IronSunLauncher/1.0')
 try {
  $response=$client.GetAsync($uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  $response.EnsureSuccessStatusCode()|Out-Null
  if($response.RequestMessage.RequestUri.Scheme -cne 'https'){throw 'Update redirect left HTTPS.'}
  if($response.Content.Headers.ContentLength -gt $MaxBytes){throw 'Update metadata exceeds the supported size.'}
  $inputStream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
  $buffer=New-Object byte[] 65536
  $output=New-Object IO.MemoryStream
  try {
   while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
    if($output.Length+$count -gt $MaxBytes){throw 'Update metadata exceeds the supported size.'}
    $output.Write($buffer,0,$count)
   }
   return ,$output.ToArray()
  } finally {$output.Dispose();$inputStream.Dispose()}
 } finally {$client.Dispose();$handler.Dispose()}
}
function Confirm-SignedMetadata([byte[]]$Bytes,[byte[]]$Signature,[string]$PublicKeyPath) {
 $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
 $rsa.PersistKeyInCsp=$false
 try {
  $rsa.FromXmlString([IO.File]::ReadAllText($PublicKeyPath))
  if(!$rsa.VerifyData($Bytes,'SHA256',$Signature)){throw 'Release signature is invalid. No update was installed.'}
 } finally {$rsa.Dispose()}
 return ([Text.Encoding]::UTF8.GetString($Bytes)|ConvertFrom-Json)
}
function Get-SignedGameFeed {
 param([string]$FeedUrl,[string]$PublicKeyPath,[string]$FixtureRoot='')
 if($FixtureRoot){
  $bytes=[IO.File]::ReadAllBytes((Join-Path $FixtureRoot 'game-manifest.json'))
  $signature=[IO.File]::ReadAllBytes((Join-Path $FixtureRoot 'game-manifest.sig'))
 } else {
  $bytes=Read-BoundedHttps $FeedUrl
  $signature=Read-BoundedHttps ($FeedUrl.Substring(0,$FeedUrl.Length-'.json'.Length)+'.sig') 1024
 }
 $manifest=Confirm-SignedMetadata $bytes $signature $PublicKeyPath
 if(!$manifest.PSObject.Properties['protocol'] -or [int]$manifest.protocol -lt 58 -or !$manifest.PSObject.Properties['archive_url']){throw 'Release lacks game compatibility metadata.'}
 $url=[Uri]$manifest.archive_url
 if(!$url.IsAbsoluteUri -or $url.Scheme -cne 'https' -or $url.UserInfo){throw 'Game archive must use HTTPS.'}
 return [pscustomobject]@{manifest=$manifest;bytes=$bytes}
}
function Receive-VerifiedArchive {
 param($Manifest,[string]$Destination,[string]$FixtureRoot='',[scriptblock]$Progress)
 $full=[IO.Path]::GetFullPath($Destination)
 $partial=$full+'.partial'
 try {
  if($FixtureRoot){Copy-Item -LiteralPath (Join-Path $FixtureRoot $Manifest.archive) -Destination $partial -Force}
  else {
   $handler=New-Object Net.Http.HttpClientHandler
   $client=New-Object Net.Http.HttpClient($handler)
   $client.Timeout=[TimeSpan]::FromHours(3)
   $client.DefaultRequestHeaders.UserAgent.ParseAdd('IronSunLauncher/1.0')
   try {
    $response=$client.GetAsync([string]$Manifest.archive_url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode()|Out-Null
    if($response.RequestMessage.RequestUri.Scheme -cne 'https'){throw 'Game redirect left HTTPS.'}
    if($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -ne [long]$Manifest.archive_size){throw 'Game download length differs from the signed release.'}
    $inputStream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $output=[IO.File]::Open($partial,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer=New-Object byte[] 1048576
    $total=[long]0;$last=-1
    try {
     while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
      $total+=$count
      if($total -gt [long]$Manifest.archive_size){throw 'Game download exceeded its signed size.'}
      $output.Write($buffer,0,$count)
      $pct=[Math]::Floor(100.0*$total/[long]$Manifest.archive_size)
      if($pct -ne $last){$last=$pct;if($Progress){& $Progress ([int]$pct) $total}}
     }
    } finally {$output.Dispose();$inputStream.Dispose()}
   } finally {$client.Dispose();$handler.Dispose()}
  }
  if((Get-Item -LiteralPath $partial).Length -ne [long]$Manifest.archive_size -or (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $Manifest.archive_sha256){throw 'Downloaded game failed verification. The installed game was preserved.'}
  if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Force}
  Move-Item -LiteralPath $partial -Destination $full
 } finally {if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}}
}
Export-ModuleMember -Function Get-SignedGameFeed,Receive-VerifiedArchive,Confirm-SignedMetadata
