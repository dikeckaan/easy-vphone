# Release checklist

The default repository is `dikeckaan/easy-vphone`, the tap repository is `dikeckaan/homebrew-easy-vphone`.

1. Run tests and review the source tree. Do not include VM files, account state, IPA files, private keys or local logs.
2. For public distribution, set `SIGN_IDENTITY` to your Developer ID Application signing identity and `NOTARY_PROFILE` to an existing `notarytool` Keychain profile. Credentials stay in the Keychain.
3. Run `VERSION=0.3.0 bash scripts/release.sh`. This compiles, signs, optionally notarizes/staples, archives, calculates SHA-256 and generates `dist/homebrew-easy-vphone/Casks/easy-vphone.rb`. No network publishing occurs.
4. Publish source to `dikeckaan/easy-vphone`, tag `v0.3.0`, and attach `dist/easy-vphone-0.3.0-arm64.zip` and `dist/SHA256SUMS` to that GitHub release.
5. Copy the generated `Casks/easy-vphone.rb` into `dikeckaan/homebrew-easy-vphone` and push the tap.
6. Verify on another Apple Silicon Mac: `brew tap dikeckaan/easy-vphone`, then `brew install --cask dikeckaan/easy-vphone/easy-vphone`.

Keep the checksum tied to the final archive: re-signing, stapling or rebuilding changes it. Regenerate the cask if the archive changes. The cask's `zap` intentionally leaves VM storage, IPAs and ipatool account state intact.

GitHub Actions builds test artifacts on pushes/PRs. It has read-only repository permissions and does not publish releases or push tap updates. The generated local ad-hoc artifact is suitable for development, not a notarized public release.

Official `homebrew/cask` inclusion has separate acceptance and Gatekeeper requirements; publishing a personal tap does not imply inclusion there.

For a locally development-signed build, set `SIGN_IDENTITY` to the Apple Development identity fingerprint and leave `NOTARY_PROFILE` unset. This verifies local code integrity but is not a notarized Developer ID release. No certificate, private key, identity fingerprint or account credential is committed to this repository.
