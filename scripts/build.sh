#!/bin/bash
# Build + install Criterion24/7.
#
# Two modes:
#   SIGNED (default when a DEVELOPMENT_TEAM + cert is present) — the ONLY way the
#     WIDGET works. Builds with your Apple team, installs to /Applications, and
#     macOS registers the widget extension. Use this unless you're just testing
#     the menu bar.
#   UNSIGNED (DEVELOPMENT_TEAM="" or CODE_SIGNING_ALLOWED=NO) — ad-hoc signed;
#     fine for the menu bar only, but the widget will NOT register on macOS.
#
# Usage:
#   bash scripts/build.sh [Release|Debug]        # signed, your team
#   DEVELOPMENT_TEAM= bash scripts/build.sh      # unsigned/ad-hoc (menu bar only)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
TEAM="${DEVELOPMENT_TEAM:-}"
# If no team given, fall back to whatever "Apple Development" identity we have.
if [ -z "$TEAM" ]; then
  TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '\(([A-Z0-9]{10})\)' | tail -1 | tr -d '()' || true)
fi

echo "▸ xcodegen generate"
xcodegen generate >/dev/null

if [ -n "$TEAM" ]; then
  echo "▸ SIGNED build ($CONFIG) with team $TEAM"
  xcodebuild -project Criterion247.xcodeproj -scheme Criterion247 \
    -configuration "$CONFIG" -derivedDataPath ./build \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build 2>&1 \
    | grep -E 'error:|warning:|BUILD' | grep -vE 'note:' || true
else
  echo "▸ unsigned build ($CONFIG) — menu bar only, widget will NOT register"
  xcodebuild -project Criterion247.xcodeproj -scheme Criterion247 \
    -configuration "$CONFIG" -derivedDataPath ./build \
    CODE_SIGNING_ALLOWED=NO build 2>&1 \
    | grep -E 'error:|warning:|BUILD' | grep -vE 'note:' || true
fi

APP="build/Build/Products/$CONFIG/Criterion247.app"
if [ ! -d "$APP" ]; then
  echo "! build failed — no app at $APP" >&2; exit 1
fi

# Install to /Applications — macOS only registers desktop widgets from here.
echo "▸ installing to /Applications"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
rm -rf "/Applications/Criterion247.app"
cp -R "$APP" /Applications/

# Ensure the nested widget extension is signed too.
codesign --verify --deep --strict "/Applications/Criterion247.app" \
  && echo "  ✓ signature verified (nested widget included)"
if [ -n "$TEAM" ]; then
  echo "✓ Installed /Applications/Criterion247.app (signed — widget will register)"
else
  echo "✓ Installed /Applications/Criterion247.app (ad-hoc — MENU BAR ONLY)"
  echo "  ⚠ For the widget to work, build with your team:  DEVELOPMENT_TEAM=<id> bash scripts/build.sh"
fi
echo "  Launch: open /Applications/Criterion247.app"
echo "  Widget: right-click desktop → Edit Widgets → search 'Criterion 24/7'."
echo "  Live widget data needs App Group 'group.dev.criterion247' registered in the Apple portal."