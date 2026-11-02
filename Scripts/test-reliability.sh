#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun clang++ -std=c++20 -O2 -I Sources/DSP -I Sources/AudioEngine -I ThirdParty/OctopusEAX/src \
  -c Sources/AudioEngine/Engine.cpp -o Build/ReliabilityEngine.o
sources=()
while IFS= read -r path; do sources+=("$path"); done < <(rg --files Sources -g '*.swift' -g '!NoirApp.swift')
xcrun swiftc -swift-version 5 -O -parse-as-library -import-objc-header Sources/AudioEngine/NoirBridge.h \
  "${sources[@]}" Tests/Reliability.swift Build/ReliabilityEngine.o \
  -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework AppKit -framework SwiftUI -lc++ -o Build/Reliability
Build/Reliability | tee Tests/Results/reliability-tests.log
