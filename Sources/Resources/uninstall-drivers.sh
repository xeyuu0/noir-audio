#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then
  echo 'Administrator authorization is required.' >&2
  exit 1
fi
# Exact product-owned paths only. No wildcard removal and no automatic audio daemon restart.
for bundle in NOIRMicrophone NOIRLoopback; do
  path="/Library/Audio/Plug-Ins/HAL/$bundle.driver"
  if [ -e "$path" ]; then
    /bin/rm -rf -- "$path"
  fi
done
/usr/sbin/pkgutil --forget audio.noir.drivers >/dev/null 2>&1 || true
echo 'NOIR drivers removed. Restart macOS to unload them.'
