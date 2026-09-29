#!/usr/bin/env python3
"""Writes a Flutter test into a *copy* of an app that dumps the theme Flutter
resolves for its MaterialApp, in the shape `flutter2figma theme` prints.

usage: gen_theme_test.py <app> <copy> <file-with-MaterialApp> root|expression

root:       pumps the app's real root widget, the argument of `runApp(...)`
            in lib/main.dart. Themes that depend on runtime state (a cubit's
            initial state, ...) resolve exactly as in the app.
expression: pumps `MaterialApp(theme: <expr>)` with the `theme:` argument of
            the first MaterialApp in <file> copied verbatim. For apps whose
            root can't be pumped in a test (async setup, plugins, ...).

Every library of the app is imported so the code resolves (unused imports
are fine in a test).
"""
import os
import re
import sys

app, copy, app_file, mode = sys.argv[1:5]


def argument_after(src, start):
    """The argument expression starting at src[start], up to `,` or `)`."""
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
    return src[start:end].strip()


if mode == 'root':
    main = open(os.path.join(app, 'lib', 'main.dart')).read()
    subject = argument_after(main, main.index('runApp(') + len('runApp('))
else:
    src = open(os.path.join(app, app_file)).read()
    expr = argument_after(src, src.index('theme:', src.index('MaterialApp')) + len('theme:'))
    subject = f'MaterialApp(theme: {expr}, home: Scaffold(body: Builder(builder: (_) => const SizedBox())))'

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
flutter_import = "import 'package:flutter/material.dart';" if mode == 'expression' else ''
test = (open(template_path).read()
        .replace('/*FLUTTER_IMPORT*/', flutter_import)
        .replace('/*IMPORTS*/', '\n'.join(imports))
        .replace('/*SUBJECT*/', subject))
os.makedirs(os.path.join(copy, 'test'), exist_ok=True)
open(os.path.join(copy, 'test', 'f2f_theme_dump_test.dart'), 'w').write(test)
print(f'{mode}: {" ".join(subject.split())[:100]}')
