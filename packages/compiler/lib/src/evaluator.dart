import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';

import 'material_theme.dart';
import 'text_style.dart';

/// Interprets analyzed Dart values (`EdgeInsets.all(16)`, `Colors.blue`, ...)
/// as design values.
class ValueEvaluator {
  const ValueEvaluator(this.theme);

  final MaterialTheme theme;

  /// Follows `const` references to their initializers.
  DartValue? deref(DartValue? v) {
    var current = v;
    for (var i = 0; i < 16 && current is RefValue; i++) {
      final constant = current.constant;
      if (constant == null) return current;
      current = constant;
    }
    return current;
  }

  /// Unwraps `WidgetStatePropertyAll(x)` / `MaterialStatePropertyAll(x)`.
  DartValue? unwrapStateProperty(DartValue? v) {
    final d = deref(v);
    if (d is ObjectValue &&
        (d.type == 'WidgetStatePropertyAll' ||
            d.type == 'MaterialStatePropertyAll')) {
      return d.arg(0);
    }
    if (d is CallValue &&
        d.method == 'all' &&
        d.target is RefValue &&
        const {
          'WidgetStateProperty',
          'MaterialStateProperty',
        }.contains((d.target as RefValue).last)) {
      return d.positional.firstOrNull;
    }
    return v;
  }

  /// Name of an enum-like constant: `CrossAxisAlignment.start` → `start`.
  String? enumName(DartValue? v) => v is RefValue ? v.last : null;

  double? number(DartValue? v) {
    if (v is RefValue) {
      if (v.dotted == 'double.infinity') return double.infinity;
      if (v.dotted == 'double.maxFinite') return double.infinity;
    }
    final d = deref(v);
    if (d is LiteralValue) return d.asDouble;
    return null;
  }

  int? integer(DartValue? v) => number(v)?.toInt();

  String? string(DartValue? v) {
    final d = deref(v);
    return d is LiteralValue ? d.asString : null;
  }

  // -------------------------------------------------------------------------
  // Color
  // -------------------------------------------------------------------------

  IrColor? color(DartValue? v) {
    final unwrapped = unwrapStateProperty(v);
    if (unwrapped is RefValue) {
      switch (unwrapped.dotted) {
        case 'Colors.transparent':
          return IrColor.transparent;
        case 'Colors.white':
          return IrColor.white;
        case 'Colors.black':
          return IrColor.black;
      }
    }
    final d = deref(unwrapped);
    switch (d) {
      case LiteralValue(value: final int argb):
        return IrColor.fromArgb32(argb);
      case ObjectValue():
        return _colorObject(d);
      case AccessValue(:final target, :final name):
        if (name.startsWith('shade')) {
          final swatch = deref(target);
          final shade = int.tryParse(name.substring(5));
          if (swatch is ObjectValue && shade != null) {
            final map = deref(swatch.arg(1));
            if (map is MapValue) return color(map.lookup(shade));
          }
          return null;
        }
        if (_endsWith(target, const {'colorScheme'})) {
          return theme.maybeColor(name);
        }
        return null;
      case CallValue(:final target, :final method):
        final base = color(target);
        if (base == null) return null;
        switch (method) {
          case 'withOpacity':
            final o = number(d.positional.firstOrNull);
            return o == null ? base : base.withAlpha(o);
          case 'withValues':
            final a = number(d.named['alpha']);
            return a == null ? base : base.withAlpha(a);
          case 'withAlpha':
            final a = number(d.positional.firstOrNull);
            return a == null ? base : base.withAlpha(a / 255);
        }
        return base;
      case ConditionalValue(:final then):
        return color(then);
      default:
        return null;
    }
  }

  IrColor? _colorObject(ObjectValue o) {
    switch (o.displayName) {
      case 'Color' ||
          'MaterialColor' ||
          'MaterialAccentColor' ||
          'ColorSwatch' ||
          'CupertinoDynamicColor':
        final argb = integer(o.arg(0));
        return argb == null ? null : IrColor.fromArgb32(argb);
      case 'Color.fromARGB':
        final [a, r, g, b] = [for (var i = 0; i < 4; i++) number(o.arg(i))];
        if ([a, r, g, b].contains(null)) return null;
        return IrColor(r! / 255, g! / 255, b! / 255, a! / 255);
      case 'Color.fromRGBO':
        final [r, g, b, opacity] = [
          for (var i = 0; i < 4; i++) number(o.arg(i)),
        ];
        if ([r, g, b, opacity].contains(null)) return null;
        return IrColor(r! / 255, g! / 255, b! / 255, opacity!);
      case 'Color.from':
        final a = number(o['alpha']), r = number(o['red']);
        final g = number(o['green']), b = number(o['blue']);
        if ([a, r, g, b].contains(null)) return null;
        return IrColor(r!, g!, b!, a!);
    }
    return null;
  }

