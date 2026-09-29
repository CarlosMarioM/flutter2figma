#!/usr/bin/env python3
"""Writes a Flutter test into a *copy* of an app that dumps the theme Flutter
resolves for its MaterialApp, in the shape `flutter2figma theme` prints.

usage: gen_theme_test.py <app> <copy> <file-with-MaterialApp>

The `theme:` argument of the first MaterialApp in <file> is copied verbatim
into `MaterialApp(theme: <expr>)`. Every library of the app is imported so
the expression resolves (unused imports are fine in a test).
"""
import os
import re
import sys

app, copy, app_file = sys.argv[1], sys.argv[2], sys.argv[3]

src = open(os.path.join(app, app_file)).read()
start = src.index('theme:', src.index('MaterialApp')) + len('theme:')
depth, end = 0, start
while True:
    c = src[end]
    if c in '([{':
        depth += 1
    elif c in ')]}':
        if depth == 0:
            break
        depth -= 1
    elif c == ',' and depth == 0:
        break
    end += 1
expr = src[start:end].strip()

package = re.search(r'^name:\s*(\S+)', open(os.path.join(app, 'pubspec.yaml')).read(), re.M).group(1)
imports = []
lib = os.path.join(app, 'lib')
for root, _, files in os.walk(lib):
    for f in sorted(files):
        if not f.endswith('.dart') or f.endswith(('.g.dart', '.freezed.dart')):
            continue
        path = os.path.join(root, f)
        if open(path).read(400).lstrip().startswith('part of'):
            continue
        imports.append(f"import 'package:{package}/{os.path.relpath(path, lib)}';")

template_path = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'theme_dump_test.dart.tmpl')
test = open(template_path).read().replace('/*IMPORTS*/', '\n'.join(imports)).replace('/*THEME*/', expr)
os.makedirs(os.path.join(copy, 'test'), exist_ok=True)
open(os.path.join(copy, 'test', 'f2f_theme_dump_test.dart'), 'w').write(test)
print(f'theme: {" ".join(expr.split())[:100]}')
