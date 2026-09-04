# Better Meeting

A native macOS menu bar app that records meetings and turns them into local,
portable transcripts.

Better Meeting captures the main display, system audio, and microphone. When
recording stops, it transcribes the audio on the Mac and creates one folder with
the video, audio, Markdown transcript, and machine-readable metadata. Recording
controls, processing progress, and recent transcripts all live in the menu bar;
there is no Dock icon or separate app window.

[Features](#features) · [Install](#install-from-source) · [Permissions](#permissions-and-privacy) · [Development](#development) · [Project origin](#project-origin)

## Features

- Record the main display, system audio, and microphone with ScreenCaptureKit
- Transcribe locally with WhisperKit after recording stops
- Follow real progress while the model downloads and the transcript is created
- Reopen any of the 10 most recent transcripts from the menu bar
- Open an individual meeting folder or the complete meetings folder in Finder
- Keep recordings and transcripts on the Mac

## Meeting folders

The default location is `~/Documents/Better Meetings`. You can choose another
folder before recording.

```text
2026-09-04 14.30.00 — Product sync/
├── recording.mp4
├── audio.m4a
├── transcript.md
├── transcript.json
└── metadata.json
```

`transcript.md` contains readable, timestamped text and links back to the video.
The JSON files make the same meeting easy to use with scripts or other tools.

## Requirements

- macOS 15 or newer
- Apple Silicon Mac
- Xcode 16 or newer to build from source
- Internet access for the first Whisper model download

## Install from source

```bash
git clone https://github.com/kremnyi/better-meeting.git
cd better-meeting
./scripts/build-app.sh
open "dist/Better Meeting.app"
```

Move `Better Meeting.app` from `dist` to `/Applications` if you want to keep it
installed. A signed and notarized release is not available yet.

## Permissions and privacy

The first recording asks for **Screen & System Audio Recording** and
**Microphone** access. macOS may require Better Meeting to be reopened after
screen-recording access is granted.

Recording and transcription run locally. The app does not upload meetings or
send them to an LLM. Network access is only needed when WhisperKit downloads its
speech model for the first time.

Development builds are ad-hoc signed by default. Because macOS ties recording
permission to an app's signature, permissions may need to be granted again after
each ad-hoc rebuild. Use a stable keychain identity to avoid that:

```bash
BETTER_MEETING_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" \
    ./scripts/build-app.sh
```

## Development

The app is a Swift Package with a single SwiftUI executable target.

```bash
swift build --product BetterMeeting
swift run BetterMeeting
```

`./scripts/build-app.sh` produces the complete `.app` bundle in `dist/`, including
the app icon, menu bar assets, license notices, and code signature.

## Project origin

This repository is a native macOS adaptation of
[GivenFLY/better-meeting](https://github.com/GivenFLY/better-meeting). The
original project extracts transcripts, on-screen text, and screenshots from an
existing recording. This fork keeps its local-first, one-folder-per-meeting
idea, but focuses the current codebase on recording and transcription through a
native menu bar app.

The original implementation remains available in the upstream repository and
in this fork's Git history.

## License

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for
upstream attribution and [ThirdPartyNotices.md](ThirdPartyNotices.md) for
WhisperKit notices.
