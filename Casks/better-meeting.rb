cask "better-meeting" do
  version "0.3.4"
  sha256 "5859fbbc9692896c8375e80f80df1baac00f9f20777e6a607947d380db8f33b4"

  url "https://github.com/kremnyi/better-meeting/releases/download/v#{version}/Better-Meeting-#{version}-arm64.zip"
  name "Better Meeting"
  desc "Record meetings from the menu bar and transcribe them locally"
  homepage "https://github.com/kremnyi/better-meeting"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Better Meeting.app"

  caveats <<~EOS
    This app is ad-hoc signed and is not notarized by Apple.
    If macOS blocks opening it, use System Settings > Privacy & Security > Open Anyway.
    Updates may require granting Screen Recording and Microphone access again.
  EOS
end
