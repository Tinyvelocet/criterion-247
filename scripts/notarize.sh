#!/bin/bash
# Notarize Criterion24/7 for frictionless distribution.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application).
#      Verify:  security find-identity -v -p codesigning  → shows "Developer ID Application: …"
#   2. Notarization credentials — pick ONE method and export the env vars:
#
#      Method A — App Store Connect API key (recommended, no app password):
#        - developer.apple.com ▸ Account ▸ Users & Access ▸ Keys ▸ + ▸
#          enable "Developer ID" + "Notary Services", download the .p8 (Key ID, Issuer ID shown).
#        export ASC_KEY_ID=ABCDEF1234
#        export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#        export ASC_API_KEY=/path/to/AuthKey_ABCDEF1234.p8
#
#      Method B — Apple ID + app-specific password:
#        - appleid.apple.com ▸ Sign-In & Security ▸ App-Specific Passwords ▸ +  (name it "notarytool")
#        export APPLE_ID=you@icloud.com
#        export APPLE_TEAM_ID=WW4KSN8655        # your team id (use your real one)
#        export APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx   # the app-specific password (NOT your account password)
#
# Usage:  bash scripts/notarize.sh [Release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"

# 0. Find a Developer ID Application identity.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -oE 'Developer ID Application: [^(]+' | head -1 | sed 's/^Developer ID Application: //')
if [ -z "$IDENTITY" ]; then
  echo "✗ No 'Developer ID Application' certificate found." >&2
  echo "  Get one: Xcode ▸ Settings ▸ Accounts ▸ your team ▸ Manage Certificates ▸ + ▸ Developer ID Application" >&2
  exit 1
fi
echo "▸ Using identity: $IDENTITY"

echo "▸ xcodegen generate"
xcodegen generate >/dev/null

echo "▸ build signed ($CONFIG)"
xcodebuild -project Criterion247.xcodeproj -scheme Criterion247 \
  -configuration "$CONFIG" -derivedDataPath ./build \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID:-WW4KSN8655}" \
  CODE_SIGN_IDENTITY="Developer ID Application: $IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build 2>&1 | grep -E 'error:|BUILD' | grep -vE 'note:' || true

APP="build/Build/Products/$CONFIG/Criterion247.app"
[ -d "$APP" ] || { echo "✗ build failed: no app at $APP" >&2; exit 1; }

echo "▸ verifying Developer ID signature (must NOT say 'adhoc')"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Identifier=|Signature=|TeamIdentifier=' | head -5
codesign -dv "$APP" 2>&1 | grep -q 'flags=0x2(adhoc)' && { echo "✗ app is ad-hoc signed, not Developer ID" >&2; exit 1; } || true

# 1. Compress for notarization (Apple wants a zip).
ZIP="dist/Criterion247-${CONFIG}.zip"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 2. Notarize — pick method from available env.
echo "▸ submitting for notarization (this can take a few minutes)…"
if [ -n "${ASC_API_KEY:-}" ]; then
  xcrun notarytool submit "$ZIP" \
    --key "$ASC_API_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait
elif [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  xcrun notarytool submit "$ZIP" \
    --apple-id "${APPLE_ID:?}" --password "$APPLE_APP_PASSWORD" --team-id "${APPLE_TEAM_ID:?}" \
    --wait
else
  echo "✗ notarization credentials not set. See header of this script (ASC_* or APPLE_*)." >&2
  exit 1
fi

# 3. Staple the ticket onto the app bundle.
echo "▸ stapling notarization ticket…"
xcrun stapler staple "$APP" && xcrun stapler validate "$APP"

# 4. Final full-sign app containing the stapled ticket → re-zip for release.
rm -f "dist/Criterion247-1.1-macOS.zip"
ditto -c -k --keepParent "$APP" "dist/Criterion247-1.1-macOS.zip"

echo
echo "✓ Notarized + stapled."
echo "  App:     $APP"
echo "  Release: dist/Criterion247-1.1-macOS.zip  (drag to users — no Gatekeeper override)"
echo "  Widget will register on users' Macs when they add it."