# Third-party components

The original source in this repository is MIT licensed. The minimal release runtime contains only the project executables and system-framework references. It does **not** redistribute Homebrew executables, third-party dynamic libraries or model weights.

Install runtime tools from their respective distributors. Their licenses are independent of this repository's MIT license:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp): downloader; see its LICENSE and dependency notices.
- [FFmpeg](https://ffmpeg.org/legal.html): audio/video processing; build options determine LGPL/GPL licensing.
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp): local recognition; see its MIT license and ggml dependencies.
- [Node.js](https://github.com/nodejs/node/blob/main/LICENSE): JavaScript runtime used by yt-dlp when needed.
- [Whisper model conversion](https://huggingface.co/ggerganov/whisper.cpp) and [original Whisper](https://github.com/openai/whisper): model files are downloaded separately, not committed or included in the release ZIP.

If you choose to create a fully bundled redistribution, you are responsible for the licenses, notices, corresponding-source requirements and platform signing of the exact third-party builds you include. The public build script deliberately produces a minimal application.
