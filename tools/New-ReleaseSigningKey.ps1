param([string]$PublicKeyPath=(Join-Path $PSScriptRoot '../src/ReleasePublicKey.xml'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$folder=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IRON SUN Publishing'
[IO.Directory]::CreateDirectory($folder)|Out-Null
$path=Join-Path $folder 'release-signing.key'
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.PersistKeyInCsp=$false
try {
 if(Test-Path -LiteralPath $path){
  $bytes=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($bytes))
  [Array]::Clear($bytes,0,$bytes.Length)
 } else {
  $bytes=[Text.Encoding]::UTF8.GetBytes($rsa.ToXmlString($true))
  $protected=[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  [IO.File]::WriteAllBytes($path,$protected)
  [Array]::Clear($bytes,0,$bytes.Length)
 }
 [IO.File]::WriteAllText([IO.Path]::GetFullPath($PublicKeyPath),$rsa.ToXmlString($false),[Text.UTF8Encoding]::new($false))
 Write-Output 'Public release-verification key exported. Private signing key is protected for this Windows user outside the repositories.'
} finally {$rsa.Dispose()}
