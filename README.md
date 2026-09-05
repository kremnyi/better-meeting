# Better Meeting

Record meetings from the macOS menu bar and transcribe them locally with Whisper.
Save video, audio, Markdown, and JSON in one folder per meeting.

Better Meeting captures a display, system audio, and your microphone. Choose the
display and microphone in **Capture options**, then start recording. After you
stop, the app creates a timestamped transcript on your Mac. Open completed
meeting folders with the Finder button in the menu bar.

**For Apple Silicon Macs running macOS 15 or newer.** Homebrew and ZIP releases
are ad-hoc signed, without an Apple Developer ID or notarization.

<img src="docs/menu-bar.png" alt="Better Meeting menu with capture options and Finder buttons for recent meetings" width="304">

The app's menu bar view, rendered with fictional meetings.

[Features](#features) · [Install](#install-with-homebrew) · [Permissions](#permissions-and-privacy) · [Development](#development) · [Project origin](#project-origin)

## Features

- Choose a display, microphone, video resolution, and frame rate; record with ScreenCaptureKit
- Transcribe locally with WhisperKit after recording stops
- Automatically name untitled meetings from a person, company, or product and a recurring topic
- Prepare the speech model before your first meeting and follow processing progress
- Open any of the 10 most recent completed meeting folders in Finder
- Retry unfinished recordings from saved audio, including after restarting the app
- Remember your save folder and capture options
- Finish saving and transcribing before quitting an active recording

## Meeting folders

The default location is `~/Documents/Better Meetings`. You can choose another
folder before recording; the app remembers it on subsequent launches.

```text
2026-09-04 14.30.00 — Product sync/
├── recording.mp4
├── audio.m4a
├── transcript.md
├── transcript.json
└── metadata.json
```

`transcript.md` contains readable timestamps and a link to the video file. The
timestamps themselves are plain text. `transcript.json` stores each segment's
start, end, text, and detected language; `metadata.json` stores the meeting title,
date, duration, file names, and transcription status.

Leave the meeting name empty to name it automatically after transcription. For
example, repeated discussion of a pricing review with Anna can produce
`Anna — Pricing Review`, saved in a folder such as
`2026-09-04 14.30.00 — Anna — Pricing Review`. The Markdown heading and metadata
use the same title; the Finder button opens the renamed folder.

Titles use Apple's built-in `NaturalLanguage` framework to find a person or
organization and a repeated noun or short noun phrase. Recurring capitalized
nouns provide a conservative fallback for product names. This requires no
additional model download or API call. Recognition depends on the transcript
and language support available on the Mac; it is not a generated summary.

If no usable name and repeated topic are found, the date-based name remains,
such as `2026-09-04 14.30.00`. Typed titles are preserved. New recordings remember
whether a title was entered, so automatic naming also works when retrying an
unfinished recording after a restart. Older folders without that information
keep their titles. Name collisions receive a numeric suffix; existing folders
are never overwritten.

An illustrative transcript excerpt:

```text
## Transcript

[00:00:02] [en] Let's review the release checklist.
[00:00:08] [en] I'll check the microphone selection before Friday.
[00:00:15] [en] We'll decide whether to ship after that test.
```

Recordings are saved before transcription. If processing fails, use **Retry
transcription** or return to **Finish saved recording** in the menu bar. Existing
audio is reused; the app extracts it from the video if needed. A recording
interrupted before macOS finishes writing the video may not be recoverable.

## Requirements

- macOS 15 or newer
- Apple Silicon Mac
- Xcode 16 or newer only when building from source
- Internet access for the first Whisper model download

## Install with Homebrew

This repository also serves as the app's Homebrew tap:

```bash
brew tap kremnyi/better-meeting https://github.com/kremnyi/better-meeting
brew install --cask kremnyi/better-meeting/better-meeting
open -a "Better Meeting"
```

The cask downloads a versioned Apple Silicon app from
[GitHub Releases](https://github.com/kremnyi/better-meeting/releases) and verifies
its SHA-256 checksum. It uses the same ad-hoc signing as a local build. A ZIP
download is also available there; extract it and move the app to `/Applications`.

If macOS blocks the first launch, try opening the app, then use **System Settings
→ Privacy & Security → Open Anyway** for Better Meeting. See
[Apple's instructions](https://support.apple.com/102445). The installer keeps
macOS security checks enabled. Managed Macs may not allow this exception.

To update, finish any active recording and quit the app, then run:

```bash
brew update
brew upgrade --cask kremnyi/better-meeting/better-meeting
```

Ad-hoc signatures change with new builds, so macOS may require recording
permissions to be granted again after an update. Homebrew uninstall removes the
app; saved meeting folders remain on disk.

## Install from source

```bash
git clone https://github.com/kremnyi/better-meeting.git
cd better-meeting
./scripts/build-app.sh
open "dist/Better Meeting.app"
```

Move `Better Meeting.app` from `dist` to `/Applications` if you want to keep it
installed. Controls live in the menu bar; the app has no Dock icon.

## First recording

1. Open Better Meeting's menu bar icon. Use **Set up transcription** to download
   and load the multilingual Whisper `small` model before a meeting. Otherwise,
   setup happens after your first recording stops.
2. Choose a save folder and adjust **Capture options** if needed. The defaults are
   your main display, system microphone, 1440 px resolution, and 10 fps frame rate.
3. Start recording and grant the permissions below. After granting screen
   recording access, restart the app when prompted.
4. Stop recording and wait for transcription. Use the folder button beside the
   finished meeting to open its files in Finder.

**Resolution** caps the video's longest edge at 1280, 1440, 1920, or 2560 pixels.
The app uses the display's pixel size, including Retina scaling, preserves its
aspect ratio, and never upscales smaller displays. Dimensions are rounded down
to even pixels for H.264 recording.

**Frame rate** controls motion smoothness: 5 fps (Compact), 10 fps (Standard),
or 30 fps (Smooth). Higher resolution and frame rate can
increase file size and capture work. These presets use the native recorder;
compression bitrate is managed by macOS. Audio and transcription are unaffected.
Choices are saved for future recordings and can be changed before starting one.

Model downloads are cached under
`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/`; tokenizer files may
also be stored under `~/Documents/huggingface/models/openai/whisper-small/`.
The first model load can take longer while Core ML prepares it for your Mac.
Subsequent launches load cached model files directly.

## Permissions and privacy

The first recording asks for **Screen & System Audio Recording** and
**Microphone** access. macOS may require Better Meeting to be reopened after
screen-recording access is granted.

Recording and transcription run locally. The app does not upload meetings or
send them to an LLM. Model and tokenizer setup downloads files from Hugging Face.
Automatic meeting titles run entirely through Apple's on-device language tagging.
After successful setup, cached files support offline transcription across app
restarts. Setup may need internet again if those files are removed or damaged.

Release ZIPs and default source builds are ad-hoc signed. Because macOS ties recording
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
swift test
./scripts/build-app.sh
```

`./scripts/build-app.sh` produces the complete `.app` bundle in `dist/`, including
the app icon, menu bar assets, license notices, and code signature.
Use the app bundle for recording and permission checks; `swift run BetterMeeting`
is only a development launch and does not include the bundle's permission text
or assets. GitHub Actions runs the recovery checks and builds the app bundle on
macOS.

The optional model check downloads the real model into `.build/model-check`,
then verifies a fresh process can load it with HTTP requests blocked:

```bash
BETTER_MEETING_MODEL_CHECK=prepare swift test --filter testModelPreparationAcrossColdLaunches
BETTER_MEETING_MODEL_CHECK=offline swift test --filter testModelPreparationAcrossColdLaunches
```

To refresh the menu image using fictional meetings:

```bash
BETTER_MEETING_PREVIEW_PATH="$PWD/docs/menu-bar.png" swift test --filter testRenderMenuBarPreview
```

## Current limits

- Records one whole display; there is no window-only or audio-only capture mode.
- Transcription starts after recording stops. New recordings wait until it finishes.
- Transcript segments have timestamps and detected language, without speaker labels.
- Existing-file import, live captions, and meeting summaries are not included.
- A selected display or microphone must still be connected when recording starts.
- Force Quit or power loss can interrupt video finalization; normal Quit waits for saving.

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
