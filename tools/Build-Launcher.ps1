param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$csc=Join-Path $framework 'csc.exe'
if(!(Test-Path -LiteralPath $csc)){throw 'Windows .NET Framework compiler is unavailable.'}
$output=Join-Path $root 'build/IronSunLauncher.exe'
[IO.Directory]::CreateDirectory((Split-Path $output))|Out-Null
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/warn:4',('/out:'+$output),('/win32manifest:'+(Join-Path $root 'src/app.manifest')))
foreach($reference in @('System.dll','System.Core.dll','System.Net.Http.dll','System.Web.Extensions.dll','System.Security.dll','System.Xaml.dll')){$arguments+=('/reference:'+(Join-Path $framework $reference))}
foreach($reference in @('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll')){$arguments+=('/reference:'+(Join-Path $framework ('WPF/'+$reference)))}
foreach($name in @('RidgefireUpdate.psm1','InternetFeed.psm1','InternetUpdate.ps1','ReleasePublicKey.xml')){$arguments+=('/resource:'+(Join-Path $root ('src/'+$name))+','+$name)}
$arguments+=('/resource:'+(Join-Path $root 'assets/arena-preview.png')+',arena-preview.png')
$arguments+=(Join-Path $root 'src/IronSunLauncher.cs')
& $csc @arguments
if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed.'}
[ordered]@{built=$true;version='1.0.0';executable=$output;size_bytes=(Get-Item -LiteralPath $output).Length;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}|ConvertTo-Json
