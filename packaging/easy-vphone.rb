cask "easy-vphone" do
  version "0.2.0"
  sha256 "3e8eaa28c914b6333070f688e272c4d780577346537f24a2e0861c721a9251b3"

  url "https://github.com/dikeckaan/easy-vphone/releases/download/v#{version}/easy-vphone-#{version}-arm64.zip"
  name "easy-vphone"
  desc "Graphical iOS virtual machine toolkit with an integrated IPA library"
  homepage "https://github.com/dikeckaan/easy-vphone"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "easy-vphone.app"

  zap trash: "~/Library/Preferences/io.github.easy-vphone.plist"
end