  bool _endsWith(DartValue target, Set<String> names) =>
      target is AccessValue && names.contains(target.name);

  // -------------------------------------------------------------------------
  // Geometry
  // -------------------------------------------------------------------------

  IrInsets? insets(DartValue? v) {
    final d = deref(unwrapStateProperty(v));
    if (d is! ObjectValue) return null;
    if (d.type != 'EdgeInsets' && d.type != 'EdgeInsetsDirectional') {
      return null;
    }
    double n(DartValue? x) => number(x) ?? 0;
    switch (d.constructor) {
      case 'all':
        return IrInsets.all(n(d.arg(0)));
      case 'symmetric':
        return IrInsets.symmetric(
          horizontal: n(d['horizontal']),
          vertical: n(d['vertical']),
        );
      case 'only':
        return IrInsets(
          top: n(d['top']),
          bottom: n(d['bottom']),
          left: n(d['left'] ?? d['start']),
          right: n(d['right'] ?? d['end']),
        );
      case 'fromLTRB' || 'fromSTEB':
        return IrInsets(
          left: n(d.arg(0)),
          top: n(d.arg(1)),
          right: n(d.arg(2)),
          bottom: n(d.arg(3)),
        );
      case 'zero':
        return IrInsets.zero;
    }
    return null;
  }

  double? radius(DartValue? v) {
    final d = deref(v);
    if (d is ObjectValue && d.type == 'Radius') {
      return number(d.arg(0));
    }
    return null;
  }

  IrCorners? borderRadius(DartValue? v) {
    final d = deref(v);
    if (d is! ObjectValue) return null;
    if (d.type != 'BorderRadius' && d.type != 'BorderRadiusDirectional') {
      return null;
    }
    double r(DartValue? x) => radius(x) ?? 0;
    switch (d.constructor) {
      case 'circular':
        return IrCorners.all(number(d.arg(0)) ?? 0);
      case 'all':
        return IrCorners.all(r(d.arg(0)));
      case 'only':
        return IrCorners(
          topLeft: r(d['topLeft'] ?? d['topStart']),
          topRight: r(d['topRight'] ?? d['topEnd']),
          bottomRight: r(d['bottomRight'] ?? d['bottomEnd']),
          bottomLeft: r(d['bottomLeft'] ?? d['bottomStart']),
        );
      case 'vertical':
        final top = r(d['top']), bottom = r(d['bottom']);
        return IrCorners(
          topLeft: top,
          topRight: top,
          bottomLeft: bottom,
          bottomRight: bottom,
        );
      case 'horizontal':
        final left = r(d['left'] ?? d['start']);
        final right = r(d['right'] ?? d['end']);
        return IrCorners(
          topLeft: left,
          bottomLeft: left,
          topRight: right,
          bottomRight: right,
        );
      case 'zero':
        return IrCorners.zero;
    }
    return null;
  }

  IrStroke? borderSide(DartValue? v) {
    final d = deref(unwrapStateProperty(v));
    if (d is! ObjectValue || d.type != 'BorderSide') return null;
    if (enumName(d['style']) == 'none') return null;
    return IrStroke(
      color: color(d['color']) ?? IrColor.black,
      width: number(d['width']) ?? 1,
    );
  }

  /// `Border.all(...)` or a uniform `Border(...)`.
  IrStroke? border(DartValue? v) {
    final d = deref(v);
    if (d is! ObjectValue || d.type != 'Border') return null;
    if (d.constructor == 'all') {
      return IrStroke(
        color: color(d['color']) ?? IrColor.black,
        width: number(d['width']) ?? 1,
      );
    }
    if (d.constructor == 'fromBorderSide') return borderSide(d.arg(0));
    // Non-uniform borders: use the first side that is set.
    for (final side in ['top', 'right', 'bottom', 'left']) {
      final s = borderSide(d[side]);
      if (s != null) return s;
    }
    return null;
  }

  /// Shape → (corners, stroke). Stadium/circle shapes use a large radius.
  (IrCorners?, IrStroke?) shape(DartValue? v) {
    final d = deref(unwrapStateProperty(v));
    if (d is! ObjectValue) return (null, null);
    final side = borderSide(d['side']);
    return switch (d.type) {
      'RoundedRectangleBorder' ||
      'ContinuousRectangleBorder' ||
      'BeveledRectangleBorder' => (
        borderRadius(d['borderRadius']) ?? IrCorners.zero,
        side,
      ),
      'StadiumBorder' || 'CircleBorder' => (const IrCorners.all(9999), side),
      _ => (null, side),
    };
  }

  List<IrShadow> boxShadows(DartValue? v) {
    final d = deref(v);
    if (d is! ListValue) return const [];
    return [
      for (final item in d.items)
        if (deref(item) case ObjectValue(type: 'BoxShadow') && final s)
          IrShadow(
            color: color(s['color']) ?? IrColor.black,
            x: _offset(s['offset']).$1,
            y: _offset(s['offset']).$2,
            blur: number(s['blurRadius']) ?? 0,
            spread: number(s['spreadRadius']) ?? 0,
          ),
    ];
  }

