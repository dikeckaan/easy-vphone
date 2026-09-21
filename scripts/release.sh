#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.3.0}"
REPOSITORY="${REPOSITORY:-dikeckaan/easy-vphone}"
[[ "$REPOSITORY" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]] || { echo 'Invalid repository' >&2; exit 1; }
BUILD_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/easy-vphone-release.XXXXXX")"
export VERSION BUILD_STAGE
bash scripts/build.sh
ARCHIVE="$PWD/dist/easy-vphone-$VERSION-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$BUILD_STAGE/easy-vphone.app" "$ARCHIVE"
# Supply a configured notarytool keychain profile for a publicly trusted release.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${SIGN_IDENTITY:-}" ]] || { echo 'Notarization requires SIGN_IDENTITY' >&2; exit 1; }
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$BUILD_STAGE/easy-vphone.app"
  /usr/bin/ditto --norsrc "$BUILD_STAGE/easy-vphone.app" "$PWD/dist/easy-vphone.app"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$BUILD_STAGE/easy-vphone.app" "$ARCHIVE"
fi
SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "easy-vphone-$VERSION-arm64.zip" > dist/SHA256SUMS
mkdir -p dist/homebrew-easy-vphone/Casks
cat > dist/homebrew-easy-vphone/Casks/easy-vphone.rb <<RUBY
cask "easy-vphone" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPOSITORY/releases/download/v#{version}/easy-vphone-#{version}-arm64.zip"
  name "easy-vphone"
  desc "Graphical iOS virtual machine toolkit with an integrated IPA library"
  homepage "https://github.com/$REPOSITORY"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "easy-vphone.app"

  zap trash: "~/Library/Preferences/io.github.easy-vphone.plist"
end
RUBY
cp dist/homebrew-easy-vphone/Casks/easy-vphone.rb packaging/easy-vphone.rb
ruby -c packaging/easy-vphone.rb
printf 'Prepared %s\nSHA-256: %s\n' "$ARCHIVE" "$SHA"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo 'Local ad-hoc build: not notarized. Public Gatekeeper-ready distribution needs Developer ID signing and notarization.'
elif [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo 'Certificate-signed build. Notarization was not requested; this is not a notarized distribution release.'
fi
