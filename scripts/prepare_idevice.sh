#!/usr/bin/env bash
# Unpacks the prebuilt idevice library into Native/IDevice.xcframework (no Rust needed).
# Built from https://github.com/jkcoxson/idevice (MIT) commit 8970209: see Native/README.md
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d Native/IDevice.xcframework ] && exit 0
mkdir -p /tmp/ghostpin-lib
gunzip -c Native/libidevice_ffi-ios-arm64.a.gz > /tmp/ghostpin-lib/libidevice_ffi.a
xcodebuild -create-xcframework -library /tmp/ghostpin-lib/libidevice_ffi.a \
  -headers Native/include -output Native/IDevice.xcframework >/dev/null
echo "idevice library ready"
