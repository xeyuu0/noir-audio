#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d 'dist/NOIR Audio.app'
codesign --verify --deep --strict 'dist/NOIR Audio.app'
mkdir -p Build/DMG
python3 - <<'PY'
from pathlib import Path
import shutil
p=Path('Build/DMG/NOIR Audio.app')
if p.exists():shutil.rmtree(p)
PY
ditto 'dist/NOIR Audio.app' 'Build/DMG/NOIR Audio.app'
ln -sfn /Applications Build/DMG/Applications
cp LICENSE Build/DMG/LICENSE.txt
cat > 'Build/DMG/Read Me.txt' <<'TEXT'
NOIR Audio 0.1.0 · Apple Silicon

Drag NOIR Audio.app into Applications, then launch it.
Liquid Glass is available on macOS 26 and later. macOS 14.2–25 use native materials.

This is an ad-hoc signed, unnotarized preview. macOS may block it.
Review the source and SHA-256 checksum before deciding whether to trust this build.
Official Apple guidance: https://support.apple.com/en-us/102445

Virtual drivers are optional. Install them separately from the app's Virtual Devices section.
Driver installation requires administrator authorization and a restart.
The app stays silent until you select devices and press Start audio.

Guide: https://noir-audio-orpin.vercel.app/install
Source: https://github.com/xeyuu0/noir-audio
TEXT
hdiutil create -volname 'NOIR Audio' -srcfolder Build/DMG -ov -format UDZO 'dist/NOIR-Audio-0.1.0-macOS-arm64.dmg'
hdiutil verify 'dist/NOIR-Audio-0.1.0-macOS-arm64.dmg'
