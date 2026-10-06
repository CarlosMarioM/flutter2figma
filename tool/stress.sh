#!/usr/bin/env bash
# Stress test: exports the showcase app (showcase/) both ways and imports
# both designs through the plugin's strict Figma mock.
#
#   tool/stress.sh [out-dir]       (default: build/showcase)
#
# Writes <out>/static/design.json, <out>/runtime/design.json and Flutter's
# own render of every screen in <out>/screenshots/, to compare with the
# Figma import.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/build/showcase}
mkdir -p "$out"
out=$(cd "$out" && pwd)

if [ -f "$root/.fvmrc" ] && command -v fvm >/dev/null; then flutter=(fvm flutter); else flutter=(flutter); fi
(cd "$root/showcase" && "${flutter[@]}" pub get >/dev/null)

cd "$root"
echo "== Static export"
dart run bin/flutter2figma.dart export showcase --static -o "$out/static" | tail -8
echo "== Runtime export"
dart run bin/flutter2figma.dart export showcase --runtime \
  --screenshots "$out/screenshots" -o "$out/runtime" | tail -8
echo "== Figma import (mock)"
(cd figma-plugin && F2F_DESIGNS="$out/static/design.json:$out/runtime/design.json" \
  npm test 2>&1 | grep -E '^(not )?ok .*imports /|^# (pass|fail)')
