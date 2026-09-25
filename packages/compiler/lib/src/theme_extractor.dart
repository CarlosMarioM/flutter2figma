import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';

import 'evaluator.dart';
import 'material_theme.dart';
import 'text_style.dart';

/// `ThemeData` arguments that change what exported widgets look like.
const _handledThemeArgs = {
  'useMaterial3',
  'brightness',
  'colorScheme',
  'colorSchemeSeed',
  'fontFamily',
  'textTheme',
  'scaffoldBackgroundColor',
  'appBarTheme',
  'cardTheme',
  'elevatedButtonTheme',
  'filledButtonTheme',
  'outlinedButtonTheme',
  'textButtonTheme',
};

const _buttonThemes = {
  'ElevatedButton': 'elevatedButtonTheme',
  'FilledButton': 'filledButtonTheme',
  'OutlinedButton': 'outlinedButtonTheme',
  'TextButton': 'textButtonTheme',
};

/// Recovers the app's `ThemeData` statically and resolves it the way Flutter
/// does (`ThemeData` factory + `Theme.of` localization), producing the
/// [MaterialTheme] widgets are compiled against.
class ThemeExtractor {
  ThemeExtractor(this.eval);

  final ValueEvaluator eval;
  final diagnostics = <IrDiagnostic>[];

  /// The theme of the project's `MaterialApp`.
  ///
  /// [brightness] picks `theme` or `darkTheme`. When null, a literal
  /// `themeMode: ThemeMode.dark` selects dark; otherwise light.
  MaterialTheme fromProject(
    ProjectAnalysis analysis, {
    ThemeBrightness? brightness,
  }) {
    ObjectValue? app;
    for (final w in analysis.widgets) {
      app = _findApp(w.tree, 0);
      if (app != null) break;
    }
    final fallback = MaterialTheme.baseline(
      brightness ?? ThemeBrightness.light,
    );
    if (app == null) {
      _note(
        'No MaterialApp found; using the default Material 3 theme',
        null,
        IrSeverity.info,
      );
      return fallback;
    }

    final mode = eval.enumName(app['themeMode']);
    final dark =
        (brightness ?? (mode == 'dark' ? ThemeBrightness.dark : null)) ==
        ThemeBrightness.dark;
    var data = app['theme'];
    if (dark) {
      if (app['darkTheme'] != null) {
        data = app['darkTheme'];
      } else {
        _note(
          'Dark mode requested but MaterialApp has no darkTheme; using theme',
          app,
          IrSeverity.info,
        );
      }
    }
    if (data == null) return fallback;
    return themeData(data, current: fallback);
  }

  ObjectValue? _findApp(DartValue? v, int depth) {
    if (v == null || depth > 24) return null;
    final d = eval.deref(v);
    switch (d) {
      case ObjectValue(isWidget: true):
        if (d.isFlutter && d.type == 'MaterialApp') return d;
        if (d.isFlutter && d.type == 'CupertinoApp') {
          _note('CupertinoApp themes are not supported', d, IrSeverity.warning);
          return null;
        }
        for (final arg in [...d.positional, ...d.named.values]) {
          final found = _findApp(arg, depth + 1);
          if (found != null) return found;
        }
      case ListValue(:final items):
        for (final i in items) {
          final found = _findApp(i, depth + 1);
          if (found != null) return found;
        }
      case ConditionalValue(:final then, :final otherwise):
        return _findApp(then, depth + 1) ?? _findApp(otherwise, depth + 1);
      case FunctionValue(:final returns):
        return _findApp(returns, depth + 1);
      default:
        break;
    }
    return null;
  }

  /// Evaluates a `ThemeData` expression. [current] is the ambient theme,
  /// used for `Theme.of(context)` and as the fallback.
  MaterialTheme themeData(DartValue? v, {required MaterialTheme current}) {
    final d = eval.deref(v);
    switch (d) {
      case ObjectValue(type: 'ThemeData', :final constructor):
        return switch (constructor) {
          null || 'from' => _build(d.named, d),
          'light' ||
          'fallback' => MaterialTheme.baseline(ThemeBrightness.light),
          'dark' => MaterialTheme.baseline(ThemeBrightness.dark),
          _ => _unresolved(d, current),
        };
      case CallValue(target: final target?, method: 'copyWith'):
        return _copyWith(themeData(target, current: current), d.named, d);
      case CallValue(target: RefValue(last: 'Theme'), method: 'of'):
        return current;
      default:
        return _unresolved(d, current);
    }
  }

  MaterialTheme _unresolved(DartValue? d, MaterialTheme current) {
    _note(
      'Could not statically resolve the theme; using the enclosing theme',
      d,
      IrSeverity.warning,
    );
    return current;
  }

