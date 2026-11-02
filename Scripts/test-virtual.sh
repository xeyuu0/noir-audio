#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun clang++ -std=c++20 -O2 -I Sources/DSP -I Sources/AudioEngine -I ThirdParty/OctopusEAX/src \
  -c Sources/AudioEngine/Engine.cpp -o Build/VirtualEngine.o
xcrun swiftc -swift-version 5 -O -parse-as-library -import-objc-header Sources/AudioEngine/NoirBridge.h \
  Sources/AudioDevices/AudioDevices.swift Tests/VirtualRouting.swift Build/VirtualEngine.o \
  -framework CoreAudio -framework AudioToolbox -framework AppKit -lc++ -o Build/VirtualRouting
Build/VirtualRouting | tee Tests/Results/virtual-routing-tests.log
