import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter2figma/ir.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Figma rejects images larger than this on either side.
const _maxFigmaPixels = 4096;

/// Larger images are left out so `design.json` stays importable.
const _maxBytes = 8 * 1024 * 1024;

/// Source files larger than this aren't read at all.
const _maxSourceBytes = 64 * 1024 * 1024;

/// Finds the image files a Flutter project's asset names refer to, the way
/// Flutter's asset bundle does: relative to the project (or to a package
/// for `packages/<name>/...` and `package:` arguments), preferring the
/// highest resolution variant (`2.0x/`, `3.0x/` folders next to the file).
class ProjectAssets {
  ProjectAssets(this.root);

  final String root;
  final _cache = <String, AssetLookup>{};
  late final Map<String, String> _packages = _readPackages();

  /// The image behind asset [name], or why it can't be exported.
  AssetLookup resolve(String name, {String? package}) {
    final key = package == null ? name : 'packages/$package/$name';
    return _cache[key] ??= _load(key);
  }

  AssetLookup _load(String key) {
    var base = root;
    var relative = key;
    final parts = p.posix.split(key);
    if (parts.length > 2 && parts.first == 'packages') {
      final package = _packages[parts[1]];
      if (package == null) {
        return AssetLookup.missing('package ${parts[1]} is not resolved');
      }
      base = package;
      // Package assets live under the package's lib/ unless listed at root.
      relative = p.posix.joinAll(parts.skip(2));
      if (!File(p.join(base, relative)).existsSync()) {
        relative = p.posix.join('lib', relative);
      }
    }

    final (file, ratio) = _bestVariant(base, relative);
    if (file == null) return AssetLookup.missing('$key not found');
    if (file.lengthSync() > _maxSourceBytes) {
      return AssetLookup.missing('$key is too large to read');
    }
    final bytes = file.readAsBytesSync();
    final info = _identify(bytes);
    final IrImageAsset asset;
    if (info case (final format, final width, final height)
        when format == 'svg' ||
            (width <= _maxFigmaPixels && height <= _maxFigmaPixels)) {
      asset = IrImageAsset(
        key: key,
        format: format,
        width: width / ratio,
        height: height / ratio,
        data: bytes,
      );
    } else {
      // Formats Figma can't take (WebP, BMP, ...) become PNG, and images
      // over Figma's limit are scaled down; the logical size is unchanged.
      final decoded = _decode(bytes);
      if (decoded == null) {
        return AssetLookup.missing('$key is not an image Figma can show');
      }
      final scale = _maxFigmaPixels / max(decoded.width, decoded.height);
      final fitted = scale >= 1
          ? decoded
          : img.copyResize(
              decoded,
              width: (decoded.width * scale).round(),
              height: (decoded.height * scale).round(),
              interpolation: img.Interpolation.average,
            );
      final jpeg = info?.$1 == 'jpeg';
      asset = IrImageAsset(
        key: key,
        format: jpeg ? 'jpeg' : 'png',
        width: decoded.width / ratio,
        height: decoded.height / ratio,
        data: jpeg ? img.encodeJpg(fitted, quality: 90) : img.encodePng(fitted),
      );
    }
    if (asset.data.length > _maxBytes) {
      return AssetLookup.missing(
        '$key is ${(asset.data.length / 1048576).toStringAsFixed(1)} MB, '
        'too large to embed',
      );
    }
    return AssetLookup._(asset, null);
  }

  /// The file for [relative] at the highest available device pixel ratio.
  (File?, double) _bestVariant(String base, String relative) {
    final main = File(p.join(base, relative));
    final dir = Directory(p.dirname(main.path));
    File? best = main.existsSync() ? main : null;
    var bestRatio = 1.0;
    if (dir.existsSync()) {
      final variant = RegExp(r'^(\d+(?:\.\d+)?)x$');
      for (final entry in dir.listSync().whereType<Directory>()) {
        final ratio = double.tryParse(
          variant.firstMatch(p.basename(entry.path))?.group(1) ?? '',
        );
        if (ratio == null || ratio <= bestRatio) continue;
        final candidate = File(p.join(entry.path, p.basename(relative)));
        if (candidate.existsSync()) {
          best = candidate;
          bestRatio = ratio;
        }
      }
    }
    return (best, bestRatio);
  }

  Map<String, String> _readPackages() {
    final config = File(p.join(root, '.dart_tool', 'package_config.json'));
    if (!config.existsSync()) return {};
    try {
      final json = jsonDecode(config.readAsStringSync()) as Map;
      return {
        for (final pkg in (json['packages'] as List).cast<Map>())
          pkg['name'] as String: config.parent.uri
              .resolve(pkg['rootUri'] as String)
              .toFilePath(),
      };
    } on FormatException {
      return {};
    }
  }
}

/// Decoders throw assorted errors on files they don't understand.
img.Image? _decode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

/// A resolved asset, or the reason there is none.
class AssetLookup {
  AssetLookup._(this.asset, this.problem);
  AssetLookup.missing(String problem) : this._(null, problem);

  final IrImageAsset? asset;
  final String? problem;
}

/// Format and pixel size from the file header.
(String, int, int)? _identify(Uint8List b) {
  final d = ByteData.sublistView(b);
  bool starts(List<int> magic) =>
      b.length >= magic.length &&
      [for (var i = 0; i < magic.length; i++) b[i] == magic[i]].every((x) => x);

  if (starts([0x89, 0x50, 0x4E, 0x47]) && b.length >= 24) {
    return ('png', d.getUint32(16), d.getUint32(20));
  }
  if (starts([0x47, 0x49, 0x46]) && b.length >= 10) {
    return (
      'gif',
      d.getUint16(6, Endian.little),
      d.getUint16(8, Endian.little),
    );
  }
  if (starts([0xFF, 0xD8])) {
    // Walk the segments to the frame header (SOF0..SOF15, minus DHT/JPG/DAC).
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = d.getUint16(i + 2);
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) return ('jpeg', d.getUint16(i + 7), d.getUint16(i + 5));
      i += 2 + length;
    }
    return null;
  }
  final head = utf8.decode(
    b.sublist(0, b.length < 4096 ? b.length : 4096),
    allowMalformed: true,
  );
  final svg = RegExp(r'<svg\b[^>]*>', caseSensitive: false).firstMatch(head);
  if (svg != null) {
    final tag = svg.group(0)!;
    double? attr(String name) => double.tryParse(
      RegExp('\\b$name\\s*=\\s*["\']\\s*([\\d.]+)').firstMatch(tag)?.group(1) ??
          '',
    );
    final viewBox = RegExp(
      r'viewBox\s*=\s*["'
      "'"
      r']([^"'
      "'"
      r']+)',
    ).firstMatch(tag)?.group(1)?.trim().split(RegExp(r'[\s,]+'));
    final vw = viewBox?.length == 4 ? double.tryParse(viewBox![2]) : null;
    final vh = viewBox?.length == 4 ? double.tryParse(viewBox![3]) : null;
    final w = attr('width') ?? vw ?? 100;
    final h = attr('height') ?? vh ?? 100;
    return ('svg', w.round(), h.round());
  }
  return null;
}
