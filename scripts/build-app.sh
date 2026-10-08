#!/usr/bin/env bash
# Builds SubwayMenuBar with Swift Package Manager and wraps the binary in a minimal
# .app bundle at build/SubwayMenuBar.app. An .app bundle (with Info.plist) is
# required for macOS to show the location permission prompt and to keep the
# app out of the Dock.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/SubwayMenuBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SubwayMenuBar" "$APP/Contents/MacOS/SubwayMenuBar"
cp -R "$BIN_DIR/SubwayMenuBar_SubwayMenuBar.bundle" "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so TCC (location permission) remembers the decision across launches.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
