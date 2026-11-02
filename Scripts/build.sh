#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build dist Tests/Results
if [ ! -f Sources/Resources/NOIR.icns ]; then
  xcrun swift Scripts/make-icon.swift
  iconutil -c icns Build/NOIR.iconset -o Sources/Resources/NOIR.icns
fi
xcodegen generate
xcodebuild -project 'NOIR Audio.xcodeproj' -scheme 'NOIR Audio' -configuration Release -derivedDataPath Build/DerivedData CODE_SIGN_IDENTITY=- build > Build/app-build.log 2>&1
ditto 'Build/DerivedData/Build/Products/Release/NOIR Audio.app' 'dist/NOIR Audio.app'
codesign --verify --deep --strict 'dist/NOIR Audio.app'
echo 'Built dist/NOIR Audio.app (local ad-hoc signature).'
