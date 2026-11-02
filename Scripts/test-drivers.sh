#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
for channels in 2 16; do
  xcrun clang -O2 -fblocks -DkNumber_Of_Channels="$channels" Tests/DriverTests.c \
    -framework CoreAudio -framework CoreFoundation -framework Accelerate -o "Build/DriverTests$channels"
  "Build/DriverTests$channels"
done | tee Tests/Results/driver-tests.log
