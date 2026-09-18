#!/bin/bash
#
# Builds blipsy and assembles it into a proper .app bundle (no Xcode required).
# Output: build/blipsy.app
#
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building (${CONFIG})"
swift build -c "${CONFIG}"

BIN=".build/${CONFIG}/blipsy"
APP="build/blipsy.app"

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/blipsy"
cp "Info.plist" "${APP}/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi
if [ -f "Resources/icon.png" ]; then
  cp "Resources/icon.png" "${APP}/Contents/Resources/icon.png"
fi

# Ad-hoc sign so the bundle has a stable identity (helps notifications /
# login item on recent macOS). This is NOT a Developer ID signature.
if codesign --force --deep --sign - "${APP}" >/dev/null 2>&1; then
  echo "==> Ad-hoc signed"
else
  echo "==> codesign skipped (bundle will still run)"
fi

echo "==> Built ${APP}"
echo "    Run it:     open ${APP}"
echo "    First time: right-click -> Open to clear Gatekeeper"
