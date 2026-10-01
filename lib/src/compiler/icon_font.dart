import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// The icon fonts a Flutter project at [root] draws with, by family: Material
/// icons from its Flutter SDK, and `CupertinoIcons` when it depends on
/// `cupertino_icons`. Fonts that can't be found are left out.
///
/// Packages are located through `.dart_tool/package_config.json`, so the
/// project needs `flutter pub get`.
Map<String, IconFont> projectIconFonts(String root) {
  final config = File(p.join(root, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return {};
  final Map<String, String> packages;
  try {
    final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    final base = config.parent.uri;
    packages = {
      for (final pkg in (json['packages'] as List).cast<Map<String, Object?>>())
        pkg['name'] as String: base
            .resolve(pkg['rootUri'] as String)
            .toFilePath(),
    };
  } on FormatException {
    return {};
  }
  final fonts = <String, IconFont>{};
  void add(String family, String? path) {
    final font = path == null ? null : IconFont.load(path);
    if (font != null) fonts[family] = font;
  }

  final flutter = packages['flutter'];
  add(
    'MaterialIcons',
    flutter == null
        ? null
        : p.join(
            flutter,
            '..',
            '..',
            'bin',
            'cache',
            'artifacts',
            'material_fonts',
            'MaterialIcons-Regular.otf',
          ),
  );
  final cupertino = packages['cupertino_icons'];
  add(
    'CupertinoIcons',
    cupertino == null
        ? null
        : p.join(cupertino, 'assets', 'CupertinoIcons.ttf'),
  );
  return fonts;
}

/// Glyph outlines from an icon font, such as Flutter's `MaterialIcons`.
///
/// Reads OpenType fonts with CFF outlines (`OTTO`, what Flutter ships for
/// Material icons) and TrueType outlines (`glyf`). Only what icons need is
/// read: the character map, the outlines, and the metrics that place a glyph
/// in its box.
class IconFont {
  IconFont._(
    this._cmap,
    this._outline,
    this.unitsPerEm,
    this.ascender,
    this.descender,
    this._advances,
  );

  /// Parses [bytes], or returns null when they are not a supported font.
  static IconFont? parse(Uint8List bytes) {
    try {
      return _FontReader(ByteData.sublistView(bytes)).read();
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static IconFont? load(String path) {
    final file = File(path);
    return file.existsSync() ? parse(file.readAsBytesSync()) : null;
  }

  final Map<int, int> _cmap;
  final List<_Command> Function(int glyph) _outline;
  final int unitsPerEm;
  final int ascender;
  final int descender;
  final List<int> _advances;

  /// [codePoint] drawn the way Flutter's `Icon` draws it at [size]: the
  /// glyph set at `fontSize: size, height: 1`, centered in a [size] square.
  /// Null when the font has no such glyph; [IconGlyph.isEmpty] when it has
  /// no ink.
  IconGlyph? glyph(int codePoint, double size) {
    final gid = _cmap[codePoint];
    if (gid == null || gid == 0) return null;
    final scale = size / unitsPerEm;
    final advance = _advances.isEmpty
        ? unitsPerEm
        : _advances[math.min(gid, _advances.length - 1)];
    // height: 1 makes the line exactly fontSize tall, split between ascent
    // and descent in the font's own proportions.
    final lineUnits = ascender - descender;
    final baseline = lineUnits == 0 ? size : size * ascender / lineUnits;
    final dx = (size - advance * scale) / 2;

    final commands = _outline(gid);
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    void include(double x, double y) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }

    // Bounds of the outline itself, curve extremes included but not control
    // points: Figma sizes a vector the same way, so the two agree.
    final points = <List<double>>[];
    var cx = 0.0, cy = 0.0;
    for (final c in commands) {
      final m = <double>[
        for (var i = 0; i < c.args.length; i += 2) ...[
          dx + c.args[i] * scale,
          baseline - c.args[i + 1] * scale,
        ],
      ];
      points.add(m);
      if (m.isEmpty) continue;
      final ex = m[m.length - 2], ey = m[m.length - 1];
      include(ex, ey);
      if (c.op == 'Q') {
        for (final t in [
          _quadExtreme(cx, m[0], ex),
          _quadExtreme(cy, m[1], ey),
        ]) {
          if (t == null) continue;
          include(_quad(cx, m[0], ex, t), _quad(cy, m[1], ey, t));
        }
      } else if (c.op == 'C') {
        for (final t in [
          ..._cubicExtremes(cx, m[0], m[2], ex),
          ..._cubicExtremes(cy, m[1], m[3], ey),
        ]) {
          include(_cubic(cx, m[0], m[2], ex, t), _cubic(cy, m[1], m[3], ey, t));
        }
      }
      cx = ex;
      cy = ey;
    }
    if (commands.isEmpty) {
      return IconGlyph._(path: '', x: 0, y: 0, width: 0, height: 0);
    }

    String n(double v) {
      final s = v.toStringAsFixed(3);
      return s.contains('.')
          ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
          : s;
    }

    final d = StringBuffer();
    for (var i = 0; i < commands.length; i++) {
      final c = commands[i];
      if (d.isNotEmpty) d.write(' ');
      d.write(c.op);
      final p = points[i];
      for (var j = 0; j < p.length; j += 2) {
        d.write(' ${n(p[j] - minX)} ${n(p[j + 1] - minY)}');
      }
    }
    return IconGlyph._(
      path: d.toString(),
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }
}

double _quad(double a, double b, double c, double t) =>
    (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c;

double? _quadExtreme(double a, double b, double c) {
  final denominator = a - 2 * b + c;
  if (denominator == 0) return null;
  final t = (a - b) / denominator;
  return t > 0 && t < 1 ? t : null;
}

double _cubic(double a, double b, double c, double d, double t) {
  final u = 1 - t;
  return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
}

/// Parameters in (0, 1) where a cubic's derivative is zero.
Iterable<double> _cubicExtremes(double a, double b, double c, double d) {
  // Derivative / 3: qa t² + qb t + qc.
  final qa = -a + 3 * b - 3 * c + d;
  final qb = 2 * (a - 2 * b + c);
  final qc = b - a;
  final roots = <double>[];
  if (qa.abs() < 1e-12) {
    if (qb.abs() > 1e-12) roots.add(-qc / qb);
  } else {
    final disc = qb * qb - 4 * qa * qc;
    if (disc >= 0) {
      final r = math.sqrt(disc);
      roots
        ..add((-qb + r) / (2 * qa))
        ..add((-qb - r) / (2 * qa));
    }
  }
  return roots.where((t) => t > 0 && t < 1);
}

/// A glyph outline placed in an icon's box.
class IconGlyph {
  IconGlyph._({
    required this.path,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// SVG path data (`M`, `L`, `Q`, `C`, `Z`), relative to ([x], [y]).
  final String path;

  /// Bounds of the outline within the icon's box.
  final double x, y, width, height;

  bool get isEmpty => path.isEmpty;
}

class _Command {
  _Command(this.op, [this.args = const []]);
  final String op;
  final List<double> args;
}

class _FontReader {
  _FontReader(this.d);
  final ByteData d;

  int u8(int o) => d.getUint8(o);
  int u16(int o) => d.getUint16(o);
  int i16(int o) => d.getInt16(o);
  int u32(int o) => d.getUint32(o);

  IconFont read() {
    final tag = u32(0);
    const otto = 0x4F54544F, trueType = 0x00010000, tru = 0x74727565;
    if (tag != otto && tag != trueType && tag != tru) {
      throw const FormatException('Not an OpenType font');
    }
    final tables = <String, int>{};
    final count = u16(4);
    for (var i = 0; i < count; i++) {
      final r = 12 + i * 16;
      final name = String.fromCharCodes([
        for (var k = 0; k < 4; k++) u8(r + k),
      ]);
      tables[name] = u32(r + 8);
    }
    int table(String name) =>
        tables[name] ?? (throw FormatException('No $name table'));

    final head = table('head');
    final unitsPerEm = u16(head + 18);
    final hhea = table('hhea');
    final ascender = i16(hhea + 4);
    final descender = i16(hhea + 6);
    final numberOfHMetrics = u16(hhea + 34);
    final hmtx = tables['hmtx'];
    final advances = hmtx == null
        ? <int>[]
        : [for (var i = 0; i < numberOfHMetrics; i++) u16(hmtx + i * 4)];

    final List<_Command> Function(int) outline;
    if (tables.containsKey('CFF ')) {
      outline = _Cff(d, table('CFF ')).glyph;
    } else {
      final indexToLocFormat = i16(head + 50);
      outline = _Glyf(
        d,
        table('glyf'),
        table('loca'),
        longOffsets: indexToLocFormat == 1,
      ).glyph;
    }
    return IconFont._(
      _readCmap(table('cmap')),
      outline,
      unitsPerEm,
      ascender,
      descender,
      advances,
    );
  }

  Map<int, int> _readCmap(int cmap) {
    // Prefer a full-Unicode subtable (format 12), else the BMP (format 4).
    int? best;
    var bestFormat = 0;
    final n = u16(cmap + 2);
    for (var i = 0; i < n; i++) {
      final r = cmap + 4 + i * 8;
      final platform = u16(r), encoding = u16(r + 2);
      final unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) continue;
      final sub = cmap + u32(r + 4);
      final format = u16(sub);
      if (format == 12 || (format == 4 && bestFormat != 12)) {
        best = sub;
        bestFormat = format;
      }
    }
    if (best == null) throw const FormatException('No Unicode cmap');
    final map = <int, int>{};
    if (bestFormat == 12) {
      final groups = u32(best + 12);
      for (var g = 0; g < groups; g++) {
        final r = best + 16 + g * 12;
        final start = u32(r), end = u32(r + 4), gid = u32(r + 8);
        for (var c = start; c <= end; c++) {
          map[c] = gid + c - start;
        }
      }
      return map;
    }
    final segX2 = u16(best + 6);
    final ends = best + 14;
    final starts = ends + segX2 + 2;
    final deltas = starts + segX2;
    final rangeOffsets = deltas + segX2;
    for (var s = 0; s < segX2; s += 2) {
      final end = u16(ends + s), start = u16(starts + s);
      final delta = u16(deltas + s), rangeOffset = u16(rangeOffsets + s);
      for (var c = start; c <= end && c != 0xFFFF; c++) {
        int gid;
        if (rangeOffset == 0) {
          gid = (c + delta) & 0xFFFF;
        } else {
          final at = rangeOffsets + s + rangeOffset + (c - start) * 2;
          gid = u16(at);
          if (gid != 0) gid = (gid + delta) & 0xFFFF;
        }
        if (gid != 0) map[c] = gid;
      }
    }
    return map;
  }
}

/// Compact Font Format (CFF 1) outlines: Type 2 charstrings.
class _Cff {
  _Cff(this.d, this.base) {
    final headerSize = d.getUint8(base + 2);
    final names = _index(base + headerSize);
    final topDicts = _index(names.end);
    final strings = _index(topDicts.end);
    final globals = _index(strings.end);
    _globalSubrs = globals.items;
    final top = _dict(topDicts.items.first.$1, topDicts.items.first.$2);

    _charStrings = _index(base + top[17]!.first.toInt()).items;
    final fdArray = top[1236];
    if (fdArray != null) {
      // CID-keyed: each glyph's private dict comes from its font dict.
      final fds = _index(base + fdArray.first.toInt()).items;
      _fdSubrs = [for (final (s, e) in fds) _privateSubrs(_dict(s, e))];
      _fdSelect = _readFdSelect(base + top[1237]!.first.toInt());
    } else {
      _fdSubrs = [_privateSubrs(top)];
    }
  }

  final ByteData d;
  final int base;
  late final List<(int, int)> _globalSubrs;
  late final List<(int, int)> _charStrings;
  late final List<List<(int, int)>> _fdSubrs;
  List<int>? _fdSelect;

  List<(int, int)> _privateSubrs(Map<int, List<num>> dict) {
    final private = dict[18];
    if (private == null) return const [];
    final size = private[0].toInt(), offset = base + private[1].toInt();
    final pd = _dict(offset, offset + size);
    final subrs = pd[19];
    return subrs == null
        ? const []
        : _index(offset + subrs.first.toInt()).items;
  }

  List<int> _readFdSelect(int o) {
    final format = d.getUint8(o);
    final n = _charStrings.length;
    if (format == 0) return [for (var i = 0; i < n; i++) d.getUint8(o + 1 + i)];
    final select = List.filled(n, 0);
    final ranges = d.getUint16(o + 1);
    for (var r = 0; r < ranges; r++) {
      final at = o + 3 + r * 3;
      final first = d.getUint16(at), fd = d.getUint8(at + 2);
      final next = d.getUint16(at + 3);
      for (var g = first; g < next && g < n; g++) {
        select[g] = fd;
      }
    }
    return select;
  }

  ({List<(int, int)> items, int end}) _index(int o) {
    final count = d.getUint16(o);
    if (count == 0) return (items: const [], end: o + 2);
    final offSize = d.getUint8(o + 2);
    int off(int i) {
      var v = 0;
      for (var k = 0; k < offSize; k++) {
        v = (v << 8) | d.getUint8(o + 3 + i * offSize + k);
      }
      return v;
    }

    final data = o + 3 + (count + 1) * offSize - 1;
    final items = [
      for (var i = 0; i < count; i++) (data + off(i), data + off(i + 1)),
    ];
    return (items: items, end: data + off(count));
  }

  Map<int, List<num>> _dict(int start, int end) {
    final dict = <int, List<num>>{};
    var operands = <num>[];
    var i = start;
    while (i < end) {
      final b = d.getUint8(i);
      if (b <= 21) {
        var op = b;
        i++;
        if (b == 12) op = 1200 + d.getUint8(i++);
        dict[op] = operands;
        operands = [];
      } else if (b == 28) {
        operands.add(d.getInt16(i + 1));
        i += 3;
      } else if (b == 29) {
        operands.add(d.getInt32(i + 1));
        i += 5;
      } else if (b == 30) {
        // Real number: nibbles; only skipped, icons never need them.
        i++;
        while (i < end) {
          final v = d.getUint8(i++);
          if ((v & 0x0F) == 0x0F || (v >> 4) == 0x0F) break;
        }
        operands.add(0);
      } else if (b >= 32 && b <= 246) {
        operands.add(b - 139);
        i++;
      } else if (b >= 247 && b <= 250) {
        operands.add((b - 247) * 256 + d.getUint8(i + 1) + 108);
        i += 2;
      } else if (b >= 251 && b <= 254) {
        operands.add(-(b - 251) * 256 - d.getUint8(i + 1) - 108);
        i += 2;
      } else {
        i++;
      }
    }
    return dict;
  }

  static int _bias(int count) => count < 1240
      ? 107
      : count < 33900
      ? 1131
      : 32768;

  List<_Command> glyph(int gid) {
    if (gid >= _charStrings.length) return const [];
    final localSubrs = _fdSubrs[_fdSelect?[gid] ?? 0];
    return _Type2(
      d,
      _globalSubrs,
      localSubrs,
      _bias(_globalSubrs.length),
      _bias(localSubrs.length),
    ).run(_charStrings[gid]);
  }
}

class _Type2 {
  _Type2(this.d, this.globals, this.locals, this.gBias, this.lBias);
  final ByteData d;
  final List<(int, int)> globals, locals;
  final int gBias, lBias;

  final stack = <double>[];
  final out = <_Command>[];
  var x = 0.0, y = 0.0;
  var stems = 0;
  var haveWidth = false;
  var open = false;
  var done = false;

  List<_Command> run((int, int) charString) {
    _exec(charString, 0);
    if (open) out.add(_Command('Z'));
    return out;
  }

  void _width(bool hasExtra) {
    if (!haveWidth && hasExtra) stack.removeAt(0);
    haveWidth = true;
  }

  void _move(double dx, double dy) {
    if (open) out.add(_Command('Z'));
    x += dx;
    y += dy;
    out.add(_Command('M', [x, y]));
    open = true;
  }

  void _line(double dx, double dy) {
    x += dx;
    y += dy;
    out.add(_Command('L', [x, y]));
  }

  void _curve(double a, double b, double c, double e, double f, double g) {
    final x1 = x + a, y1 = y + b;
    final x2 = x1 + c, y2 = y1 + e;
    x = x2 + f;
    y = y2 + g;
    out.add(_Command('C', [x1, y1, x2, y2, x, y]));
  }

  void _stems() {
    _width(stack.length.isOdd);
    stems += stack.length ~/ 2;
    stack.clear();
  }

  void _exec((int, int) range, int depth) {
    if (depth > 10) return;
    var i = range.$1;
    final end = range.$2;
    while (i < end && !done) {
      final b = d.getUint8(i++);
      if (b >= 32) {
        if (b <= 246) {
          stack.add(b - 139.0);
        } else if (b <= 250) {
          stack.add((b - 247) * 256.0 + d.getUint8(i++) + 108);
        } else if (b <= 254) {
          stack.add(-(b - 251) * 256.0 - d.getUint8(i++) - 108);
        } else {
          stack.add(d.getInt32(i) / 65536);
          i += 4;
        }
        continue;
      }
      switch (b) {
        case 28:
          stack.add(d.getInt16(i).toDouble());
          i += 2;
        case 1 || 3 || 18 || 23: // hstem vstem hstemhm vstemhm
          _stems();
        case 19 || 20: // hintmask cntrmask
          if (stack.isNotEmpty) _stems();
          i += (stems + 7) >> 3;
        case 21: // rmoveto
          _width(stack.length > 2);
          _move(stack[0], stack[1]);
          stack.clear();
        case 22: // hmoveto
          _width(stack.length > 1);
          _move(stack[0], 0);
          stack.clear();
        case 4: // vmoveto
          _width(stack.length > 1);
          _move(0, stack[0]);
          stack.clear();
        case 5: // rlineto
          for (var k = 0; k + 1 < stack.length; k += 2) {
            _line(stack[k], stack[k + 1]);
          }
          stack.clear();
        case 6 || 7: // hlineto vlineto: alternating
          var horizontal = b == 6;
          for (final v in stack) {
            horizontal ? _line(v, 0) : _line(0, v);
            horizontal = !horizontal;
          }
          stack.clear();
        case 8: // rrcurveto
          for (var k = 0; k + 5 < stack.length; k += 6) {
            _curve(
              stack[k],
              stack[k + 1],
              stack[k + 2],
              stack[k + 3],
              stack[k + 4],
              stack[k + 5],
            );
          }
          stack.clear();
        case 24: // rcurveline
          var k = 0;
          for (; k + 7 < stack.length; k += 6) {
            _curve(
              stack[k],
              stack[k + 1],
              stack[k + 2],
              stack[k + 3],
              stack[k + 4],
              stack[k + 5],
            );
          }
          _line(stack[k], stack[k + 1]);
          stack.clear();
        case 25: // rlinecurve
          var k = 0;
          for (; k + 7 < stack.length; k += 2) {
            _line(stack[k], stack[k + 1]);
          }
          _curve(
            stack[k],
            stack[k + 1],
            stack[k + 2],
            stack[k + 3],
            stack[k + 4],
            stack[k + 5],
          );
          stack.clear();
        case 26: // vvcurveto
          var k = 0;
          var dx1 = 0.0;
          if (stack.length.isOdd) dx1 = stack[k++];
          for (; k + 3 < stack.length; k += 4) {
            _curve(dx1, stack[k], stack[k + 1], stack[k + 2], 0, stack[k + 3]);
            dx1 = 0;
          }
          stack.clear();
        case 27: // hhcurveto
          var k = 0;
          var dy1 = 0.0;
          if (stack.length.isOdd) dy1 = stack[k++];
          for (; k + 3 < stack.length; k += 4) {
            _curve(stack[k], dy1, stack[k + 1], stack[k + 2], stack[k + 3], 0);
            dy1 = 0;
          }
          stack.clear();
        case 30 || 31: // vhcurveto hvcurveto
          var horizontal = b == 31;
          var k = 0;
          while (k + 3 < stack.length) {
            final last = stack.length - k == 5 ? stack[k + 4] : 0.0;
            if (horizontal) {
              _curve(
                stack[k],
                0,
                stack[k + 1],
                stack[k + 2],
                last,
                stack[k + 3],
              );
            } else {
              _curve(
                0,
                stack[k],
                stack[k + 1],
                stack[k + 2],
                stack[k + 3],
                last,
              );
            }
            k += 4;
            horizontal = !horizontal;
          }
          stack.clear();
        case 10 || 29: // callsubr callgsubr
          final subrs = b == 10 ? locals : globals;
          final index = stack.removeLast().toInt() + (b == 10 ? lBias : gBias);
          if (index >= 0 && index < subrs.length) {
            _exec(subrs[index], depth + 1);
          }
        case 11: // return
          return;
        case 14: // endchar
          _width(stack.isNotEmpty && stack.length != 4);
          stack.clear();
          done = true;
        case 12:
          final op = d.getUint8(i++);
          _flex(op);
          stack.clear();
        default:
          stack.clear();
      }
    }
  }

  void _flex(int op) {
    final s = stack;
    switch (op) {
      case 35: // flex
        _curve(s[0], s[1], s[2], s[3], s[4], s[5]);
        _curve(s[6], s[7], s[8], s[9], s[10], s[11]);
      case 34: // hflex
        final y0 = y;
        _curve(s[0], 0, s[1], s[2], s[3], 0);
        _curve(s[4], 0, s[5], y0 - y, s[6], 0);
      case 36: // hflex1
        final y0 = y;
        _curve(s[0], s[1], s[2], s[3], s[4], 0);
        _curve(s[5], 0, s[6], s[7], s[8], y0 - y - s[7]);
      case 37: // flex1
        final x0 = x, y0 = y;
        var dx = 0.0, dy = 0.0;
        for (var k = 0; k < 10; k += 2) {
          dx += s[k];
          dy += s[k + 1];
        }
        _curve(s[0], s[1], s[2], s[3], s[4], s[5]);
        final horizontal = dx.abs() > dy.abs();
        _curve(
          s[6],
          s[7],
          s[8],
          s[9],
          horizontal ? s[10] : x0 - x - s[6] - s[8],
          horizontal ? y0 - y - s[7] - s[9] : s[10],
        );
    }
  }
}

/// TrueType outlines: quadratic contours in `glyf`.
class _Glyf {
  _Glyf(this.d, this.glyf, this.loca, {required this.longOffsets});
  final ByteData d;
  final int glyf, loca;
  final bool longOffsets;

  int _offset(int gid) => longOffsets
      ? d.getUint32(loca + gid * 4)
      : d.getUint16(loca + gid * 2) * 2;

  List<_Command> glyph(int gid, [int depth = 0]) {
    final start = _offset(gid), end = _offset(gid + 1);
    if (start == end || depth > 8) return const [];
    final g = glyf + start;
    final contours = d.getInt16(g);
    if (contours < 0) return _composite(g + 10, depth);

    final endPts = [
      for (var c = 0; c < contours; c++) d.getUint16(g + 10 + c * 2),
    ];
    final points = endPts.isEmpty ? 0 : endPts.last + 1;
    var p = g + 10 + contours * 2;
    p += 2 + d.getUint16(p); // instructions
    final flags = <int>[];
    while (flags.length < points) {
      final f = d.getUint8(p++);
      flags.add(f);
      if (f & 8 != 0) {
        final repeat = d.getUint8(p++);
        for (var r = 0; r < repeat; r++) {
          flags.add(f);
        }
      }
    }
    List<int> coords(int shortBit, int sameBit) {
      final out = <int>[];
      var v = 0;
      for (final f in flags.take(points)) {
        if (f & shortBit != 0) {
          final delta = d.getUint8(p++);
          v += f & sameBit != 0 ? delta : -delta;
        } else if (f & sameBit == 0) {
          v += d.getInt16(p);
          p += 2;
        }
        out.add(v);
      }
      return out;
    }

    final xs = coords(2, 16), ys = coords(4, 32);
    final out = <_Command>[];
    var first = 0;
    for (final last in endPts) {
      _contour(out, [
        for (var k = first; k <= last; k++)
          (xs[k].toDouble(), ys[k].toDouble(), flags[k] & 1 != 0),
      ]);
      first = last + 1;
    }
    return out;
  }

  void _contour(List<_Command> out, List<(double, double, bool)> pts) {
    if (pts.isEmpty) return;
    // Start on an on-curve point (or the midpoint of two off-curve ones).
    var startIndex = pts.indexWhere((p) => p.$3);
    (double, double) start;
    if (startIndex < 0) {
      start = ((pts[0].$1 + pts.last.$1) / 2, (pts[0].$2 + pts.last.$2) / 2);
      startIndex = 0;
      pts = [(start.$1, start.$2, true), ...pts];
    } else {
      pts = [...pts.sublist(startIndex), ...pts.sublist(0, startIndex)];
      start = (pts[0].$1, pts[0].$2);
    }
    out.add(_Command('M', [start.$1, start.$2]));
    (double, double)? control;
    for (final p in [...pts.skip(1), pts.first]) {
      if (p.$3) {
        out.add(
          control == null
              ? _Command('L', [p.$1, p.$2])
              : _Command('Q', [control.$1, control.$2, p.$1, p.$2]),
        );
        control = null;
      } else {
        if (control != null) {
          final mx = (control.$1 + p.$1) / 2, my = (control.$2 + p.$2) / 2;
          out.add(_Command('Q', [control.$1, control.$2, mx, my]));
        }
        control = (p.$1, p.$2);
      }
    }
    out.add(_Command('Z'));
  }

  List<_Command> _composite(int p, int depth) {
    final out = <_Command>[];
    while (true) {
      final flags = d.getUint16(p);
      final gid = d.getUint16(p + 2);
      p += 4;
      double dx, dy;
      if (flags & 1 != 0) {
        dx = d.getInt16(p).toDouble();
        dy = d.getInt16(p + 2).toDouble();
        p += 4;
      } else {
        dx = d.getInt8(p).toDouble();
        dy = d.getInt8(p + 1).toDouble();
        p += 2;
      }
      var a = 1.0, b = 0.0, c = 0.0, e = 1.0;
      double f2dot14(int o) => d.getInt16(o) / 16384;
      if (flags & 8 != 0) {
        a = e = f2dot14(p);
        p += 2;
      } else if (flags & 0x40 != 0) {
        a = f2dot14(p);
        e = f2dot14(p + 2);
        p += 4;
      } else if (flags & 0x80 != 0) {
        a = f2dot14(p);
        b = f2dot14(p + 2);
        c = f2dot14(p + 4);
        e = f2dot14(p + 6);
        p += 8;
      }
      for (final cmd in glyph(gid, depth + 1)) {
        out.add(
          _Command(cmd.op, [
            for (var k = 0; k < cmd.args.length; k += 2) ...[
              a * cmd.args[k] + c * cmd.args[k + 1] + dx,
              b * cmd.args[k] + e * cmd.args[k + 1] + dy,
            ],
          ]),
        );
      }
      if (flags & 0x20 == 0) break;
    }
    return out;
  }
}