  /// The `ThemeData({...})` factory.
  MaterialTheme _build(Map<String, DartValue> args, DartValue at) {
    if (args['useMaterial3'] case LiteralValue(value: false)) {
      _note(
        'Material 2 themes (useMaterial3: false) are exported with Material 3 defaults',
        at,
        IrSeverity.warning,
      );
    }
    final unhandled = args.keys.where((k) => !_handledThemeArgs.contains(k));
    if (unhandled.isNotEmpty) {
      _note(
        'ThemeData arguments not applied: ${unhandled.join(', ')}',
        at,
        IrSeverity.info,
      );
    }

    final explicitBrightness = switch (eval.enumName(args['brightness'])) {
      'dark' => ThemeBrightness.dark,
      'light' => ThemeBrightness.light,
      _ => null,
    };

    ColorSchemeValue? scheme;
    if (args['colorScheme'] != null) {
      scheme = eval.colorScheme(args['colorScheme']);
      if (scheme == null) {
        _note(
          'Could not evaluate ThemeData.colorScheme; using the baseline scheme',
          args['colorScheme'],
          IrSeverity.warning,
        );
      }
    } else if (args['colorSchemeSeed'] != null) {
      final seed = eval.colorScheme(
        ObjectValue(
          type: 'ColorScheme',
          constructor: 'fromSeed',
          named: {
            'seedColor': args['colorSchemeSeed']!,
            'brightness': ?args['brightness'],
          },
        ),
      );
      scheme = seed;
    }
    final brightness =
        explicitBrightness ?? scheme?.brightness ?? ThemeBrightness.light;
    final roles =
        scheme?.roles ?? MaterialTheme.baseline(brightness).colorScheme;

    // Typography: geometry (sizes) under family + user text theme, as
    // `ThemeData.localize` merges it.
    final fontFamily = eval.string(args['fontFamily']) ?? 'Roboto';
    final user = eval.textTheme(args['textTheme']) ?? const {};
    if (args['textTheme'] != null && user.isEmpty) {
      _note(
        'Could not evaluate ThemeData.textTheme',
        args['textTheme'],
        IrSeverity.warning,
      );
    }
    final textTheme = {
      for (final MapEntry(:key, :value) in m3TextTheme.entries)
        key: value
            .merge(TextStyleSpec(fontFamily: fontFamily))
            .merge(user[key]),
    };

    return MaterialTheme(
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: roles,
      textTheme: textTheme,
      scaffoldBackground: eval.color(args['scaffoldBackgroundColor']),
      appBar: _appBarTheme(args['appBarTheme']),
      card: _cardTheme(args['cardTheme']),
      buttonStyles: _buttonStyles(args),
    );
  }

  /// `ThemeData.copyWith`: replaces what's given, keeps the rest.
  MaterialTheme _copyWith(
    MaterialTheme base,
    Map<String, DartValue> args,
    DartValue at,
  ) {
    final scheme = args['colorScheme'] == null
        ? null
        : eval.colorScheme(args['colorScheme']);
    final textTheme = args['textTheme'] == null
        ? null
        : eval.textTheme(args['textTheme']);
    final buttons = _buttonStyles(args);
    return MaterialTheme(
      brightness: scheme?.brightness ?? base.brightness,
      fontFamily: base.fontFamily,
      colorScheme: scheme?.roles ?? base.colorScheme,
      textTheme: textTheme == null
          ? base.textTheme
          : {
              for (final MapEntry(:key, :value) in base.textTheme.entries)
                key: textTheme[key] ?? value,
            },
      scaffoldBackground:
          eval.color(args['scaffoldBackgroundColor']) ??
          base.scaffoldBackground,
      appBar: args['appBarTheme'] == null
          ? base.appBar
          : _appBarTheme(args['appBarTheme']),
      card: args['cardTheme'] == null
          ? base.card
          : _cardTheme(args['cardTheme']),
      buttonStyles: {...base.buttonStyles, ...buttons},
    );
  }

  AppBarThemeSpec _appBarTheme(DartValue? v) {
    final d = eval.deref(v);
    if (d is! ObjectValue ||
        (d.type != 'AppBarTheme' && d.type != 'AppBarThemeData')) {
      return const AppBarThemeSpec();
    }
    return AppBarThemeSpec(
      backgroundColor: eval.color(d['backgroundColor']),
      foregroundColor: eval.color(d['foregroundColor']),
      elevation: eval.number(d['elevation']),
      centerTitle: switch (d['centerTitle']) {
        LiteralValue(value: final bool b) => b,
        _ => null,
      },
      titleTextStyle: eval.textStyle(d['titleTextStyle']),
      toolbarHeight: eval.number(d['toolbarHeight']),
    );
  }

  CardThemeSpec _cardTheme(DartValue? v) {
    final d = eval.deref(v);
    if (d is! ObjectValue ||
        (d.type != 'CardTheme' && d.type != 'CardThemeData')) {
      return const CardThemeSpec();
    }
    return CardThemeSpec(
      color: eval.color(d['color']),
      elevation: eval.number(d['elevation']),
      margin: eval.insets(d['margin']),
      shape: d['shape'],
    );
  }

  Map<String, Map<String, DartValue>> _buttonStyles(
    Map<String, DartValue> args,
  ) {
    final out = <String, Map<String, DartValue>>{};
    for (final MapEntry(key: button, value: arg) in _buttonThemes.entries) {
      final data = eval.deref(args[arg]);
      if (data is! ObjectValue) continue;
      final style = eval.deref(data['style']);
      if (style is CallValue && style.method == 'styleFrom') {
        out[button] = style.named;
      } else if (style is ObjectValue && style.type == 'ButtonStyle') {
        out[button] = style.named;
      }
    }
    return out;
  }

  void _note(String message, DartValue? at, IrSeverity severity) =>
      diagnostics.add(IrDiagnostic(severity, message, source: at?.source));
}
