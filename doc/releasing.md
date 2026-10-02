# Releasing

A release is one version of two things that ship together: the Dart package
on pub.dev (the `flutter2figma` CLI and library) and the Figma plugin (a zip
on the GitHub release, and later Figma Community). Both are cut from the same
`vX.Y.Z` tag.

## Versioning

- **Package:** semantic versioning, `0.x` while in beta. Bump the minor
  version (`0.2.0` → `0.3.0`) for new features or anything that changes what
  an export produces, the patch version (`0.2.0` → `0.2.1`) for fixes only.
- **`design.json` / IR format:** a separate integer (`designVersion` in
  `lib/src/figma/renderer.dart`, `irVersion` in `lib/src/ir/model.dart`,
  `DESIGN_VERSION` in `figma-plugin/src/design.ts`). Bump it when an older
  plugin would misread new files; the plugin then asks people to update. Say
  so in the changelog.
- **pub.dev versions are permanent.** A published version can't be deleted
  or replaced, only retracted (within 7 days) and superseded. Check twice.

## Before you start

- `main` is green on CI.
- Work since the last release is listed under `## Unreleased` at the top of
  `CHANGELOG.md`.
- You have imported a fresh export into the real Figma desktop app at least
  once (`example/` and `build/showcase/runtime/design.json` from
  `tool/stress.sh`). The mock catches API misuse, not everything Figma does.

## Steps

1. **Version.** Set the new version in all three places:

   | File | Line |
   | --- | --- |
   | `pubspec.yaml` | `version: X.Y.Z` |
   | `lib/src/version.dart` | `const packageVersion = 'X.Y.Z';` |
   | `figma-plugin/package.json` | `"version": "X.Y.Z"` |

   Rename `## Unreleased` in `CHANGELOG.md` to `## X.Y.Z`. The release notes
   on GitHub are taken from that section. On tag builds,
   `test/version_test.dart` fails if the versions or the changelog heading
   disagree.

2. **Goldens.** The generator version is part of the golden:

   ```sh
   UPDATE_GOLDENS=1 dart test test/cli
   git diff test/goldens/   # only the version should change
   ```

3. **Verify everything locally:**

   ```sh
   dart format --output=none --set-exit-if-changed lib bin test
   dart analyze --fatal-infos
   dart test
   (cd figma-plugin && npm run typecheck && npm test)
   (cd example && fvm flutter test)
   tool/stress.sh
   dart pub publish --dry-run   # the only warning allowed is uncommitted files
   ```

4. **Commit and push**, then wait for CI to pass on `main`:

   ```sh
   git commit -am "Release X.Y.Z"
   git push origin main
   ```

5. **Tag and push the tag:**

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

   This starts two workflows:
   - **Release Figma plugin** (`release-plugin.yml`): runs the plugin tests,
     builds `flutter2figma-figma-plugin-X.Y.Z.zip`, and creates the GitHub
     release with the changelog section as notes.
   - **Publish to pub.dev** (`publish.yml`): runs CI again, then publishes
     the package through pub.dev's automated publishing. Until the package
     exists on pub.dev it skips publishing with a notice (see below).

6. **Publish to pub.dev.**
   - **First release only:** publish by hand from the tagged commit, signed
     in with the Google account that should own the package:

     ```sh
     git checkout vX.Y.Z
     dart pub publish
     git checkout main
     ```

     Then turn on automated publishing so later tags publish themselves:
     pub.dev → flutter2figma → **Admin** → **Automated publishing** → enable
     publishing from GitHub Actions, repository
     `CarlosMarioM/flutter2figma`, tag pattern `v{{version}}`.
   - **Later releases:** nothing to do. The tag publishes it. Check
     <https://pub.dev/packages/flutter2figma> once the workflow is done.

7. **Figma plugin.**
   - The zip on the GitHub release is what people install today
     (**Plugins → Development → Import plugin from manifest…**).
   - On Figma Community: in the Figma desktop app, **Plugins → Development →
     Flutter2Figma → Publish** (first time: fill in the form from
     `figma-plugin/listing/LISTING.md`, with `icon.png` and `cover.png`).
     For an update, publish a new version with a short note from the
     changelog. Figma reviews it before it goes live.
   - Re-check the data-security answers in `LISTING.md` if the plugin's
     capabilities changed (network access, storage).

8. **Open the next version.** Add an empty `## Unreleased` section at the
   top of `CHANGELOG.md` and commit.

## If something goes wrong

- **The plugin release failed or needs rebuilding:** Actions → **Release
  Figma plugin** → **Run workflow** with the existing tag. It recreates the
  zip without retagging.
- **A tag points at the wrong commit and nothing was published to pub.dev
  yet:** delete and recreate it.

  ```sh
  git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z
  git tag vX.Y.Z <commit> && git push origin vX.Y.Z
  ```

- **A broken version reached pub.dev:** retract it within 7 days
  (`dart pub retract`, or pub.dev → Versions), fix, and release a patch
  version. Don't move the tag of a published version.
- **Automated publishing failed:** the workflow log says why (most often the
  tag doesn't match `v{{version}}`, or the version in `pubspec.yaml` wasn't
  bumped). Fix forward with a new patch version.
