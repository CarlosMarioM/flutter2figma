#!/usr/bin/env bash
# Validates flutter2figma against a real Flutter app, without modifying it.
#
#   tool/validate_app.sh <app-dir> <file-with-MaterialApp> [out-dir]
#
# 1. Theme: copies the app to a temp dir, runs a Flutter test there that
#    dumps the theme Flutter resolves, and diffs it with `flutter2figma theme`.
# 2. Export: runs `flutter2figma export` and summarizes screens, nodes,
#    placeholders and diagnostics.
# 3. Figma: imports the design.json through the plugin's strict Figma mock.
#
# Requires the app to be resolved already (`flutter pub get`) and FVM.
set -euo pipefail

app=$(cd "$1" && pwd)
app_file=$2
root=$(cd "$(dirname "$0")/.." && pwd)
out=${3:-$(mktemp -d)}
copy=$(mktemp -d)
trap 'rm -rf "${copy:?}"' EXIT
mkdir -p "$out"

echo "== Theme ground truth"
rsync -a --exclude /.git --exclude /build --exclude /ios --exclude /android \
  --exclude /macos --exclude /web --exclude /windows --exclude /linux \
  --exclude /test "$app/" "$copy/"
python3 "$root/tool/validate/gen_theme_test.py" "$app" "$copy" "$app_file"
(cd "$copy" && F2F_OUT="$out/theme.flutter.json" \
  fvm flutter test test/f2f_theme_dump_test.dart >"$out/theme.flutter.log" 2>&1) ||
  { echo "Flutter theme dump failed; see $out/theme.flutter.log"; exit 1; }
(cd "$root" && dart run flutter2figma theme "$app" >"$out/theme.ours.json" 2>/dev/null)
python3 - "$out/theme.flutter.json" "$out/theme.ours.json" <<'EOF'
import json, sys
flutter, ours = (json.load(open(p)) for p in sys.argv[1:3])
diffs = []
def walk(a, b, path):
    if isinstance(a, dict):
        for k in a:
            walk(a[k], b.get(k) if isinstance(b, dict) else None, f'{path}.{k}')
    elif a != b:
        diffs.append(f'  {path}: flutter={a!r} flutter2figma={b!r}')
walk(flutter, ours, '')
print(f'{len(diffs)} differences')
print('\n'.join(diffs[:40]))
EOF

echo "== Export"
(cd "$root" && dart run flutter2figma export "$app" -o "$out" -v >"$out/export.log" 2>&1)
python3 - "$out/ir.json" "$out/export.log" <<'EOF'
import json, re, sys
doc = json.load(open(sys.argv[1]))
def count(n):
    kids = [count(c) for c in n.get('children', [])]
    return (1 + sum(k[0] for k in kids),
            (n['name'].startswith('⚠')) + sum(k[1] for k in kids))
for s in doc['screens']:
    nodes, placeholders = count(s['root'])
    print(f"  {s['name']:32s} nodes={nodes:4d} placeholders={placeholders}")
log = open(sys.argv[2]).read()
for level in ('error', 'warning'):
    lines = re.findall(rf'^\s+{level}\s+(.*)$', log, re.M)
    print(f'{len(lines)} {level}s')
    for l in lines[:20]:
        print('  ' + l)
EOF

echo "== Figma import (strict mock)"
(cd "$root/figma-plugin" && F2F_DESIGNS="$out/design.json" npm test 2>&1 | grep -E '^(not )?ok .*imports /|# (pass|fail)')

echo "Output: $out"
