#!/usr/bin/env bash
# Builds the plugin and zips what Figma needs to import it:
#   release/flutter2figma-figma-plugin-<version>.zip
#     flutter2figma-figma-plugin/{manifest.json, ui.html, dist/code.js, INSTALL.txt}
#
#   scripts/package.sh [version]   (default: version from package.json)
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:-$(node -p "require('./package.json').version")}
version=${version#v}
name=flutter2figma-figma-plugin
stage=$(mktemp -d)
trap 'rm -rf "${stage:?}"' EXIT

npm run build >/dev/null

mkdir -p "$stage/$name/dist" release
cp manifest.json ui.html "$stage/$name/"
cp dist/code.js "$stage/$name/dist/"
cat >"$stage/$name/INSTALL.txt" <<EOF
Flutter2Figma Figma plugin $version

1. In the Figma desktop app, open any design file.
2. Plugins > Development > Import plugin from manifest...
   and choose manifest.json from this folder.
3. Run it: Plugins > Development > Flutter2Figma.
4. Drop the design.json written by \`flutter2figma export\` on its window.

The plugin has no network access; it only reads the file you drop.
Export tool: https://pub.dev/packages/flutter2figma
EOF

zip_path="release/$name-$version.zip"
rm -f "$zip_path"
(cd "$stage" && zip -qr - "$name") >"$zip_path"
echo "$zip_path"
