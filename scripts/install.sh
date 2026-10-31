#!/usr/bin/env bash
# GhostPin one-shot installer for macOS. Safe to re-run (needed every 7 days with a free Apple ID).
# Usage: scripts/install.sh            full install
#        scripts/install.sh --build-only   build only, do not touch the phone
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_ONLY=0; [ "${1:-}" = "--build-only" ] && BUILD_ONLY=1
say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
die() { printf "\n\033[31mSTOP: %s\033[0m\n" "$*"; exit 1; }

say "1/7 Checking Xcode"
xcodebuild -version >/dev/null 2>&1 || die "Xcode is not installed. Install it free from the Mac App Store, open it once, then re-run."
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || sudo xcodebuild -runFirstLaunch

say "2/7 Unpacking the idevice library"
scripts/prepare_idevice.sh

say "3/7 Setting up Python tools (pymobiledevice3)"
PY=""
for p in python3.13 python3.12 python3.11 python3.10; do command -v $p >/dev/null 2>&1 && PY=$(command -v $p) && break; done
if [ -z "$PY" ]; then
  command -v brew >/dev/null 2>&1 || die "Homebrew is needed. Install from https://brew.sh then re-run."
  brew install python@3.12; PY=$(brew --prefix python@3.12)/bin/python3.12
fi
VENV="$HOME/.ghostpin/venv"
[ -x "$VENV/bin/python" ] || { mkdir -p "$HOME/.ghostpin"; "$PY" -m venv "$VENV"; }
"$VENV/bin/pip" install -q --upgrade pip pymobiledevice3
PMD="$VENV/bin/pymobiledevice3"

if [ $BUILD_ONLY = 0 ]; then
  say "4/7 Finding your iPhone (plugged in, unlocked, 'Trust' tapped)"
  UDID=$("$PMD" usbmux list 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d[0]['Identifier'] if d else '')")
  [ -n "$UDID" ] || die "No iPhone found. Plug it in with a cable, unlock it, tap Trust, and re-run."
  echo "iPhone: $UDID"
  if ! "$PMD" amfi developer-mode-status 2>/dev/null | grep -qi true; then
    "$PMD" amfi reveal-developer-mode >/dev/null 2>&1 || true   # makes the switch appear on the phone
    die "Turn on Developer Mode: iPhone Settings > Privacy & Security > scroll down > Developer Mode > On, restart, confirm. Then re-run."
  fi

  say "5/7 Pairing (needs your Mac password once; keep your phone unlocked)"
  REC="$HOME/.pymobiledevice3/remote_$UDID.plist"
  if [ ! -f "$REC" ]; then
    sudo "$PMD" remote tunneld >/tmp/ghostpin-tunneld.log 2>&1 &
    TPID=$!
    for i in $(seq 1 60); do [ -f "$REC" ] && break; sleep 2; done
    sudo kill $TPID 2>/dev/null || true
    [ -f "$REC" ] || die "Pairing record not created. Make sure the phone is unlocked and you tapped Trust. Log: /tmp/ghostpin-tunneld.log"
  fi
  "$VENV/bin/python" scripts/make_rppairing.py "$UDID" "$HOME/.ghostpin/rppairing.plist"
fi

say "6/7 Building the app"
TEAM="${GHOSTPIN_TEAM:-}"
if [ -z "$TEAM" ]; then
  for id in $(security find-identity -v -p codesigning | grep "Apple Development" | sed -E 's/^ *[0-9]+\) ([0-9A-F]+) .*/\1/'); do
    TEAM=$(security find-certificate -c "$(security find-identity -v -p codesigning | grep $id | sed -E 's/.*"(.*)"/\1/')" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' | head -1)
    [ -n "$TEAM" ] && break
  done
fi
[ -n "$TEAM" ] || die "No Apple developer team found. Open GhostPin.xcodeproj in Xcode > Settings > Accounts, sign in with your Apple ID, pick your team under Signing & Capabilities, then re-run. (Or set GHOSTPIN_TEAM=<team id>.)"
BUNDLE="com.ghostpin.$(whoami | tr -cd 'a-z0-9')"
DEST="generic/platform=iOS"; [ $BUILD_ONLY = 0 ] && DEST="id=$UDID"
xcodebuild -project GhostPin.xcodeproj -scheme GhostPin -destination "$DEST" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
  -derivedDataPath "$ROOT/build" build | tail -3
[ $BUILD_ONLY = 1 ] && { say "Build finished (build-only)"; exit 0; }

say "7/7 Installing on your iPhone"
DEV=$(xcrun devicectl list devices 2>/dev/null | grep -i "$(echo $UDID | cut -c1-8)\|available\|connected" | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
[ -n "$DEV" ] || DEV=$(xcrun devicectl list devices 2>/dev/null | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
xcrun devicectl device install app --device "$DEV" "$ROOT/build/Build/Products/Debug-iphoneos/GhostPin.app"
xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$HOME/.ghostpin/rppairing.plist" --destination "Library/Application Support/rppairing.plist" >/dev/null
cat <<MSG

DONE. Now on the iPhone:
 1. Settings > General > VPN & Device Management > your Apple ID > Trust
 2. Install LocalDevVPN from the App Store, open it, tap Connect
 3. Open GhostPin > gear icon > Mode: On-device. Pick a place and tap Teleport.
MSG
