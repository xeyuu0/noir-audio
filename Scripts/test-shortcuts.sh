#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun swiftc -swift-version 5 -O -parse-as-library \
  Sources/AudioDevices/AudioDevices.swift Sources/Presets/Session.swift Sources/App/Shortcuts.swift Tests/ShortcutTests.swift \
  -framework SwiftUI -framework CoreAudio -framework AudioToolbox -framework AppKit -o Build/ShortcutTests
Build/ShortcutTests | tee Tests/Results/shortcut-tests.log
