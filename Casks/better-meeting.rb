cask "better-meeting" do
  version "0.3.0"
  sha256 "986976ce6458a474845ba7d3a0465c2ce00ec243dce1502c742617c8116ecc84"

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
