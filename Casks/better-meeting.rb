cask "better-meeting" do
  version "0.3.15"
  sha256 "02327d4933c9155f391e2ca9f8e2781e8bc974b216052551a86fecde4d0c0b79"

  url "https://github.com/kremnyi/better-meeting/releases/download/v#{version}/Better-Meeting-#{version}-arm64.zip"
  name "Better Meeting"
  desc "Record meetings from the menu bar and transcribe them locally"
  homepage "https://github.com/kremnyi/better-meeting"

  auto_updates true

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Better Meeting.app"

  caveats <<~EOS
    This app uses a self-signed certificate and is not notarized by Apple.
    If macOS blocks opening it, use System Settings > Privacy & Security > Open Anyway.
    Upgrading from 0.3.4 or older requires granting recording permissions again.
  EOS
end
