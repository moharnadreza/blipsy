#!/bin/bash
#
# Cuts a new blipsy release: bumps the version, runs tests, builds the .dmg,
# commits + tags, and (if `gh` is set up) publishes a GitHub release with the dmg.
#
# Usage:  ./scripts/release.sh <patch|minor|major>
#   patch  1.0.0 -> 1.0.1   bug fixes
#   minor  1.0.0 -> 1.1.0   new features, backwards compatible
#   major  1.0.0 -> 2.0.0   breaking changes
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUMP="${1:-}"
case "$BUMP" in
  patch|minor|major) ;;
  *) echo "usage: $0 <patch|minor|major>"; exit 1 ;;
esac

PB=/usr/libexec/PlistBuddy
CURRENT=$("$PB" -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$("$PB" -c "Print :CFBundleVersion" Info.plist)

IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac
NEW="$MAJOR.$MINOR.$PATCH"
NEW_BUILD=$((BUILD + 1))
TAG="v$NEW"

echo "==> Releasing $CURRENT -> $NEW (build $NEW_BUILD)"

# Refuse to release on a dirty tree (except the version bump we are about to make).
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "!! Working tree has uncommitted changes. Commit or stash them first."
  exit 1
fi

echo "==> Running tests"
swift run blipsy --test >/dev/null || { echo "!! Tests failed. Aborting."; exit 1; }

echo "==> Bumping version in Info.plist"
"$PB" -c "Set :CFBundleShortVersionString $NEW" Info.plist
"$PB" -c "Set :CFBundleVersion $NEW_BUILD" Info.plist

echo "==> Committing and tagging"
git add Info.plist
git commit -m "Release $TAG"
git tag "$TAG"

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "==> No 'origin' remote. Committed + tagged locally."
  echo "    Add a remote, then: git push && git push --tags"
  exit 0
fi

git push
git push --tags

if [ -f ".github/workflows/release.yml" ]; then
  # GitHub Actions builds the .dmg and publishes the release on the tag push.
  echo "==> Pushed $TAG. GitHub Actions is building and publishing the release."
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && echo "    Watch: https://github.com/$REPO/actions"
elif command -v gh >/dev/null 2>&1; then
  # No CI workflow: build and publish locally.
  echo "==> Building the .dmg locally"
  ./scripts/make-dmg.sh >/dev/null
  echo "==> Creating GitHub release"
  gh release create "$TAG" build/blipsy.dmg --title "blipsy $TAG" --generate-notes
  echo "==> Done. Release $TAG is live."
else
  echo "==> Pushed $TAG. Install 'gh' or upload a dmg (./scripts/make-dmg.sh) to the release."
fi
