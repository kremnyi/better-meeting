# Contributing

Contributions to the native macOS app are welcome under the terms of the
[Apache License 2.0](LICENSE).

## Build locally

Better Meeting requires macOS 15, Apple Silicon, and Xcode 16 or newer.

```bash
git clone https://github.com/kremnyi/better-meeting.git
cd better-meeting
swift build --product BetterMeeting
swift test
```

Use `./scripts/build-app.sh` when a complete `.app` bundle is needed.

## Before opening a pull request

- Keep the app menu-bar-only unless a change explicitly requires another surface.
- Keep recording and transcription local.
- Preserve one self-contained folder per meeting.
- Match the existing Swift and SwiftUI style.
- Keep commits focused and verify a release build succeeds.
- Run `swift test`; it covers unfinished recordings, older meeting folders,
  failed audio exports, persisted choices, video presets, automatic titles, and folder renaming.
  Keep automatic naming on-device with `NaturalLanguage`; preserve typed titles
  and the date fallback, including during recovery. The real model check is opt-in,
  as described in the README.

If a change affects recording permissions, also test a signed app bundle because
macOS grants Screen Recording access to an app identity, not just its bundle ID.

## Publish a Homebrew release

The app repository is also a tap; `Casks/better-meeting.rb` points to a versioned
GitHub release. No separate tap repository or signing certificate is needed.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `App/Info.plist` for the new release.
2. Run `swift test`, then `./scripts/package-release.sh` on an Apple Silicon Mac.
   This builds an ad-hoc-signed app and writes a ZIP and `.sha256` file in `dist/`.
3. Set the cask's `version` and `sha256` to match that exact archive. Check it with
   `ruby -c Casks/better-meeting.rb`, then commit the release changes
   together. Keep the archive: rebuilding can change its checksum.
4. Tag the committed source as `v<version>` and push the commit and tag. Create
   the matching GitHub release and attach the ZIP and checksum file from step 2.
   Never replace an existing version's archive; publish a new version instead.
5. Verify the documented Homebrew install commands against the public release.

Release notes must state that the app is ad-hoc signed and not notarized, explain
the first-launch approval, and mention that updates may require recording
permissions again. Preserve the cask's macOS and architecture requirements and
checksum verification. Do not add install hooks that disable security checks or
remove saved meetings.
