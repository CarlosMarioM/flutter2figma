# Figma Community listing

Everything to paste into Figma's publish dialog for the Flutter2Figma
plugin. Images: `icon.png` (128×128), `cover.png` (1920×1080), regenerated
with `./render.sh` from `icon.svg` / `cover.svg`.

## Name

Flutter2Figma

## Tagline

Turn your Flutter app's UI into editable Figma designs

## Description

Flutter2Figma rebuilds an existing Flutter UI in Figma: frames, text
layers, vector icons, color variables, text styles and components.

Beta: it works on real apps, but not every widget or app setup is covered
yet. Please report what doesn't come out right.

**How it works**

1. Install the exporter: `dart pub global activate flutter2figma`
2. In your Flutter project, run `flutter2figma export`. It reads your code
   and writes `design.json`. Add `--runtime` to have Flutter render each
   screen and export exactly what it draws.
3. Open this plugin and drop `design.json` on it.

**What you get**

- One frame per screen: with auto layout that follows Flutter's own sizing
  rules (padding, gaps, alignment, fill and hug), or Flutter's exact
  layout with `--runtime`.
- Your app's theme as **color variables with Light and Dark modes**.
  Switch a frame's mode and it recolors.
- Text styles from your text theme, and effect styles for elevation.
- Buttons as a component set with variants, and your repeated widgets as
  components with instances.
- Every layer remembers the Flutter widget and the `file:line` it came from.

**Good to know**

- Each import creates a new page. Variables and styles are reused and
  updated, not duplicated.
- UI that depends on runtime state is exported in its initial state, and
  anything that can't be drawn is clearly marked.
- Fonts are matched by name. Fonts that aren't installed are substituted,
  and the plugin tells you which.

**Privacy:** the plugin has no network access. It only reads the file you
drop.

Open source (MIT): https://github.com/CarlosMarioM/flutter2figma
Exporter on pub.dev: https://pub.dev/packages/flutter2figma

Flutter is a trademark of Google LLC. Flutter2Figma is an independent
project, not affiliated with or endorsed by Google or Figma.

## Tags

flutter, design system, handoff, auto layout, variables, components, developer, import

## Support contact

https://github.com/CarlosMarioM/flutter2figma/issues

## Data security answers

For Figma's plugin data-security questions. These are facts about the code
as of 0.1.0, checked in `manifest.json` and `src/`:

| Question | Answer |
| --- | --- |
| Does the plugin make network requests? | **No.** `manifest.json` declares `networkAccess.allowedDomains: ["none"]`, and the code has no `fetch`/XHR. |
| Does it collect, store or transmit user data? | **No.** It only reads the `design.json` the user selects or drops. |
| Does it use third-party services or analytics? | **No.** |
| Does it store data outside the document (e.g. `clientStorage`)? | **No.** |
| Does it store data in the document? | **Yes, only in the user's own file.** Each layer it creates gets plugin data with the Flutter widget names and source `file:line` it came from (the content of `design.json`). |
| Does it read existing document content? | Only local variable collections, text styles and effect styles, which it matches by name to update them instead of creating duplicates. |
| Does it require an account or sign-in? | **No.** |

## Before publishing

1. Check the plugin in Figma desktop. Import the release zip's
   `manifest.json`, drop `test/goldens/basic.design.json`, and confirm the
   screens, components, and Light/Dark variables.
2. Publish from **Plugins → Development → Manage plugins in development →
   Publish**, using the text and images above.
3. The plugin ID in `../manifest.json` (`1687559887675755742`) was generated
   by Figma (Plugins → Development → New plugin). Figma rejects IDs it
   didn't issue. Publish with this ID, so release zips update the published
   plugin instead of creating a new one.
4. Update the README's plugin install steps to point to the Community page.
