cask "easy-vphone" do
  version "0.3.0"
  sha256 "b429a5ce73b822efbebf38ef4795cf2274bf2353d3661b3c2c840acc893ce196"

  url "https://github.com/dikeckaan/easy-vphone/releases/download/v#{version}/easy-vphone-#{version}-arm64.zip"
  name "easy-vphone"
  desc "Graphical iOS virtual machine toolkit with an integrated IPA library"
  homepage "https://github.com/dikeckaan/easy-vphone"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "easy-vphone.app"

  zap trash: "~/Library/Preferences/io.github.easy-vphone.plist"
end
