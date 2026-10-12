# IRON SUN Launcher

Windows launcher for the IRON SUN internal playtest. A small per-user application installs the complete game, checks signed releases over HTTPS, preserves saves, and offers repair/rollback. Launcher updates are signed and applied after the old launcher exits. No game-server invite, GitHub token, or private signing key is distributed.

Download page: https://iron-sun-playtest.wilcoxwarrior4577.chatgpt.site

**Release status: internal-alpha setup accepted for publication.** Microsoft’s analyst removed the detection for the exact native 1.0.1 launcher. The portal’s final field still says Pending. The unchanged launcher and production setup pass fresh Defender scans with protection enabled, real installation/open/uninstall/reinstall, the real signed HTTPS VS60 download/current checks, all 32 installed file hashes and bounded installed game startup. Normal launcher-button interaction and a fresh friend-PC flow remain unverified after app-control denial. This scoped alpha acceptance preserves those limitations. The owner desktop retains its existing LAN shortcut and has a separate IRON SUN Launcher shortcut.

## Players

Download **IRON-SUN-Setup.exe** from the playtest page and open it once. Obtain the server address/invite privately from the host. The separately labeled game ZIP remains a manual fallback; extract its complete folder and keep `Windows/TP_FirstPerson.exe` beside all included files.

Setup installs **IRON SUN Launcher** for the current Windows account, adds it to the Start menu, offers a desktop shortcut, and opens it when **Open IRON SUN Launcher** remains selected at the end. Select **Create a desktop shortcut** if wanted. In the launcher, choose **Install IRON SUN**, then **Play**. No game ZIP or updater metadata needs to be opened by a friend. The browser requires the user to open the installer once.

The launcher checks published updates when opened and every ten minutes while idle. Running games are never replaced. Both co-op players must use a compatible game build. Uninstall **IRON SUN Launcher** through Windows Installed Apps; game files and saves are retained. The setup shortcut is named `IRON SUN Launcher` and does not replace the owner's existing `IRON SUN` LAN shortcut.

The first launcher is not Authenticode signed; Windows may show an unknown-publisher prompt. Releases and payloads are cryptographically verified against the embedded release key after initial download. Download only from the official page/release.

## Build

```powershell
./tools/Build-Launcher.ps1
./tests/Update-Integration.ps1
./tools/Build-Setup.ps1
./tests/Setup-Integration.ps1
```

Targets Windows x64 with the system .NET Framework/WPF. The distributed application uses native C# for HTTPS, signature verification, downloads, ZIP extraction, install swaps, repair, rollback and its own updates. It does not embed or execute PowerShell. PowerShell is used only for the owner's build, tests and publisher tools. No third-party runtime or package restore is required.

Windows setup is built with the official [Inno Setup](https://jrsoftware.org/) compiler. Supply `-IsccPath` if it is installed elsewhere. Setup uses no administrator privileges, validates installation ownership and refuses linked/foreign folders. It preserves a newer self-updated launcher if an older setup is run again. `Setup-Integration.ps1` compiles the real setup with an inert test executable, verifies its per-user registration, shortcuts, repair, uninstall, save retention and downgrade behavior, and compiles production directives without installing the blocked production payload. A fixture pass does not clear real launcher distribution.

Run `./tests/Launcher-SelfUpdate.ps1` to validate replacement and reopening with a signed fixture. This owner-only test uses the existing protected publishing identity; it does not publish the fixture version.

## Publish a tested game

`tools/Publish-InternetRelease.ps1` requires a COMPLETE Shipping package, its recorded artifact hashes, the approved local feed, and the native server's matching protocol. It verifies every player artifact, signs the game/launcher release manifests, uploads immutable assets to a GitHub draft, confirms remote asset sizes/hashes, and publishes only when all assets are present. The stable latest-release links update together. An ordinary source commit does not publish a game or alter the native server. Launcher-only releases use a new launcher version and can reuse the verified game package; tags include both identities.

```powershell
./tools/Publish-InternetRelease.ps1 `
  -PackageRoot 'C:/Users/YaYa/Documents/Codex/2026-09-22/connect-this-github-repo-to-a/unreal/Ridgefire/Saved/Packages/20261011-120705-452' `
  -ArtifactManifest 'C:/Users/YaYa/Documents/ChatGPT/FPS-1/research/lenovo-specs/server-access/vs58-package-artifacts.json' `
  -LocalFeed 'C:/Users/YaYa/Documents/ChatGPT/FPS-1/distribution/IRON-SUN-LAN' `
  -Protocol 58
```

Launcher publication requires `-DeliveryApproval <recorded-acceptance.json>` with exact launcher/setup SHA256 hashes and actual production evidence. Full-flow acceptance retains the normal Install/Play requirement. Explicitly requested internal-alpha delivery can instead record the analyst’s removed detection, fresh clean Defender scans with protection enabled, real protected install/open/uninstall, live HTTPS game download/current, installed file verification and bounded game startup. It keeps unverified normal-button and friend-PC fields false. `tools/Delivery-Policy.ps1` rejects incomplete evidence or changed binaries; `tests/Delivery-Policy.ps1` covers both routes without keys/network. Start from `installer/delivery-acceptance.example.json`, which is an unapproved template. After promotion, the website verifies the signed setup feed and exact release asset. The feed’s `security_review_status=ACCEPTED` means publisher security acceptance; `security_review_basis` preserves the actual analyst disposition and `delivery_scope` preserves the validation level. It does not mean Microsoft portal completion or beta approval. `-PrepareOnly` cannot create accepted delivery metadata.

For a new game release, replace these inputs with the new tested package and its proof, and deploy its matching server first. For a launcher change, increment the launcher version and assembly versions, run both test scripts, commit/push the exact source and then publish. `-PrepareOnly` prepares signed local metadata without uploading or promoting anything. Published tags are immutable. Drafts interrupted during upload can be resumed.

The owner private release-signing key is DPAPI-protected under `%LOCALAPPDATA%/IRON SUN Publishing`, outside this repository. Keep a separately protected owner backup before moving development machines. Only `src/ReleasePublicKey.xml` is shipped. Do not create a new signing identity for an ordinary update.

`-GameOnly` publishes only the verified ZIP and signed game metadata, without opening or uploading the blocked launcher. It is a temporary manual distribution path. Normal launcher publication remains a separate release gate.

## Validation boundaries

`tests/Update-Integration.ps1` drives the actual compiled native C# updater with RSA-signed local fixtures, covering install/current/update, repair, rollback/hold, unsigned metadata, malicious paths, corrupted downloads, foreign folders, saved-progress preservation and interrupted swaps. Live hosted download/install and actual game launch are recorded separately in the game checkout's dated beta-readiness snapshots. Website/native rendering, same-PC smoke, physical PCs and human gameplay remain distinct evidence levels.

The initial 1.0.0 download was blocked by Defender (`Trojan:Win32/Sabsik.TE.A!ml`) before execution and its release was withdrawn to draft. Version 1.0.1 replaces its embedded script updater with the native implementation. Never disable endpoint protection or add exclusions to install a release. A successful test on the development PC does not guarantee every friend's antivirus or organizational policy will accept an unsigned application.
