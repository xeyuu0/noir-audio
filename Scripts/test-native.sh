#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun clang++ -std=c++20 -O2 -I Sources/DSP -I Sources/AudioEngine -I ThirdParty/OctopusEAX/src \
  -c Sources/AudioEngine/Engine.cpp -o Build/NativeEngine.o
xcrun swiftc -swift-version 5 -O -parse-as-library -import-objc-header Sources/AudioEngine/NoirBridge.h \
  Sources/AudioDevices/AudioDevices.swift Sources/App/Shortcuts.swift Sources/Presets/Session.swift Sources/Recording/*.swift \
  Sources/Soundboard/ClipDecoder.swift Tests/NativeIntegration.swift Build/NativeEngine.o \
  -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework AppKit -lc++ -o Build/NativeIntegration
Build/NativeIntegration | tee Tests/Results/native-integration.log
