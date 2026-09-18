# Releasing blipsy

One command cuts a release: it bumps the version, runs the tests, builds the
`.dmg`, commits, tags, and publishes a GitHub release with the dmg attached.

## One-time setup

1. The project is a git repo with a GitHub remote named `origin`.
2. Install the GitHub CLI and sign in (so releases can be published):
   ```sh
   brew install gh
   gh auth login
   ```

## Cutting a release

Pick the bump based on what changed:

| Command | Version | Use when |
| :------ | :------ | :------- |
| `./scripts/release.sh patch` | 1.0.0 → 1.0.1 | bug fixes only |
| `./scripts/release.sh minor` | 1.0.0 → 1.1.0 | new features, nothing broken |
| `./scripts/release.sh major` | 1.0.0 → 2.0.0 | breaking changes |

That's it. The script:

1. checks the working tree is clean,
2. runs the regression suite (aborts if anything fails),
3. bumps `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`,
4. commits `Release vX.Y.Z`, tags it, and pushes the tag.

Pushing the tag triggers **GitHub Actions** (`.github/workflows/release.yml`), which
builds `blipsy.dmg` on a clean macOS runner and publishes the GitHub release with the
dmg attached and auto-generated notes. No local build needed, and it's reproducible.

The new version number shows up automatically in the app's **About** window.

(If the CI workflow isn't present, the script falls back to building the dmg and
publishing the release locally with `gh`.)

## Working with me

After I make a change you want shipped, just tell me, for example:

> release a patch

and I'll run `./scripts/release.sh patch` for you and report back the new version
and the release link. Say "minor" for a feature, "major" for a breaking change.

## If you don't have `gh` yet

The script still bumps the version, builds the dmg, commits, tags, and pushes. It
prints a reminder to attach `build/blipsy.dmg` to the release on GitHub by hand, or
you can install `gh` later and re-run.

## Notes

- Releases are **unsigned**. Users install fine (see the README's Install section)
  but clear a one-time Gatekeeper prompt. For a no-warning experience later, sign
  with a Developer ID and notarize; that needs a paid Apple Developer account.
- `CFBundleVersion` is a build counter that increments every release; the semantic
  version (`CFBundleShortVersionString`) is what users see.
