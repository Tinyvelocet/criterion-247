#!/bin/bash
# Frictionless build — no Apple developer team required.
#
# Builds the app unsigned and ad-hoc signs it so it runs locally without you
# ever needing to pick a Team in Xcode. This is fine for personal use.
# For public distribution with widgets working + live data, you still need a
# team + App Group (see README), but for local install this just works.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
echo "▸ xcodegen generate"
xcodegen generate >/dev/null

echo "▸ build ($CONFIG, unsigned)"
xcodebuild -project Criterion247.xcodeproj -scheme Criterion247 \
  -configuration "$CONFIG" -derivedDataPath ./build \
  CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E 'error:|warning:|BUILD' | grep -vE 'note:' || true

APP="build/Build/Products/$CONFIG/Criterion247.app"
if [ ! -d "$APP" ]; then
  echo "! build failed — no app at $APP" >&2; exit 1
fi

echo "▸ ad-hoc signing (local run, no team)"
codesign --force --deep --sign - "$APP"

echo "▸ installing to /Applications (removes quarantine)"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
rm -rf "/Applications/Criterion247.app"
cp -R "$APP" /Applications/
echo "✓ Installed /Applications/Criterion247.app"
echo "  Launch: open /Applications/Criterion247.app"
echo
echo "  Widget: right-click desktop → Edit Widgets → add 'Criterion 24/7'."
echo "  For live widget data, register App Group 'group.dev.criterion247' in your"
echo "  Apple Developer portal, then build normally from Xcode with your team."