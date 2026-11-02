#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Website/public/downloads
cp dist/NOIR-Audio-0.1.0-macOS-arm64.zip dist/NOIR-Audio-0.1.0-macOS-arm64.dmg dist/NOIR-Audio-0.1.0-Windows-x64-Setup.exe dist/NOIR-Audio-0.1.0-Windows-x64.zip Website/public/downloads/
cp dist/NOIR-Audio-0.1.0-source.tar.gz Website/public/downloads/
cp 'dist/NOIR Audio Drivers.pkg' Website/public/downloads/NOIR-Audio-Drivers-0.1.0.pkg
cd Website/public/downloads
shasum -a 256 NOIR-Audio-0.1.0-macOS-arm64.dmg NOIR-Audio-0.1.0-Windows-x64-Setup.exe NOIR-Audio-0.1.0-Windows-x64.zip NOIR-Audio-0.1.0-macOS-arm64.zip NOIR-Audio-0.1.0-source.tar.gz NOIR-Audio-Drivers-0.1.0.pkg > SHA256SUMS.txt
echo 'Website downloads prepared from the actual release artifacts.'
