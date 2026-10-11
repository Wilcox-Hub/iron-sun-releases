# IRON SUN Launcher

Windows launcher for the IRON SUN internal playtest. A small per-user application installs the complete game, checks signed releases over HTTPS, preserves saves, and offers repair/rollback. Launcher updates are signed and applied after the old launcher exits. No game-server invite, GitHub token, or private signing key is distributed.

Download page: https://iron-sun-playtest.wilcoxwarrior4577.chatgpt.site

## Players

Download `IronSunLauncher.exe`, open it, and choose **Install IRON SUN**. The launcher creates an IRON SUN desktop shortcut. It checks published updates when opened and every ten minutes while idle. Running games are never replaced. Both co-op players must use a compatible game build. Obtain the server address/invite privately from the host.

The first launcher is not Authenticode signed; Windows may show an unknown-publisher prompt. Releases and payloads are cryptographically verified against the embedded release key after initial download. Download only from the official page/release.

## Build

```powershell
./tools/Build-Launcher.ps1
./tests/Update-Integration.ps1
```

Targets Windows x64 with the system .NET Framework/WPF and Windows PowerShell 5.1. No third-party runtime or package restore is required. The updater reuses the established `RidgefireUpdate.psm1` installation/swap/rollback core, with an HTTPS/signed-metadata layer.

## Publish a tested game

`tools/Publish-InternetRelease.ps1` requires a COMPLETE Shipping package, its recorded artifact hashes, the approved local feed, and the native server's matching protocol. It verifies every player artifact, signs the game/launcher release manifests, uploads immutable assets to a GitHub draft, confirms remote asset sizes/hashes, and publishes only when all assets are present. The stable latest-release links update together. An ordinary source commit does not publish a game or alter the native server.

The owner private release-signing key is DPAPI-protected under `%LOCALAPPDATA%/IRON SUN Publishing`, outside this repository. Keep a separately protected owner backup before moving development machines. Only `src/ReleasePublicKey.xml` is shipped. Do not create a new signing identity for an ordinary update.

## Validation boundaries

`tests/Update-Integration.ps1` drives the real Windows PowerShell update engine with RSA-signed local fixtures, covering install/current/update, repair, rollback/hold, unsigned metadata, malicious paths, corrupted downloads, foreign folders, saved-progress preservation and interrupted swaps. Live hosted download/install and actual game launch are recorded separately in the game checkout's dated beta-readiness snapshots. Website/native rendering, same-PC smoke, physical PCs and human gameplay remain distinct evidence levels.
