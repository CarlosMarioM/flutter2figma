# Contributing

Thanks for helping! The full guide is in [doc/development.md](doc/development.md);
[doc/architecture.md](doc/architecture.md) explains how the pipeline works.

## Setup

Requirements:
- Dart 3.11 or later;
- [FVM](https://fvm.app), since the example app's Flutter version is pinned in `.fvmrc`;
- Node 18 or later, for the Figma plugin.

```sh
dart pub get
(cd example && fvm flutter pub get)          # the analyzer tests resolve it
(cd figma-plugin && npm install)
```

## Checks

```sh
dart analyze && dart format --set-exit-if-changed lib bin test
dart test                                    # all Dart tests
(cd example && fvm flutter test)             # theme ground truth (Flutter side)
(cd figma-plugin && npx tsc --noEmit && npm run build && npm test)
```

After an intentional change to the output, refresh the golden and review the
diff. The Figma plugin tests import the same file:

```sh
UPDATE_GOLDENS=1 dart test test/cli
```

To check behaviour on a real app without modifying it:

```sh
tool/validate_app.sh path/to/app lib/file_with_material_app.dart
```

## Releasing

1. Bump `version` in `pubspec.yaml` and `packageVersion` in
   `lib/src/version.dart`. `test/version_test.dart` fails if they differ.
2. Add a `## <version>` section at the top of `CHANGELOG.md`, with
   Added / Changed / Fixed entries. The version test checks this too.
3. Refresh the goldens (they record the generator version), then run
   `dart pub publish --dry-run`.
4. Commit, push, and push the tag `v<version>`. The *Release Figma plugin*
   workflow (`.github/workflows/release-plugin.yml`) then:
   - typechecks and tests the plugin;
   - builds `flutter2figma-figma-plugin-<version>.zip`;
   - creates the GitHub Release, with the CHANGELOG section as its notes.

   To release a tag that already exists, run the workflow from the Actions
   tab with that tag. `cd figma-plugin && npm run package` builds the same
   zip locally.
5. Publish the Dart package with `dart pub publish`.

Versioning follows [semver](https://semver.org). While the version is 0.x, a
minor bump may break the `design.json` / `ir.json` formats or the Dart API;
the format versions inside those files change with them.
