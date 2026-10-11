param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $project ('test-output/self-update-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$next=Join-Path $run 'next-source'
foreach($folder in @('src','assets','tools')){[IO.Directory]::CreateDirectory((Join-Path $next $folder))|Out-Null}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $project 'src') -File){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $next ('src/'+$file.Name))}
Copy-Item -LiteralPath (Join-Path $project 'assets/arena-preview.png') -Destination (Join-Path $next 'assets/arena-preview.png')
Copy-Item -LiteralPath (Join-Path $project 'tools/Build-Launcher.ps1') -Destination (Join-Path $next 'tools/Build-Launcher.ps1')
$cpp=Join-Path $next 'src/IronSunLauncher.cs'
[IO.File]::WriteAllText($cpp,[IO.File]::ReadAllText($cpp).Replace('1.0.0','1.0.1'),[Text.UTF8Encoding]::new($false))
& (Join-Path $next 'tools/Build-Launcher.ps1')|Out-Null
$feed=Join-Path $run 'feed';[IO.Directory]::CreateDirectory($feed)|Out-Null
$nextExe=Join-Path $feed 'IronSunLauncher.exe';Copy-Item -LiteralPath (Join-Path $next 'build/IronSunLauncher.exe') -Destination $nextExe
$meta=@{schema_version=1;app_id='IRON-SUN-LAUNCHER';version='1.0.1';url='https://github.com/Wilcox-Hub/iron-sun-releases/releases/download/fixture/IronSunLauncher.exe';size_bytes=(Get-Item $nextExe).Length;sha256=(Get-FileHash $nextExe -Algorithm SHA256).Hash}
$key=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IRON SUN Publishing/release-signing.key'
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider;$rsa.PersistKeyInCsp=$false
try {
 $bytes=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($key),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($bytes));[Array]::Clear($bytes,0,$bytes.Length)
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($meta|ConvertTo-Json -Depth 5))
 [IO.File]::WriteAllBytes((Join-Path $feed 'launcher-manifest.json'),$bytes)
 [IO.File]::WriteAllBytes((Join-Path $feed 'launcher-manifest.sig'),$rsa.SignData($bytes,'SHA256'))
} finally {$rsa.Dispose()}
$install=Join-Path $run 'install'
$old=Join-Path $project 'build/IronSunLauncher.exe'
$process=Start-Process -FilePath $old -ArgumentList ('--install-root "'+$install+'" --fixture-feed "'+$feed+'" --self-update-test "'+$feed+'"') -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $run 'old-stderr.log') -RedirectStandardOutput (Join-Path $run 'old-stdout.log')
if(!$process.WaitForExit(15000)){throw 'Old launcher did not exit for update'}
if($process.ExitCode -ne 0){throw ('Old launcher update failed: '+[IO.File]::ReadAllText((Join-Path $run 'old-stderr.log')))}
$proof=Join-Path $install 'Launcher/launcher-update-result.json'
$image=Join-Path $install 'Launcher/updated-launcher.png'
$deadline=(Get-Date).AddSeconds(30)
while((Get-Date)-lt $deadline -and (!(Test-Path $proof) -or !(Test-Path $image))){Start-Sleep -Milliseconds 250}
if(!(Test-Path $proof) -or !(Test-Path $image)){throw 'Launcher update did not activate and render the next version'}
$result=Get-Content $proof -Raw|ConvertFrom-Json
$target=Join-Path $install 'Launcher/IronSunLauncher.exe';$previous=Join-Path $install 'Launcher/IronSunLauncher.previous.exe'
if($result.status -cne 'APPLIED' -or (Get-FileHash $target -Algorithm SHA256).Hash -cne $meta.sha256 -or (Get-FileHash $previous -Algorithm SHA256).Hash -cne (Get-FileHash $old -Algorithm SHA256).Hash){throw 'Launcher update file identities did not verify'}
if([Diagnostics.FileVersionInfo]::GetVersionInfo($target).FileVersion -cne '1.0.1.0'){throw 'Updated launcher version differs'}
[ordered]@{passed=$true;from='1.0.0';to='1.0.1';signed_metadata=$true;old_process_exited=$true;new_binary_activated=$true;previous_binary_retained=$true;new_window_rendered=$true;run=$run;scope='Actual compiled WPF launcher and post-exit update helper with a production-key-signed local fixture; no hosted launcher promotion.'}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $run 'result.json') -Encoding UTF8
Get-Content (Join-Path $run 'result.json') -Raw
