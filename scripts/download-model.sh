#!/bin/bash
set -euo pipefail
# Download only the pinned multilingual base model; never replace an unrelated existing file.
target=${1:-${VIDEOSCRIBE_MODEL_PATH:-$HOME/Library/Application Support/VideoScribe/models/ggml-base.bin}}
expected=60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe
url=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
if [[ -e "$target" ]]; then
  actual=$(shasum -a 256 "$target" | awk '{print $1}')
  if [[ "$actual" == "$expected" ]]; then printf 'Model already verified: %s\n' "$target"; exit 0; fi
  echo 'A different file already exists at the model destination. Choose another destination; it was not overwritten.' >&2; exit 1
fi
mkdir -p "$(dirname "$target")"
tmp="$target.partial.$$"
trap 'rm -f "$tmp"' EXIT
curl --fail --location --retry 3 --connect-timeout 20 "$url" --output "$tmp"
actual=$(shasum -a 256 "$tmp" | awk '{print $1}')
[[ "$actual" == "$expected" ]] || { echo 'Model checksum mismatch; download discarded.' >&2; exit 1; }
mv "$tmp" "$target"
printf 'Model verified: %s\n' "$target"
