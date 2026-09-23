# easy-vphone

A native macOS GUI for [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), with an integrated App Store IPA library. The interface supports Turkish, English, German, French, Spanish, Italian, Portuguese, Russian, Japanese and Simplified Chinese. Settings provides System / Light / Dark appearance; language and theme changes apply immediately and persist across launches. Apple Silicon, macOS 15 or later.

## What it does

- Choose a storage directory on your Mac or an external SSD; discover existing VM bundles.
- Select an iOS build from the installed vphone-cli firmware catalog and its recommended cloudOS pairing, or choose local IPSWs / HTTPS sources.
- Install regular, developer, jailbreak or experimental variants; choose disk capacity and optional Frida support.
- Clone the upstream repository, prepare an isolated runtime, run firmware creation and resume the CFW stage from the GUI.
- Start / stop a selected VM; adjust CPU and RAM while it is stopped.
- Refresh Sileo/TrollStore app registration over SSH on jb/exp VMs. Regular/dev VMs are clearly identified as lacking those jailbreak apps.
- Open an SSH command session inside the app, with per-VM port/user settings and explicit USB/UDID routing.
- Search the App Store, download official IPAs, and install to the selected VM using its explicit UDID.
- Reuse the existing ipatool Keychain session. Login / 2FA is handled in an in-app interactive console; credentials are not placed in command arguments or saved by easy-vphone.
- Check host prerequisites and install Homebrew/dependencies from the GUI.

The virtual iPhone opens in vphone-cli's own display window. SSH provides a line-oriented console, not a full terminal emulator; use ordinary shell commands rather than full-screen TUI applications.

## Local use

Open `dist/easy-vphone.app`. In **Hazırlık**, run the checks, install dependencies and select full Xcode with an iOS SDK. In **Yeni VM kur**, choose your storage location, firmware and variant, then review and start the installation. Administration prompts and interactive replies appear inside the app or in the native macOS authentication dialog.

For an existing installation, select the parent of its `VMs` folder using **Dizin seç / mevcut VM ekle**. VM files remain in that directory. No migration or copying of the disk image is required.

Recovery security changes cannot be performed from a normal macOS GUI. The preparation screen explains upstream's debug-only SIP relaxation and research-guest permission, then provides the application-scoped amfidont action. The app does not change NVRAM, reboot the Mac, or modify the USB-connected physical iPhone.

## Build and tests

