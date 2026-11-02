#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S . -B Build/windows -DCMAKE_TOOLCHAIN_FILE=Windows/mingw-toolchain.cmake -DCMAKE_BUILD_TYPE=Release
cmake --build Build/windows --parallel 4
