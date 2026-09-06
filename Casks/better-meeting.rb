cask "better-meeting" do
  version "0.3.17"
  sha256 "b84e354b809ea97edbdcea5f99b9d7ed1cea953e0bb599934429f1229b8f3225"

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
