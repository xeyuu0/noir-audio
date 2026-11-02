#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun clang++ -std=c++20 -O2 -I Sources/DSP -I Sources/AudioEngine -I ThirdParty/OctopusEAX/src \
  -c Sources/AudioEngine/Engine.cpp -o Build/BroadcastEngine.o
xcrun swiftc -swift-version 5 -O -parse-as-library -import-objc-header Sources/AudioEngine/NoirBridge.h \
  Sources/AudioDevices/AudioDevices.swift Sources/Broadcasting/*.swift Tests/BroadcastConfiguration.swift Build/BroadcastEngine.o \
  -framework CoreAudio -framework AudioToolbox -framework AppKit -lc++ -o Build/BroadcastConfigurationTests
Build/BroadcastConfigurationTests | tee Tests/Results/broadcast-configuration-tests.log
xcrun swiftc -swift-version 5 -O -parse-as-library -import-objc-header Sources/AudioEngine/NoirBridge.h \
  Sources/AudioDevices/AudioDevices.swift Sources/Broadcasting/*.swift Tests/BroadcastIntegration.swift Build/BroadcastEngine.o \
  -framework CoreAudio -framework AudioToolbox -framework AppKit -lc++ -o Build/BroadcastIntegration
python3 Tests/BroadcastServers.py | tee Tests/Results/broadcast-tests.log
