#!/bin/bash
#
# Packages blipsy.app into a drag-to-Applications .dmg for a GitHub release.
# Output: build/blipsy.dmg
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/make-app.sh

STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "build/blipsy.app" "$STAGE/blipsy.app"
ln -s /Applications "$STAGE/Applications"      # the drag-to-install target

rm -f "build/blipsy.dmg"
hdiutil create -volname "blipsy" -srcfolder "$STAGE" -ov -format UDZO "build/blipsy.dmg" >/dev/null
rm -rf "$STAGE"

echo "==> Built build/blipsy.dmg"
echo "    Attach it to a GitHub release. Users open it and drag blipsy.app to Applications."
