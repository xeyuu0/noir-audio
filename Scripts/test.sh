#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun clang++ -std=c++20 -O2 -g -I Sources/DSP -I Sources/AudioEngine -I ThirdParty/OctopusEAX/src \
  Tests/CoreTests.cpp Sources/AudioEngine/Engine.cpp -framework CoreAudio -framework AudioToolbox \
  -o Build/CoreTests
Build/CoreTests | tee Tests/Results/core-tests.log
