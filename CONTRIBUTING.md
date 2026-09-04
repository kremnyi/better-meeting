# Contributing

Contributions to the native macOS app are welcome under the terms of the
[Apache License 2.0](LICENSE).

## Build locally

Better Meeting requires macOS 15, Apple Silicon, and Xcode 16 or newer.

```bash
git clone https://github.com/kremnyi/better-meeting.git
cd better-meeting
swift build --product BetterMeeting
```

Use `./scripts/build-app.sh` when a complete `.app` bundle is needed.

## Before opening a pull request

- Keep the app menu-bar-only unless a change explicitly requires another surface.
- Keep recording and transcription local.
- Preserve one self-contained folder per meeting.
- Match the existing Swift and SwiftUI style.
- Keep commits focused and verify a release build succeeds.

If a change affects recording permissions, also test a signed app bundle because
macOS grants Screen Recording access to an app identity, not just its bundle ID.
