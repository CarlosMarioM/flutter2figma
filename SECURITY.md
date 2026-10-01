# Security

## Reporting a vulnerability

Please report it privately through
[GitHub security advisories](https://github.com/CarlosMarioM/flutter2figma/security/advisories/new)
rather than a public issue. Include the version (`flutter2figma --version`),
the steps to reproduce, and the impact. You'll get a reply as soon as
possible. Fixes are released as a new version, with a CHANGELOG entry.

## Security model

**The exporter** (`flutter2figma`, the pub package):
- reads Dart source under the project's `lib/`, resolving it with
  `package:analyzer`. It **never runs the project's code**, starts
  processes, or uses the network;
- writes only `design.json` and `ir.json`, to the output directory you give
  it (default `build/flutter2figma`).

Running it on an untrusted project is therefore no riskier than opening that
project's source in an editor.

**The Figma plugin** (`figma-plugin/`):
- declares `networkAccess: none`, so it can't make network requests;
- reads only the `design.json` you drop on it, and renders text with
  `textContent`, never as HTML;
- writes only to the open Figma file: layers, local variables and styles,
  and per-layer plugin data with the source widget names and `file:line`.

**Development tools** (`tool/`, not in the package): `tool/validate_app.sh`
**runs the target app's code** in a Flutter test, to read the theme
Flutter resolves. Only use it on apps you trust.
