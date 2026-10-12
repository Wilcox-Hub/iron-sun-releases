# IRON SUN publisher signing plan

Prepared October 12, 2026. This is a reviewable implementation plan, not a signing completion record. No paid resource, account, certificate, identity submission, legal agreement, source/version change, build or public release is authorized by this document.

**Owner decision, October 12:** keep unsigned internal-alpha distribution, with no approval for further costs. This plan is deferred reference material. Do not provision a paid signing account, purchase a certificate or start identity onboarding without a new explicit request.

## Current problem and evidence

The owner reports that SmartScreen prevented `IRON-SUN-Setup (2).exe` from starting with **Unknown publisher**. The downloaded file matches the published installer SHA256 `62C789A0ABD26F2CA127635AD61FDE7B41537AAD31C4C29A2D54FF754464C9F8`; its Windows Authenticode status is `NotSigned`. Native launcher 1.0.1 is also unsigned. These checks establish file identity and missing publisher signing; they do not reproduce SmartScreen's reputation verdict or establish safety.

Microsoft's analyst removed the earlier Defender Antivirus detection for the reviewed launcher; the submission's final field remains Pending in the latest recorded portal evidence. Antivirus detection removal and SmartScreen reputation are separate. No Microsoft certification or normal friend-PC first-run acceptance is claimed. [Microsoft developer FAQ](https://learn.microsoft.com/en-us/defender-xdr/developer-faq)

The launcher already verifies RSA-signed game/launcher metadata, payload SHA256, sizes and versions. The website also verifies the RSA-signed setup feed. That release identity protects our update channel; it is not a publicly trusted Authenticode certificate on the executables. Preserve both protections when adding Windows publisher signing.

## Proposed service and approval boundary

Use **Microsoft Azure Artifact Signing, Public Trust, Basic** if the owner's legal identity is eligible and the owner approves payment and identity onboarding. The official product FAQ lists Basic at **US$9.99/month**, with 5,000 signatures and additional signatures at $0.005 each. Reconfirm the actual region, currency, taxes and displayed subscription price before creating a billable resource. This service choice is a project recommendation, not a guarantee of immediate SmartScreen clearance. [Microsoft product and pricing FAQ](https://azure.microsoft.com/en-us/products/artifact-signing), [pricing page](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/)

The service requires a paid Azure subscription. Public Trust individual onboarding is available in the United States and Canada, uses government ID/mobile verification, and requires an Individual billing account whose legal name/address match the documents. Organizations have a separate validation route. An individual certificate exposes validated identity fields; it cannot arbitrarily name the publisher `IRON SUN`. Confirm whether to use the owner's personal identity or an eligible legal business before proceeding. The account resource can incur charges while validation is incomplete, and the monthly fee is not prorated. [Setup and identity validation](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart), [Artifact Signing FAQ](https://learn.microsoft.com/en-us/azure/artifact-signing/faq)

Required user decisions remain unresolved: legal publisher identity, eligible billing account, recurring cost, and approval for identity submission/account onboarding. Existing approval for Microsoft's malware sample review does not authorize these separate actions. This plan precedes approval; no signing code/build changes are planned until legitimate publisher onboarding is available.

Once approved, configure a Public Trust account/profile in a supported region with minimum signing permissions. Use the supported SignTool integration and an authenticated signing session; keep keys, tokens, credentials and identity documents outside repositories, release assets and logs. Timestamp every signed artifact because service certificates are short lived. [Microsoft signing integrations](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations)

## Required implementation and release order

1. **Preserve the current release.** Keep the published unsigned 1.0.1 artifacts and their historical evidence immutable. A new signed file has different bytes/hash and needs new scans and delivery evidence. Do not replace assets under an existing public tag.
2. **Add one owner build signing helper.** Accept a configured SignTool/service profile and explicit executable path; fail on signing or timestamp errors. Verify Windows Authenticode trust and the expected validated publisher after signing. Use SHA256 file/timestamp digests. Do not silently fall back to unsigned output, and do not put private credentials in arguments, source or logs. Public signature metadata may be recorded.
3. **Version the launcher.** Change `AssemblyVersion`, `AssemblyFileVersion` and `Settings.LauncherVersion` in `src/IronSunLauncher.cs` together to the next unused release version, expected 1.0.2. `installer/IronSun.iss` must resolve the same version. An installed 1.0.1 launcher only accepts a higher version; signing 1.0.1 without a bump would not deliver through self-update and would collide with the current publisher's tag formula.
4. **Compile, then sign the launcher.** Invoke the helper in `tools/Build-Launcher.ps1` after successful compilation and before reporting final size/SHA256. Nothing may rewrite a signed binary afterward. Keep the embedded RSA public key unchanged for this ordinary release.
5. **Compile signed setup and uninstaller.** Configure an explicitly named Inno `SignTool` in `tools/Build-Setup.ps1`/`installer/IronSun.iss`, with `SignedUninstaller=yes`. Supply the already signed launcher payload. Inno can sign setup and its generated uninstaller through the same configured signing helper. Merely signing the outer setup afterward would leave the bundled launcher/uninstaller unsigned. Verify final setup before recording its hash. [Inno SignTool](https://jrsoftware.org/ishelp/topic_setup_signtool.htm), [SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm), [compiler signing configuration](https://jrsoftware.org/ishelp/topic_compilercmdline.htm)
6. **Verify final signed artifacts and production delivery.** Record the final setup/launcher identities and verify the installed launcher and `unins*.exe`. Run protected Defender scans and focused installer/save-retention/uninstall/reinstall checks. Exercise the actual launcher Install/Play buttons and full live game install/current paths; retain the original scope limitations where interaction is unavailable. A fixture pass cannot substitute for production acceptance.
7. **Verify a signed self-update.** `src/NativeSelfUpdate.cs` already authenticates RSA metadata and exact bytes/version before activation and again before replacement. Publish only a properly Authenticode-signed higher-version payload. Its final signed hash/size must appear in the RSA-signed launcher manifest. Confirm replacement/reopening, retained previous binary and valid signature of the activated file. No runtime behavior change is necessary just to preserve signed bytes. If runtime Authenticode enforcement is added separately, use Windows trust validation and plan publisher/certificate rotation; Artifact Signing uses short-lived certificates, so a fixed leaf-certificate thumbprint is not a durable identity policy.
8. **Gate publication on final evidence.** Extend `tools/Delivery-Policy.ps1` and `tools/Publish-InternetRelease.ps1` to require current signature evidence for signed releases, with exact setup/launcher hashes and publisher identity. Keep production checks and existing full-flow/explicit internal-alpha scopes distinct. Update `installer/delivery-acceptance.example.json` and focused policy tests accordingly. Old antivirus approval must not be automatically assigned to changed signed bytes.
9. **Create RSA metadata last.** After signing, verification and delivery acceptance, generate the launcher/setup manifests and their existing RSA signatures over final signed artifact sizes/hashes. `tools/Publish-SetupFeed.ps1` should retain its envelope and remote asset checks. Only then upload to a new immutable draft, verify remote digests, promote it, and update the signed public setup feed. Reuse the unchanged, verified game package only while its input/artifact evidence still matches and its protocol matches the live server.
10. **Measure the actual first run.** Download through the public page in a normal browser on a protected Windows friend PC, open setup normally, and record the displayed publisher, any SmartScreen decision, installation/shortcut behavior, launcher Install/Play and normal co-op startup. Update dated readiness evidence and the latest pointer with the observed validation level. Never turn signature validity into an assumed SmartScreen pass.

Signing the game executables is a separate future artifact change if chosen. It would also change package hashes and require new package/archive proof and manifests; the current game evidence cannot automatically cover those modified files.

## Evidence to save

For each final artifact, retain release/version, exact filename, size, SHA256, successful signature verification, validated public publisher/issuer details and timestamp evidence. Record tool/service versions and source input identities, without private credentials. Installed launcher/uninstaller verification should identify the corresponding installed hashes. New delivery records must preserve these separately:

- Defender scan/protection status and date.
- Actual protected browser download/open and observed SmartScreen result.
- Production installation, shortcuts, launcher opening and uninstall/save-retention.
- Normal launcher Install/Play, live game install/current/repair checks and installed hashes.
- Signed self-update activation/reopening, rollback file and activated signature.
- Physical friend-PC and human gameplay acceptance, which remain separate from build/backend tests.

The current 1.0.1 owner SmartScreen failure remains dated history. A new signed release should clearly report which checks passed and which remain unperformed; do not claim a higher game-readiness score merely because publisher signing is added.

## Expected result and uncertainty

A valid Authenticode signature supplies a verified publisher identity and supports reputation across releases. A new signed executable can still trigger SmartScreen while reputation develops; current Microsoft guidance says EV signing does not automatically bypass the warning. There is no verified exact time, usage threshold or guaranteed warning-free percentage. [Microsoft SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)

No self-signed root distribution, protection changes or warning-bypass workflow is part of this plan. If a newly signed release still warns, record the result and follow Microsoft's supported review/support process; keep first-run acceptance open.

Supporting primary-source research: [SmartScreen and signing options](https://github.com/Wilcox-Hub/fps-game/blob/main/docs/beta-readiness/snapshots/2026-10-12-launcher-smartscreen/evidence/signing-options.md).
