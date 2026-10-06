# Flutter2Figma Figma plugin

Imports the `design.json` written by
[`flutter2figma export`](https://pub.dev/packages/flutter2figma) into Figma
as editable frames, with auto layout, color variables with Light and Dark
modes, text and effect styles, and components.

This folder is not part of the pub package. It is released as a zip on each
GitHub release.

## Install (users)

Install it from
[Figma Community](https://www.figma.com/community/plugin/1687559887675755742).

A release can reach Figma Community a few days after it's out (Figma reviews
each version). To use a new version before then:

1. Download `flutter2figma-figma-plugin-<version>.zip` from the
   [latest release](https://github.com/CarlosMarioM/flutter2figma/releases/latest)
   and unzip it.
2. In the Figma **desktop** app, choose **Plugins → Development → Import plugin
   from manifest…** and pick `manifest.json`.
3. Run **Plugins → Development → Flutter2Figma** and drop a `design.json` on
   its window.

The plugin's window shows its version. To remove copies you no longer use,
choose **Plugins → Development → Manage plugins in development**.

## Develop

```sh
npm install
npm run watch       # rebuild dist/code.js on save, then re-run the plugin in Figma
npm run typecheck
npm test            # imports the golden design.json into a strict Figma mock
npm run package     # release/flutter2figma-figma-plugin-<version>.zip
```

Import `manifest.json` from this folder once (step 2 above) to run your
local build. **Plugins → Development → Open console** shows errors.

| File | |
| --- | --- |
| `manifest.json` | Plugin manifest. The `id` was issued by Figma; Figma rejects made-up IDs. `networkAccess` is `none`. |
| `ui.html` | Drop-zone window. It sends the file's text to the plugin and shows the result. |
| `src/code.ts` | Entry point: UI messages → `importDesign`. |
| `src/design.ts` | `design.json` types and `parseDesign` (checks the format and version). |
| `src/importer.ts` | Builds nodes, components and instances. A pure function of a `PluginAPI`, so it is testable. |
| `src/design-system.ts` | Upserts the variable collection, variables and styles; binds paints to variables. |
| `test/figma-mock.ts` | In-memory Figma API that throws where Figma does. |
| `scripts/package.sh` | Builds the release zip. |
| `listing/` | Figma Community listing text, icon and cover. |

The format the plugin reads is specified in
[`doc/design-json.md`](../doc/design-json.md). Figma's API ordering rules
and the mock's checks are described in
[`doc/development.md`](../doc/development.md#plugin-development).

To import other exports through the strict mock:

```sh
F2F_DESIGNS=/path/a/design.json:/path/b/design.json npm test
```

## Release

Pushing a `v*` tag runs `.github/workflows/release-plugin.yml`. It
typechecks and tests, builds the zip, and attaches it to the GitHub Release.
The full checklist, including Figma Community, is in
[doc/releasing.md](../doc/releasing.md).
