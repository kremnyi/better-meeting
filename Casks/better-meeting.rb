cask "better-meeting" do
  version "0.3.3"
  sha256 "d09637aa6e51591a7354628c2b4fc710e78dc5be6b98931dc284f8b08c8f40d2"

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
