# VideoScribe for macOS

VideoScribe is a native macOS app built with SwiftUI. Paste a video URL or import a local file to extract matching subtitles. When subtitles are unavailable, it transcribes speech locally with whisper.cpp. Export the transcript as plain TXT, timed TXT, SRT or JSON.

[中文指南](README.md) · [Agent plugin](https://github.com/magiconline/videoscribe-agent-plugin)

## Quick start

The release includes the app and MCP/worker executables. Install the media tools and model weights separately:

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

The source targets macOS 14. Release binaries are built for Apple Silicon and have only been tested on the build machine; Intel and other macOS versions remain unverified. The app has an ad-hoc signature and has not been notarized by Apple.

## Behavior

- Source URLs are resolved through the macOS system proxy selected at job start; the application never changes system networking.
- Unknown subtitle language falls back to speech transcription instead of silently selecting a translation.
- Transcription runs locally. Downloads still contact the source website.
- Persistent workers survive GUI/MCP disconnection. Two jobs may process concurrently; cancellation and retry are explicit.
- Transcripts stay in the source language. The app does not provide arbitrary translation, OCR, speaker diarization or checkpoint resumption.

See [usage](docs/USAGE.md), [development](docs/DEVELOPMENT.md), [MCP](docs/MCP.md), [security](SECURITY.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Original code is MIT licensed.