A full Xcode installation is recommended; `scripts/build.sh` discovers Xcode or respects `DEVELOPER_DIR`.

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/release.sh
```

Output: `dist/easy-vphone.app`, `dist/easy-vphone-0.3.0-arm64.zip`, checksums and a generated Homebrew cask. The app and distribution files contain no VM images, Apple credentials or downloaded IPAs.

## Homebrew distribution

Install the Apple Silicon build from the custom tap `dikeckaan/homebrew-easy-vphone`:

```sh
brew tap dikeckaan/easy-vphone
brew install --cask dikeckaan/easy-vphone/easy-vphone
```

**Version 0.3.0 is Apple Development signed, not notarized. Gatekeeper may block it on other Macs; it is a development preview, not a notarized public-distribution build.** See [packaging/RELEASE.md](packaging/RELEASE.md). A custom tap is separate from acceptance into the official `homebrew/cask` repository.

## Compatibility and limitations

- The bundled additional preset is iPhone17,3 / iOS 27.0 `24A437` with cloudOS 26.4 `23E5207q`. The firmware catalog comes from the installed upstream CLI. Not every listed pairing or jailbreak variant has been tested by this project.
- The virtual hardware can identify as iPhone99,11; selecting iPhone17,3 chooses the source firmware, not a physical hardware identity.
- Jailbreak does not decrypt FairPlay-protected App Store binaries. Download or installation success does not guarantee launch, login or runtime compatibility. vphone SEP limitations also affect Apple ID / iCloud.
- IPA installation uses `ideviceinstaller` and the selected VM's UDID. Guest pairing and valid installation signatures still matter; unsupported/unsigned packages may fail. This is not a replacement for upstream's built-in signer / TrollStore installer.
- `Power off` calls upstream `vm stop`: SIGINT first, then SIGKILL after 30 seconds if needed. The UI asks before doing so.
- CFW resume reruns the CFW stage; it is not a universal resume for interrupted firmware preparation or restore. Failed earlier stages may need a new VM name. VM files are never deleted automatically.
- Runtime fixes are guarded by the SHA-256 of the tested upstream patchers. Unknown upstream versions fail clearly instead of silently overwriting changed patchers. Signed vphone-cli.app resources are never modified.
- The default local build is ad-hoc signed. `SIGN_IDENTITY` can select an existing Apple Development identity for local development; this does not qualify as Developer ID distribution or notarization. Public, Gatekeeper-ready distribution requires a Developer ID certificate and notarization.

## Localization

`Resources/i18n/<language>.json` contains 198 stable keys per language. Numbered `{0}` placeholders support reordering without interpreting user values as format strings. Missing translations fall back to English. The locale resolver understands regional system languages. Application text is localized; external command output retains its original language. Tests verify complete key sets, placeholder parity and runtime rendering.

VM launch diagnostics are stored in `~/Library/Caches/io.github.easy-vphone/VMLogs/`. A VM started by easy-vphone can keep running when the manager exits.

## Updates and reliability

Version 0.3.0 checks GitHub release metadata on launch and at most every six hours while activating the app. A newer downloadable preview or stable release produces a persistent banner with a download link and a copyable Homebrew upgrade command. Settings has a manual check. There is no silent installation or restart.

**Users on 0.2.0 must upgrade once manually**: that version predates the updater and cannot display a new in-app notice. Run:

```sh
brew update
brew upgrade --cask dikeckaan/easy-vphone/easy-vphone
```

Downloads have a 30-minute timeout and a Stop button. Search/session/VM metadata calls have shorter bounded waits. The bundled native PTY helper permits initial Homebrew setup without Python already installed, and escalates cancellation for unresponsive tasks. A custom IPA folder survives relaunch and VM storage changes.

SSH and JB icon repair are forwarded exclusively to the selected VM UDID using `iproxy`. Guest port and username remain configurable; manual IP routing is removed. The VM must appear in usbmux. Failure never falls back to an attached physical device. SSH host keys are stored under a per-UDID alias.

## Validation for 0.3.0

Automated checks cover command timeout/cancellation, a PTY child ignoring SIGTERM, password echo suppression, native startup without Python on PATH, numeric version comparison, update asset URL validation, SSH identity validation, metric aggregation and stale-traffic preservation, plus the existing installer/runtime/i18n tests. A full fresh firmware restore and a new VM SSH connection have not been rerun as part of this release's verification.

## Credits

Based on the tools from [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), [ipatool](https://github.com/majd/ipatool), [libimobiledevice](https://libimobiledevice.org/) and [amfidont](https://github.com/zqxwce/amfidont). The copied/modified vphone patchers retain the upstream MIT license in `Resources/VPHONE-LICENSE`. Third-party binaries and Apple firmware are obtained separately, not redistributed here.

<!-- metrics:start -->
## Project statistics

Updated: **2026-09-23 12:24 UTC**. Counts are events, not installs or people.

| Metric | Count |
|---|---:|
| ZIP downloads across releases | 5 |
| Stars | 2 |
| Forks | 0 |
| Watchers | 0 |
| Open issues + pull requests | 0 |
| Clones, last 14-day snapshot | 69 |
| Unique cloners, same snapshot | 38 |
| Page views, last 14-day snapshot | 12 |
| Unique visitors, same snapshot | 6 |

[Detailed release downloads, daily clone/view history and collection timestamps](METRICS.md).
GitHub does not expose unique downloaders. Clone/view uniqueness is limited to the reported window; daily uniques must not be summed as people.
Automated builds and verification downloads can contribute to these counters.
<!-- metrics:end -->
