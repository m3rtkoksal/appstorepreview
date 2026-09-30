#!/bin/bash
# Builds a double-clickable .app bundle at macos-app/dist/App Store Görselleri.app
# Requires Xcode or the Xcode Command Line Tools (swift 5.9+, macOS 13+).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release 2>&1 | tail -n 5

APP="dist/App Store Görselleri.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/AppStoreShots" "$APP/Contents/MacOS/AppStoreShots"
cp Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc signature so Gatekeeper lets a locally built app launch.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo
echo "Hazır: $(pwd)/$APP"
echo "Açmak için: open \"$APP\""
