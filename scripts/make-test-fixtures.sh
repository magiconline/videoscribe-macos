#!/bin/bash
set -euo pipefail
folder=${1:-test-fixtures}
mkdir -p "$folder"
cat > "$folder/fixture.srt" <<'SRT'
1
00:00:01,000 --> 00:00:03,500
这是一段中文测试字幕。

2
00:00:04,000 --> 00:00:06,000
This is an English subtitle.
SRT
ffmpeg -nostdin -y -v error -f lavfi -i color=c=black:s=320x180:d=8 -i "$folder/fixture.srt" -map 0:v -map 1:s -c:v libx264 -c:s srt -metadata:s:s:0 language=zho "$folder/embedded.mkv"
ffmpeg -nostdin -y -v error -f lavfi -i sine=frequency=440:duration=8 -ar 16000 -ac 1 "$folder/sidecar.wav"
cp "$folder/fixture.srt" "$folder/sidecar.zh.srt"
if command -v say >/dev/null; then
  if say -v "${VOICE_EN:-Samantha}" -o "$folder/english.aiff" 'Ask not what your country can do for you. Ask what you can do for your country.'; then
    ffmpeg -nostdin -y -v error -i "$folder/english.aiff" -ar 16000 -ac 1 "$folder/english.wav"
  fi
  if [[ -n "${VOICE_ZH:-}" ]]; then
    say -v "$VOICE_ZH" -o "$folder/chinese.aiff" '你好，这是一段中文语音测试。我们正在开发视频文字稿工具。'
  fi
fi
printf 'Synthetic fixtures prepared: %s\n' "$folder"
