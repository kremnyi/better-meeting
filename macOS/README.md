# Better Meeting for macOS

The native app records the main display, system audio, and microphone with
ScreenCaptureKit. After recording stops, WhisperKit transcribes the meeting on
the Mac and the app writes a self-contained meeting folder. The full workflow
runs from the menu bar; the app has no Dock icon or separate window.

```text
2026-09-04 14.30.00 — Product sync/
├── recording.mp4
├── audio.m4a
├── transcript.md
├── transcript.json
└── metadata.json
```

## Requirements

- macOS 15 or newer
- Apple Silicon
- Xcode 16 or newer
- Internet access for the first transcription model download

## Build the app

```bash
cd macOS
./scripts/build-app.sh
open "dist/Better Meeting.app"
```

After launch, choose the Better Meeting icon in the menu bar to set the meeting
title and destination, start or stop recording, and open completed transcripts.

The first recording requests Screen Recording and Microphone access. macOS may
require the app to be reopened after Screen Recording access is granted.

The build script creates an ad-hoc signed development app. Distribution signing,
notarization, and release packaging are intentionally not part of this version.