  (double, double) _offset(DartValue? v) {
    final d = deref(v);
    if (d is ObjectValue && d.type == 'Offset') {
      return (number(d.arg(0)) ?? 0, number(d.arg(1)) ?? 0);
    }
    return (0, 0);
  }

  /// `Alignment.x` → (x, y) with components in -1..1.
  (double, double)? alignment(DartValue? v) {
    if (v is RefValue &&
        (v.path.first == 'Alignment' ||
            v.path.first == 'AlignmentDirectional')) {
      const named = {
        'topLeft': (-1.0, -1.0),
        'topStart': (-1.0, -1.0),
        'topCenter': (0.0, -1.0),
        'topRight': (1.0, -1.0),
        'topEnd': (1.0, -1.0),
        'centerLeft': (-1.0, 0.0),
        'centerStart': (-1.0, 0.0),
        'center': (0.0, 0.0),
        'centerRight': (1.0, 0.0),
        'centerEnd': (1.0, 0.0),
        'bottomLeft': (-1.0, 1.0),
        'bottomStart': (-1.0, 1.0),
        'bottomCenter': (0.0, 1.0),
        'bottomRight': (1.0, 1.0),
        'bottomEnd': (1.0, 1.0),
      };
      final hit = named[v.last];
      if (hit != null) return hit;
    }
    final d = deref(v);
    if (d is ObjectValue &&
        (d.type == 'Alignment' || d.type == 'AlignmentDirectional')) {
      return (number(d.arg(0)) ?? 0, number(d.arg(1)) ?? 0);
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Typography
  // -------------------------------------------------------------------------

  int? fontWeight(DartValue? v) {
    if (v is RefValue && v.path.first == 'FontWeight') {
      const named = {'normal': 400, 'bold': 700};
      final n = named[v.last] ?? int.tryParse(v.last.replaceFirst('w', ''));
      if (n != null) return n;
    }
    final d = deref(v);
    if (d is ObjectValue && d.type == 'FontWeight') {
      // `FontWeight._(index, value)` in older SDKs, `FontWeight(value)` later.
      final values = [for (final p in d.positional) integer(p)].nonNulls;
      return values.where((w) => w >= 100).firstOrNull;
    }
    return null;
  }

  TextStyleSpec? textStyle(DartValue? v) {
    final d = deref(v);
    switch (d) {
      case ObjectValue(type: 'TextStyle'):
        return TextStyleSpec(
          fontFamily: string(d['fontFamily']),
          fontSize: number(d['fontSize']),
          fontWeight: fontWeight(d['fontWeight']),
          italic: switch (enumName(d['fontStyle'])) {
            'italic' => true,
            'normal' => false,
            _ => null,
          },
          color: color(d['color']),
          height: number(d['height']),
          letterSpacing: number(d['letterSpacing']),
        );
      case AccessValue(:final target, :final name)
          when _endsWith(target, const {'textTheme', 'primaryTextTheme'}):
        return theme.textStyle(name);
      case CallValue(target: final target?, method: 'copyWith'):
        final base = textStyle(target) ?? const TextStyleSpec();
        return base.merge(
          textStyle(ObjectValue(type: 'TextStyle', named: d.named)),
        );
      case CallValue(target: final target?, method: 'merge'):
        final base = textStyle(target) ?? const TextStyleSpec();
        return base.merge(textStyle(d.positional.firstOrNull));
      case CallValue(target: final target?, method: 'apply'):
        final base = textStyle(target) ?? const TextStyleSpec();
        return base.merge(TextStyleSpec(color: color(d.named['color'])));
      case ConditionalValue(:final then):
        return textStyle(then);
      default:
        return null;
    }
  }

  /// Plain text for a `Text` data argument. Non-constant parts become
  /// `{placeholders}`.
  String text(DartValue? v) {
    final d = deref(v);
    return switch (d) {
      LiteralValue(value: final String s) => s,
      LiteralValue(value: final Object value) => '$value',
      UnknownValue(:final code) => '{$code}',
      AccessValue(:final name) => '{$name}',
      CallValue(:final method) => '{$method()}',
      RefValue(:final last) => '{$last}',
      ConditionalValue(:final then) => text(then),
      _ => '',
    };
  }

  /// Text of a `TextSpan` tree, concatenated.
  String spanText(DartValue? v) {
    final d = deref(v);
    if (d is! ObjectValue) return '';
    final buffer = StringBuffer(text(d['text']));
    final children = deref(d['children']);
    if (children is ListValue) {
      for (final c in children.items) {
        buffer.write(spanText(c));
      }
    }
    return buffer.toString();
  }
}
