# VideoScribe for macOS

A native SwiftUI tool for video-to-text workflows. Download a video URL or import local media, reuse matching subtitles when available, transcribe speech offline with whisper.cpp, and export plain TXT, timed TXT, SRT or JSON.

[中文指南](README.md) · [Agent plugin](https://github.com/magiconline/videoscribe-agent-plugin)

## Quick start

The public release is a **minimal runtime**: the application and MCP/worker executables are included; third-party tools and model weights are installed separately.

```sh
brew install yt-dlp ffmpeg whisper.cpp node
git clone https://github.com/magiconline/videoscribe-macos.git
cd videoscribe-macos
./scripts/download-model.sh
```

Download the application ZIP from Releases, extract it and place `VideoScribe.app` in `/Applications` or your personal Applications directory. Alternatively, build with Xcode / Swift 6 and Python 3:

```sh
swift test
./scripts/build-app.sh
open dist.noindex/VideoScribe.app
```

The source deployment target is macOS 14; release binaries are for Apple Silicon and have only been tested on the build machine. Intel and other OS versions are not verified. The app is ad-hoc signed, not Apple-notarized.

## Behavior

- Source URLs are resolved through the macOS system proxy selected at job start; the application never changes system networking.
- Unknown subtitle language falls back to speech transcription instead of silently selecting a translation.
- Transcription runs locally. Downloads still contact the source website.
- Persistent workers survive GUI/MCP disconnection. Two jobs may process concurrently; cancellation and retry are explicit.
- Source-language transcription is not arbitrary translation. No OCR, speaker diarization or checkpoint resumption is provided.

See [usage](docs/USAGE.md), [development](docs/DEVELOPMENT.md), [MCP](docs/MCP.md), [security](SECURITY.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Original code is MIT licensed.
