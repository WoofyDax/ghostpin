`libidevice_ffi-ios-arm64.a.gz` is the iOS (arm64) static build of `idevice-ffi` from
https://github.com/jkcoxson/idevice (MIT) at commit 8970209, built with:
`cargo build --release --target aarch64-apple-ios --no-default-features --features "ring full"`
(IPHONEOS_DEPLOYMENT_TARGET=17.0). `include/` holds its generated header and module map.
`scripts/prepare_idevice.sh` turns it into `IDevice.xcframework`.
