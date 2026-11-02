#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build/DriverPackage/Library/Audio/Plug-Ins/HAL dist
for kind in Microphone Loopback; do
  channels=2
  if [ "$kind" = Loopback ]; then channels=16; fi
  product="NOIR$kind"
  bundle="audio.noir.driver.$kind"
  xcodebuild -project ThirdParty/BlackHole/BlackHole.xcodeproj -scheme BlackHole -configuration Release \
    -derivedDataPath "Build/Driver-$kind" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES PRODUCT_NAME="$product" PRODUCT_BUNDLE_IDENTIFIER="$bundle" \
    "GCC_PREPROCESSOR_DEFINITIONS=\$(inherited) kDriver_Name=\\\"$product\\\" kDevice_Name=\\\"NOIR\\ $kind\\\" kPlugIn_BundleID=\\\"$bundle\\\" kNumber_Of_Channels=$channels kHas_Driver_Name_Format=0" \
    build > "Build/driver-$kind.log" 2>&1
  ditto "Build/Driver-$kind/Build/Products/Release/$product.driver" "Build/DriverPackage/Library/Audio/Plug-Ins/HAL/$product.driver"
done
pkgbuild --root Build/DriverPackage --identifier audio.noir.drivers --version 0.1.0 --install-location / \
  --ownership recommended 'dist/NOIR Audio Drivers.pkg'
cp 'dist/NOIR Audio Drivers.pkg' 'Sources/Resources/NOIR Audio Drivers.pkg'
echo 'Built driver installer. Installation is an explicit administrator action; restart afterward.'
