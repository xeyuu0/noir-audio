#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun clang++ -std=c++20 -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I Sources/DSP -I Sources/AudioEngine -I ThirdParty/OctopusEAX/src \
  Tests/CoreTests.cpp Sources/AudioEngine/Engine.cpp -framework CoreAudio -framework AudioToolbox \
  -o Build/CoreTestsSanitized
Build/CoreTestsSanitized | tee Tests/Results/sanitizer-tests.log
