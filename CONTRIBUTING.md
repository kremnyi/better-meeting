# Contributing

## Build and test

Use an Apple Silicon Mac with macOS 15 or newer and Xcode 16 or newer. From the
repository root:

```bash
swift test
./scripts/build-app.sh
```

Tests cover meeting recovery, audio exports, saved preferences, capture presets,
and automatic titles. GitHub Actions runs the same checks and keeps any macOS
crash reports when a check fails.

Use `dist/Better Meeting.app` to check recording permissions. macOS associates
permission with the signed app. To keep that identity across local builds, use
an existing keychain identity:

```bash
BETTER_MEETING_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" \
    ./scripts/build-app.sh
```

## Optional checks

The model check downloads into `.build/model-check`, then checks that a separate
process can load the cache with HTTP requests blocked:

```bash
BETTER_MEETING_MODEL_CHECK=prepare swift test --filter testModelPreparationAcrossColdLaunches
BETTER_MEETING_MODEL_CHECK=offline swift test --filter testModelPreparationAcrossColdLaunches
```

To update the README screenshot with fictional meetings:

```bash
BETTER_MEETING_PREVIEW_PATH="$PWD/docs/menu-bar.png" swift test --filter testRenderMenuBarPreview
```

## Before opening a pull request

- Keep recording and transcription local, with one folder per meeting.
- Preserve typed titles, the date fallback, and recovery from saved recordings.
- Keep changes and commits focused; include a regression check for a bug fix.
- Run the tests and app-bundle build above. Check permission changes in the signed app.

## Publish a Homebrew release

This repository is also the tap. `Casks/better-meeting.rb` points to a versioned
GitHub release; no separate repository or signing certificate is needed.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `App/Info.plist`.
2. Run `swift test`, then `./scripts/package-release.sh`. This creates an
   ad-hoc-signed ZIP and `.sha256` file in `dist/`.
3. Set the cask's `version` and `sha256` to match that archive. Run
   `ruby -c Casks/better-meeting.rb` and commit the release changes together.
4. Tag that commit as `v<version>` and push the commit and tag. Create the
   matching GitHub release and attach the ZIP and checksum from step 2.
5. Test the [Homebrew install commands](README.md#install-with-homebrew) against
   the public release.

Keep the exact archive used for the checksum; rebuilding can change it. Never
replace a published version's archive. Publish a new version instead.

Release notes must explain ad-hoc signing, first-launch approval, and recording
permissions after updates. Keep checksum verification and platform requirements
in the cask. Install hooks must not disable security checks or remove meetings.
