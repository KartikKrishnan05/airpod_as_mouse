#!/usr/bin/env bash
# Builds AirPods Mouse.app into ./build.
#
# macOS ties Accessibility permission to the app's code signature. With the
# default ad-hoc signature, every rebuild looks like a new app, so you'd have to
# re-grant Accessibility. To avoid that, sign with a stable identity:
#   SIGN_IDENTITY="Apple Development: you@example.com" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/AirPods Mouse.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AirPodsMouse "$APP/Contents/MacOS/AirPodsMouse"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
