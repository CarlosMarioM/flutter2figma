import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/ir.dart';

import 'color_scheme.dart';
import 'material_theme.dart';
import 'text_style.dart';

/// A statically computed `ColorScheme`.
typedef ColorSchemeValue = ({
  Map<String, int> roles,
  ThemeBrightness brightness,
});

/// Interprets analyzed Dart values (`EdgeInsets.all(16)`, `Colors.blue`, ...)
/// as design values.
class ValueEvaluator {
  ValueEvaluator(this.theme);

  /// The theme `Theme.of(context)` resolves to at the current point in the
  /// tree. The compiler swaps it inside `Theme` widgets.
  MaterialTheme theme;

  /// Colors referenced through project constants (`AppColors.brand`), by
  /// token name. They become design tokens alongside the color scheme.
  final projectColors = <String, IrColor>{};

  /// Follows references and project calls to the values they stand for.
  DartValue? deref(DartValue? v) {
    var current = v;
    for (var i = 0; i < 16; i++) {
      final next = switch (current) {
        RefValue(:final resolved?) => resolved,
        CallValue(:final result?) => result,
        _ => null,
      };
      if (next == null) return current;
      current = next;
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
    if (unwrapped is RefValue &&
        unwrapped.inProject &&
        unwrapped.resolved != null) {
      final value = color(unwrapped.resolved);
      if (value == null || value.token != null) return value;
      final token = projectToken(unwrapped.path);
      projectColors[token] = value;
      return value.withToken(token);
    }
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
        final scheme = colorScheme(target);
        final argb = scheme?.roles[name];
        if (argb == null) return null;
        // Reading the app's own scheme: bind to the theme token.
        return _sameRoles(scheme!.roles, theme.colorScheme)
            ? theme.color(name)
            : IrColor.fromArgb32(argb);
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
      case CallValue(target: RefValue(path: ['GoogleFonts']), :final method)
          when !method.endsWith('TextTheme'):
        // GoogleFonts.inter(textStyle: ..., fontSize: ...) or getFont('Inter').
        final family = method == 'getFont'
            ? string(d.positional.firstOrNull)
            : googleFontFamily(method);
        return TextStyleSpec(fontFamily: family)
            .merge(textStyle(d.named['textStyle']))
            .merge(textStyle(ObjectValue(type: 'TextStyle', named: d.named)))
            .merge(TextStyleSpec(fontFamily: family));
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

  // -------------------------------------------------------------------------
  // Theme values
  // -------------------------------------------------------------------------

  /// Evaluates a `ColorScheme` expression: the constructors, `fromSeed`,
  /// `copyWith`, or `Theme.of(context).colorScheme`.
  ColorSchemeValue? colorScheme(DartValue? v) {
    final d = deref(v);
    ThemeBrightness? brightnessOf(DartValue? b) => switch (enumName(b)) {
      'dark' => ThemeBrightness.dark,
      'light' => ThemeBrightness.light,
      _ => null,
    };
    Map<String, int> rolesIn(Map<String, DartValue> named) => {
      for (final role in allColorRoles)
        if (color(named[role]) case final c?) role: c.toArgb32(),
    };

    switch (d) {
      case ObjectValue(type: 'ColorScheme'):
        switch (d.constructor) {
          case null:
            final roles = completeColorScheme(rolesIn(d.named));
            final brightness = brightnessOf(d['brightness']);
            if (roles == null || brightness == null) return null;
            return (roles: roles, brightness: brightness);
          case 'light' || 'dark':
            final brightness = d.constructor == 'dark'
                ? ThemeBrightness.dark
                : ThemeBrightness.light;
            final defaults = brightness == ThemeBrightness.dark
                ? colorSchemeDarkDefaults
                : colorSchemeLightDefaults;
            final roles = completeColorScheme({
              ...defaults,
              ...rolesIn(d.named),
            });
            return (roles: roles!, brightness: brightness);
          case 'fromSeed':
            final seed = color(d['seedColor']);
            if (seed == null) return null;
            final brightness =
                brightnessOf(d['brightness']) ?? ThemeBrightness.light;
            return (
              roles: seedColorScheme(
                seed.toArgb32(),
                brightness: brightness,
                variant: enumName(d['dynamicSchemeVariant']) ?? 'tonalSpot',
                contrastLevel: number(d['contrastLevel']) ?? 0,
                overrides: rolesIn(d.named),
              ),
              brightness: brightness,
            );
        }
        return null;
      case CallValue(target: final target?, method: 'copyWith'):
        final base = colorScheme(target);
        if (base == null) return null;
        return (
          roles: {...base.roles, ...rolesIn(d.named)},
          brightness: brightnessOf(d.named['brightness']) ?? base.brightness,
        );
      case AccessValue(name: 'colorScheme'):
        // `Theme.of(context).colorScheme` and friends: the ambient theme.
        return (roles: theme.colorScheme, brightness: theme.brightness);
      default:
        return null;
    }
  }

  /// Evaluates a `TextTheme` expression into the entries it sets.
  ///
  /// `TextTheme(...)` yields only the named entries (as Flutter's partial
  /// text themes do); `Theme.of(context).textTheme` yields the full theme.
  Map<String, TextStyleSpec>? textTheme(DartValue? v) {
    final d = deref(v);
    switch (d) {
      case ObjectValue(type: 'TextTheme'):
        return {
          for (final MapEntry(:key, :value) in d.named.entries)
            key: ?textStyle(value),
        };
      case AccessValue(name: 'textTheme'):
        return {
          for (final name in theme.textTheme.keys) name: theme.textStyle(name)!,
        };
      case CallValue(target: RefValue(path: ['GoogleFonts']), :final method)
          when method.endsWith('TextTheme'):
        // Flutter's google_fonts starts from ThemeData.light().textTheme.
        final baseline = MaterialTheme.baseline(ThemeBrightness.light);
        final base =
            textTheme(d.positional.firstOrNull) ??
            {
              for (final name in baseline.textTheme.keys)
                name: baseline.textStyle(name)!,
            };
        final family = googleFontFamily(
          method.substring(0, method.length - 'TextTheme'.length),
        );
        return {
          for (final MapEntry(:key, :value) in base.entries)
            key: value.merge(TextStyleSpec(fontFamily: family)),
        };
      case CallValue(target: final target?, method: 'apply'):
        final base = textTheme(target);
        if (base == null) return null;
        final family = string(d.named['fontFamily']);
        final display = color(d.named['displayColor']);
        final body = color(d.named['bodyColor']);
        return {
          for (final MapEntry(:key, :value) in base.entries)
            key: value.merge(
              TextStyleSpec(
                fontFamily: family,
                color: _displayColorStyles.contains(key) ? display : body,
              ),
            ),
        };
      case CallValue(target: final target?, method: 'copyWith'):
        final base = textTheme(target);
        if (base == null) return null;
        return {
          ...base,
          for (final MapEntry(:key, :value) in d.named.entries)
            key: ?textStyle(value),
        };
      case CallValue(target: final target?, method: 'merge'):
        final base = textTheme(target);
        final other = textTheme(d.positional.firstOrNull);
        if (base == null) return other;
        if (other == null) return base;
        return {
          for (final key in {...base.keys, ...other.keys})
            key: (base[key] ?? const TextStyleSpec()).merge(other[key]),
        };
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

/// Styles `TextTheme.apply(displayColor:)` colors; the rest take `bodyColor`
/// (note `headlineSmall` is in the body group in Flutter).
const _displayColorStyles = {
  'displayLarge',
  'displayMedium',
  'displaySmall',
  'headlineLarge',
  'headlineMedium',
};

/// `GoogleFonts.robotoMono` → `Roboto Mono`.
String googleFontFamily(String method) {
  final words = method
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .split(' ');
  return [
    for (final w in words)
      if (w.isNotEmpty) w[0].toUpperCase() + w.substring(1),
  ].join(' ');
}

bool _sameRoles(Map<String, int> a, Map<String, int> b) =>
    identical(a, b) ||
    (a.length == b.length && a.entries.every((e) => b[e.key] == e.value));

/// Token name for a project constant: `AppColors.brand` → `AppColors/brand`,
/// `kBrand` → `Constants/kBrand`.
String projectToken(List<String> path) =>
    path.length == 1 ? 'Constants/${path.single}' : path.join('/');
