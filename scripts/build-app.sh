#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
version=$(cat "$repo/VERSION")
case "$(uname -m)" in arm64) ;; *) echo 'This release build targets Apple Silicon. Build the Swift package manually for other architectures.' >&2; exit 1;; esac
swift build --package-path "$repo" -c release \
  -Xswiftc -debug-prefix-map -Xswiftc "$repo=/src/videoscribe" \
  -Xswiftc -file-prefix-map -Xswiftc "$repo=/src/videoscribe"
bin=$(swift build --package-path "$repo" -c release --show-bin-path)
app="$repo/dist.noindex/VideoScribe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$repo/Assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$bin/VideoScribe" "$app/Contents/MacOS/VideoScribe"
cp "$bin/VideoScribeAgent" "$app/Contents/MacOS/VideoScribeAgent"
/usr/bin/strip -S "$app/Contents/MacOS/VideoScribe" "$app/Contents/MacOS/VideoScribeAgent"
python3 - "$app" "$version" <<'PY'
import plistlib,sys
from pathlib import Path
app=Path(sys.argv[1])
info=dict(CFBundleExecutable='VideoScribe',CFBundleIdentifier='io.github.magiconline.videoscribe',CFBundleName='VideoScribe',CFBundleDisplayName='VideoScribe',CFBundlePackageType='APPL',CFBundleShortVersionString=sys.argv[2],CFBundleVersion='6',CFBundleIconFile='AppIcon',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
