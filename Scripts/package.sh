#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -d 'dist/NOIR Audio.app'
test -f 'dist/NOIR Audio Drivers.pkg'
codesign --verify --deep --strict 'dist/NOIR Audio.app'
ditto -c -k --sequesterRsrc --keepParent 'dist/NOIR Audio.app' dist/NOIR-Audio-0.1.0-macOS-arm64.zip
COPYFILE_DISABLE=1 tar -czf dist/NOIR-Audio-0.1.0-source.tar.gz \
  --exclude='.git' --exclude='.DS_Store' --exclude='xcuserdata' \
  --exclude='*.wav' --exclude='*.aiff' --exclude='Tests/Results/*.json' --exclude='__pycache__' \
  --exclude='Website/public/downloads' --exclude='Website/test-results' --exclude='Website/.vercel' \
  .gitignore LICENSE README.md project.yml 'NOIR Audio.xcodeproj' Sources Scripts Tests Docs ThirdParty Website
cd dist
shasum -a 256 NOIR-Audio-0.1.0-macOS-arm64.zip NOIR-Audio-0.1.0-source.tar.gz 'NOIR Audio Drivers.pkg' > SHA256SUMS.txt
echo 'Packaged app, matching source, driver installer and checksums in dist.'
