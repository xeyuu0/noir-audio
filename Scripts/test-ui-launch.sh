#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Tests/Results
xcrun swiftc -parse-as-library -module-cache-path Build/ModuleCache Tests/LaunchSmoke.swift \
  -framework AppKit -framework ApplicationServices -o Build/LaunchSmoke
Build/LaunchSmoke | tee Tests/Results/ui-launch-tests.log
