import 'dart:math';

import 'package:path/path.dart' as p;

import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/ir.dart';

import 'component_extractor.dart';
import 'evaluator.dart';
import 'icon_font.dart';
import 'image_assets.dart';
import 'material_theme.dart';
import 'simplify.dart';
import 'text_style.dart';
import 'theme_extractor.dart';

/// Layout constraints flowing down the tree, reduced to what matters for
/// choosing fixed / hug / fill.
class _Box {
  const _Box({
    this.forceW = false,
    this.forceH = false,
    this.boundedW = true,
    this.boundedH = true,
  });

  /// The parent imposes its width (tight constraints) → child fills.
  final bool forceW, forceH;

  /// A maximum exists on this axis (false inside a scroll/flex main axis).
  final bool boundedW, boundedH;

  _Box copyWith({bool? forceW, bool? forceH, bool? boundedW, bool? boundedH}) =>
      _Box(
        forceW: forceW ?? this.forceW,
        forceH: forceH ?? this.forceH,
        boundedW: boundedW ?? this.boundedW,
        boundedH: boundedH ?? this.boundedH,
      );

  _Box get loose => copyWith(forceW: false, forceH: false);
}

/// The Row/Column a widget sits in directly or through wrappers that don't
/// lay anything out (project widgets, `BlocBuilder`, providers, ...).
class _FlexSlot {
  const _FlexSlot(this.parent, this.direction);

  final IrFrame parent;
  final IrLayoutDirection direction;
}

class _Ctx {
  const _Ctx({
    required this.box,
    required this.text,
    required this.iconColor,
    this.flex,
  });

  final _Box box;

  /// Set for flex children; cleared as soon as a widget lays out children
  /// ([withBox]), so `Expanded` only applies to the nearest Row/Column.
  final _FlexSlot? flex;

  /// Inherited `DefaultTextStyle`.
  final TextStyleSpec text;

  /// Inherited `IconTheme` color.
  final IrColor iconColor;

  _Ctx withBox(_Box box) => _Ctx(box: box, text: text, iconColor: iconColor);

  _Ctx withText(TextStyleSpec? style, {IrColor? iconColor}) => _Ctx(
    box: box,
    text: text.merge(style),
    iconColor: iconColor ?? this.iconColor,
    flex: flex,
  );

  _Ctx inFlex(IrFrame parent, IrLayoutDirection direction) => _Ctx(
    box: box,
    text: text,
    iconColor: iconColor,
    flex: _FlexSlot(parent, direction),
  );
}

const _passThrough = {
  'SafeArea',
  'GestureDetector',
  'InkWell',
  'InkResponse',
  'Semantics',
  'MergeSemantics',
  'ExcludeSemantics',
  'Hero',
  'Tooltip',
  'Opacity',
  'IgnorePointer',
  'AbsorbPointer',
  'RepaintBoundary',
  'KeyedSubtree',
  'Form',
  'Directionality',
  'MediaQuery',
  'IconTheme',
  'ConstrainedBox',
  'LimitedBox',
  'IntrinsicHeight',
  'IntrinsicWidth',
  'FittedBox',
  'AspectRatio',
  'Transform',
  'ClipRect',
  'ClipOval',
  'FractionallySizedBox',
  'Listener',
  'MouseRegion',
  'Focus',
  'FocusScope',
  'Scrollbar',
  'RefreshIndicator',
  'WillPopScope',
  'PopScope',
  'Dismissible',
  'Draggable',
  'AnimatedOpacity',
  'AnimatedSwitcher',
  'AnimatedSize',
  'AnimatedScale',
  'AnimatedRotation',
  'AnimatedSlide',
  'AnimatedCrossFade',
  'AnimatedDefaultTextStyle',
  'AnimatedPhysicalModel',
  'FadeTransition',
  'SlideTransition',
  'ScaleTransition',
  'RotationTransition',
  'SizeTransition',
  'DecoratedBoxTransition',
  'AlignTransition',
  'PositionedTransition',
  'TweenAnimationBuilder',
  'Offstage',
  'PageStorage',
  'NotificationListener',
  'ScrollConfiguration',
  'Shortcuts',
  'Actions',
  'CallbackShortcuts',
  'DefaultTabController',
  'Flexible',
  'Expanded',
};

/// Flutter's minimum tap target (`kMinInteractiveDimension`).
const _kMinInteractiveDimension = 48.0;

/// Compiles analyzed Flutter widget trees into [IrDocument]s.
class FlutterCompiler {
  FlutterCompiler({
    MaterialTheme theme = const MaterialTheme(),
    this.extractTheme = true,
    this.brightness,
    this.screenWidth = 390,
    this.screenHeight = 844,
    this.listPreviewCount = 3,
    this.designSystem = true,
    this.minComponentUses = 2,
    this.iconFonts = const {},
    this.assets,
  }) : eval = ValueEvaluator(
         theme,
         screenWidth: screenWidth,
         screenHeight: screenHeight,
       );

  /// Emit an [IrDesignSystem]: color variables (per theme mode), text and
  /// effect styles, and components.
  final bool designSystem;

  /// A project widget becomes a component once used this many times.
  final int minComponentUses;

  /// Icon fonts by family (e.g. `MaterialIcons`). Icons in these fonts are
  /// exported as their glyph outlines; others as placeholders.
  final Map<String, IconFont> iconFonts;

  /// Where asset images are read from; [compile] defaults it to the
  /// project being compiled.
  ProjectAssets? assets;

  /// Images painted so far, embedded in the document.
  final _images = <String, IrImageAsset>{};

  /// Read the app's `MaterialApp` theme in [compile]. When false, the
  /// constructor's `theme` is used as is.
  final bool extractTheme;

  /// Which app theme to export; null follows `MaterialApp.themeMode`.
  final ThemeBrightness? brightness;

  final ValueEvaluator eval;

  /// The ambient theme (`Theme.of(context)`) at the current point.
  MaterialTheme get theme => eval.theme;
  final double screenWidth;
  final double screenHeight;

  /// How many items to render for `ListView.builder` without a literal count.
  final int listPreviewCount;

  final _diagnostics = <String, IrDiagnostic>{};

  IrDocument compile(ProjectAnalysis analysis) {
    _diagnostics.clear();
    _images.clear();
    assets ??= ProjectAssets(analysis.root);
    if (extractTheme) {
      final extractor = ThemeExtractor(eval);
      eval.theme = extractor.fromProject(analysis, brightness: brightness);
      _absorb(extractor.diagnostics);
    }
    final screens = [
      for (final w in analysis.screens)
        compileScreen(w.name, w.tree!, w.source),
    ];

    IrDesignSystem? system;
    _painted.clear();
    for (final s in screens) {
      _collectTokens(s.root);
    }
    if (designSystem) {
      final components = ComponentExtractor(
        minUses: minComponentUses,
        sources: {for (final w in analysis.widgets) w.name: w.source},
      ).extract(screens);
      system = _designSystem(analysis, components);
    } else {
      void clear(IrNode n) {
        n.instance = null;
        if (n is IrFrame) n.children.forEach(clear);
      }

      for (final s in screens) {
        clear(s.root);
      }
    }

    return IrDocument(
      project: analysis.name,
      screens: screens,
      designSystem: system,
      images: Map.of(_images),
      diagnostics: [
        for (final d in analysis.diagnostics) IrDiagnostic(IrSeverity.error, d),
        ..._diagnostics.values,
      ],
    );
  }

  List<IrDiagnostic> get diagnostics => _diagnostics.values.toList();

  /// Deprecated scheme roles that aren't exported as variables.
  static const _deprecatedRoles = {
    'background',
    'onBackground',
    'surfaceVariant',
  };

  /// Color tokens used by fills, strokes and text, in first-use order.
  final _painted = <String>{};

  void _collectTokens(IrNode n) {
    void add(IrColor? c) {
      if (c?.token case final token?) _painted.add(token);
    }

    switch (n) {
      case IrText():
        add(n.style.color);
      case IrVector():
        add(n.fill);
      case IrFrame():
        add(n.fill);
        add(n.stroke?.color);
        n.children.forEach(_collectTokens);
    }
  }

  IrDesignSystem _designSystem(
    ProjectAnalysis analysis,
    List<IrComponent> components,
  ) {
    String modeName(ThemeBrightness b) =>
        b == ThemeBrightness.dark ? 'Dark' : 'Light';
    final active = theme;

    // Both app themes become modes of the same variables, so switching the
    // mode in Figma recolors the screens.
    final modes = <String, MaterialTheme>{};
    if (extractTheme) {
      MaterialTheme extract(ThemeBrightness b) => ThemeExtractor(
        ValueEvaluator(const MaterialTheme()),
      ).fromProject(analysis, brightness: b);
      final light = extract(ThemeBrightness.light);
      final dark = extract(ThemeBrightness.dark);
      modes[modeName(light.brightness)] = light;
      if (modes.keys.single != modeName(dark.brightness)) {
        modes[modeName(dark.brightness)] = dark;
      }
    } else {
      modes[modeName(active.brightness)] = active;
    }
    final activeMode = modes.containsKey(modeName(active.brightness))
        ? modeName(active.brightness)
        : modes.keys.first;

    return IrDesignSystem(
      modes: modes.keys.toList(),
      activeMode: activeMode,
      colors: [
        for (final role in active.colorScheme.keys)
          if (!_deprecatedRoles.contains(role))
            IrColorToken(MaterialTheme.colorToken(role), {
              for (final MapEntry(key: mode, value: t) in modes.entries)
                mode: t.color(role),
            }),
        // Project constants (`AppColors.brand`) that are actually painted.
        for (final name in _painted)
          if (eval.projectColors[name] case final color?)
            IrColorToken(name, {
              for (final mode in modes.keys) mode: color.withToken(null),
            }),
      ],
      textStyles: [
        for (final name in active.textTheme.keys)
          IrTextStyleToken(
            MaterialTheme.textToken(name),
            active.textStyle(name)!.resolve(active.fontFamily),
          ),
      ],
      shadows: active.shadowTokens,
      components: components,
    );
  }

  IrScreen compileScreen(String name, DartValue tree, String? source) {
    final ctx = _Ctx(
      box: const _Box(forceW: true, forceH: true),
      text: theme.textStyle('bodyMedium')!,
      iconColor: theme.color('onSurfaceVariant'),
    );
    final node = _widget(tree, ctx);
    final IrFrame root;
    if (node is IrFrame) {
      root = node;
    } else {
      root = IrFrame(name: name, children: [node]);
    }
    root
      ..name = name
      ..role = 'screen'
      ..width = IrSizing.fixed(screenWidth)
      ..height = IrSizing.fixed(screenHeight)
      ..clip = true;
    return IrScreen(
      name: name,
      width: screenWidth,
      height: screenHeight,
      source: source,
      root: _sanitize(simplify(root)) as IrFrame,
    );
  }

  /// Last line of defense: Figma (and JSON) can't take infinite or NaN
  /// numbers. Anything that slipped through a handler becomes fill / unset,
  /// with a warning, instead of failing the export.
  IrNode _sanitize(IrNode node) {
    bool bad(double? v) => v != null && !v.isFinite;
    void fix(String what) =>
        _warn('Non-finite $what on `${node.name}` replaced', null);
    IrSizing axis(IrSizing s, String what) {
      if (s.isFixed && bad(s.value)) {
        fix(what);
        return const IrSizing.fill();
      }
      return s;
    }

    node
      ..width = axis(node.width, 'width')
      ..height = axis(node.height, 'height');
    if (node is IrFrame) {
      if (bad(node.minWidth)) {
        fix('minWidth');
        node.minWidth = null;
      }
      if (bad(node.minHeight)) {
        fix('minHeight');
        node.minHeight = null;
      }
      if (bad(node.gap)) {
        fix('gap');
        node.gap = 0;
      }
      final p = node.padding;
      if ([p.top, p.right, p.bottom, p.left].any(bad)) {
        fix('padding');
        node.padding = IrInsets.zero;
      }
      node.children.forEach(_sanitize);
    }
    return node;
  }

  void _absorb(Iterable<IrDiagnostic> diagnostics) {
    for (final d in diagnostics) {
      _diagnostics.putIfAbsent('${d.message}@${d.source}', () => d);
    }
  }

  void _warn(
    String message,
    DartValue? at, {
    IrSeverity severity = IrSeverity.warning,
  }) {
    final d = IrDiagnostic(severity, message, source: at?.source);
    _diagnostics.putIfAbsent('$message@${at?.source}', () => d);
  }

  // -------------------------------------------------------------------------
  // Dispatch
  // -------------------------------------------------------------------------

  ObjectValue? _asWidget(DartValue? v) {
    final d = eval.deref(v);
    switch (d) {
      case ObjectValue(isWidget: true):
        return d;
      case ConditionalValue(:final condition, :final then, :final otherwise):
        // Loading/error branches are small; the screen's real content is
        // the richest branch. Ties keep the `true` branch.
        final a = _asWidget(then);
        final b = _asWidget(otherwise);
        if (a == null || b == null) return a ?? b;
        final pickElse = _richness(b) > _richness(a);
        _warn(
          'Conditional UI `$condition`: exported the '
          '${pickElse ? '`false`' : '`true`'} branch (the richer one)',
          d,
          severity: IrSeverity.info,
        );
        return pickElse ? b : a;
      case CallValue(target: final target?, method: 'call'):
        return _asWidget(target);
      default:
        return null;
    }
  }

  IrNode _widget(DartValue? v, _Ctx c) {
    final w = _asWidget(v);
    if (w == null) {
      final code = switch (v) {
        UnknownValue(:final code) => code,
        null => 'null',
        _ => v.runtimeType.toString(),
      };
      _warn('Could not statically resolve widget `$code`', v);
      return _placeholder('Unresolved: $code', v, c);
    }
    final node = w.isFlutter
        ? _flutterWidget(w, c)
        : w.build != null || w.inProject
        ? _projectWidget(w, c)
        : _genericWidget(w, c, package: true);
    node.source ??= w.source;
    if (node is IrFrame) {
      _adoptChildFill(node);
      node.shadowToken ??= theme.shadowToken(node.shadows);
    }
    return node;
  }

  /// A box that sizes to its child grows when the child expands, e.g.
  /// `Padding(child: Column())` fills the height the Column fills.
  void _adoptChildFill(IrFrame frame) {
    if (frame.direction == IrLayoutDirection.stack) return;
    if (frame.width.isHug && frame.children.any((c) => c.width.isFill)) {
      frame.width = const IrSizing.fill();
    }
    if (frame.height.isHug && frame.children.any((c) => c.height.isFill)) {
      frame.height = const IrSizing.fill();
    }
  }

  IrNode _projectWidget(ObjectValue w, _Ctx c) {
    if (w.build == null) {
      _warn('Could not expand widget `${w.type}`', w);
      return _placeholder(w.type, w, c);
    }
    final node = _widget(w.build, c);
    if (node is IrFrame) {
      node
        ..name = w.type
        ..instance = IrInstanceRef(w.type);
    }
    node.origin = [w.type, ...node.origin];
    return node;
  }

  IrNode _flutterWidget(ObjectValue w, _Ctx c) {
    switch (w.displayName) {
      case 'Scaffold':
        return _scaffold(w, c);
      case 'AppBar':
        return _appBar(w, c);
      case 'Padding' || 'AnimatedPadding':
        return _padding(w, c);
      case 'Center' || 'Align' || 'AnimatedAlign':
        return _align(w, c);
      case 'SizedBox' ||
          'SizedBox.expand' ||
          'SizedBox.shrink' ||
          'SizedBox.square' ||
          'SizedBox.fromSize':
        return _sizedBox(w, c);
      case 'Container' || 'AnimatedContainer':
        return _container(w, c);
      case 'DecoratedBox':
        return _boxLike(w, c, decoration: w['decoration']);
      case 'ColoredBox':
        return _boxLike(w, c, color: eval.color(w['color']));
      case 'ClipRRect':
        return _boxLike(
          w,
          c,
          corners: eval.borderRadius(w['borderRadius']),
          clip: true,
        );
      case 'Card' || 'Card.filled' || 'Card.outlined':
        return _card(w, c);
      case 'Material':
        return _material(w, c);
      case 'Column':
        return _flex(w, c, IrLayoutDirection.vertical);
      case 'Row':
        return _flex(w, c, IrLayoutDirection.horizontal);
      case 'Flex':
        return _flex(
          w,
          c,
          eval.enumName(w['direction']) == 'horizontal'
              ? IrLayoutDirection.horizontal
              : IrLayoutDirection.vertical,
        );
      case 'Wrap':
        _warn(
          'Wrap is exported as a Row without wrapping',
          w,
          severity: IrSeverity.info,
        );
        return _flex(w, c, IrLayoutDirection.horizontal);
      case 'Stack':
        return _stack(w, c);
      case 'Spacer':
        return _spacer(w, c, c.flex?.direction ?? IrLayoutDirection.vertical);
      case 'Text':
        return _text(w, c, eval.text(w.arg(0)));
      case 'Text.rich' || 'RichText' || 'SelectableText.rich':
        final span = eval.deref(w.arg(0) ?? w['text']);
        return _text(
          w,
          c,
          eval.spanText(span),
          spanStyle: span is ObjectValue ? eval.textStyle(span['style']) : null,
        );
      case 'SelectableText':
        return _text(w, c, eval.text(w.arg(0)));
      case 'Theme':
        final extractor = ThemeExtractor(eval);
        final nested = extractor.themeData(w['data'], current: theme);
        _absorb(extractor.diagnostics);
        final node = _withTheme(nested, () => _widget(w['child'], c));
        node.origin = ['Theme', ...node.origin];
        return node;
      case 'DefaultTextStyle':
        return _widget(w['child'], c.withText(eval.textStyle(w['style'])));
      case 'Icon':
        return _icon(w, c);
      case 'Image' ||
          'Image.asset' ||
          'Image.network' ||
          'Image.file' ||
          'Image.memory' ||
          'SvgPicture' ||
          'SvgPicture.asset' ||
          'SvgPicture.network' ||
          'SvgPicture.string' ||
          'SvgPicture.file' ||
          'SvgPicture.memory':
        return _image(w, c);
      case 'ElevatedButton' ||
          'ElevatedButton.icon' ||
          'FilledButton' ||
          'FilledButton.icon' ||
          'FilledButton.tonal' ||
          'FilledButton.tonalIcon' ||
          'OutlinedButton' ||
          'OutlinedButton.icon' ||
          'TextButton' ||
          'TextButton.icon':
        return _button(w, c);
      case 'IconButton' ||
          'IconButton.filled' ||
          'IconButton.filledTonal' ||
          'IconButton.outlined':
        return _iconButton(w, c);
      case 'FloatingActionButton' || 'FloatingActionButton.extended':
        return _fab(w, c);
      case 'Switch' || 'Switch.adaptive':
        return _switch(w);
      case 'Checkbox' || 'Checkbox.adaptive':
        return _checkbox(w);
      case 'Radio' || 'Radio.adaptive':
        return _radio(w);
      case 'GridView' ||
          'GridView.count' ||
          'GridView.extent' ||
          'GridView.builder':
        return _grid(w, c);
      case 'TextField' || 'TextFormField':
        return _textField(w, c);
      case 'CircularProgressIndicator' || 'CircularProgressIndicator.adaptive':
        return _circularProgress(w);
      case 'LinearProgressIndicator':
        return _linearProgress(w, c);
      case 'Divider' || 'VerticalDivider':
        return _divider(w, c);
      case 'ListView' || 'ListView.builder' || 'ListView.separated':
        return _listView(w, c);
      case 'SingleChildScrollView':
        return _scrollView(w, c);
      case 'Builder' || 'LayoutBuilder':
        final builder = eval.deref(w['builder']);
        return _widget(builder is FunctionValue ? builder.returns : builder, c);
      case 'Visibility':
        if (_isLiteral(w['visible'], false)) {
          return _empty(w);
        }
        return _widget(w['child'], c);
    }

    if ((w.type == 'Expanded' || w.type == 'Flexible') && c.flex != null) {
      return _expanded(w, c, c.flex!);
    }
    if (_passThrough.contains(w.type) && w['child'] != null) {
      if (w.type == 'Expanded' || w.type == 'Flexible') {
        _warn('${w.type} outside of a Row/Column', w);
      }
      final node = _widget(w['child'], c);
      node.origin = [w.type, ...node.origin];
      return node;
    }

    return _genericWidget(w, c, package: false);
  }

  /// A widget without a dedicated handler: an unknown Flutter widget, or one
  /// from a package (`BlocBuilder`, `BlocProvider`, `Consumer`, ...).
  ///
  /// Keeps the subtree visible: renders the `builder` callback's result, else
  /// passes through to `child`, else lays out `children`, else a placeholder.
  /// Flagged as a warning for Flutter widgets (their visuals are missing) and
  /// as info for package wrappers (usually state management, no visuals).
  IrNode _genericWidget(ObjectValue w, _Ctx c, {required bool package}) {
    final severity = package ? IrSeverity.info : IrSeverity.warning;
    final what = package ? 'Package widget' : 'Unsupported widget';

    final builder = eval.deref(w['builder']);
    final built = builder is FunctionValue ? _asWidget(builder.returns) : null;
    if (built != null) {
      _warn(
        '$what `${w.displayName}`: rendered its builder '
        '(state-dependent UI shows one state)',
        w,
        severity: IrSeverity.info,
      );
      final node = _widget(built, c);
      node.origin = [w.type, ...node.origin];
      return node;
    }
    final child = w['child'];
    if (child != null) {
      _warn(
        '$what `${w.displayName}`: exported its child only',
        w,
        severity: severity,
      );
      final node = _widget(child, c);
      node.origin = [w.type, ...node.origin];
      return node;
    }
    final children = _items(w['children']);
    if (children != null) {
      _warn(
        '$what `${w.displayName}`: exported its children in a column',
        w,
        severity: severity,
      );
      return IrFrame(
        name: w.displayName,
        origin: [w.type],
        children: [
          for (final i in children) _widget(i, c.withBox(c.box.loose)),
        ],
      );
    }
    _warn('$what `${w.displayName}`', w);
    return _placeholder(w.displayName, w, c);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Compiles with [nested] as `Theme.of(context)`.
  T _withTheme<T>(MaterialTheme nested, T Function() body) {
    final outer = eval.theme;
    eval.theme = nested;
    try {
      return body();
    } finally {
      eval.theme = outer;
    }
  }

  /// How much UI a value describes: widgets written inline (capped).
  int _richness(DartValue? v, [int depth = 0]) {
    if (v == null || depth > 24) return 0;
    final d = eval.deref(v);
    final int score = switch (d) {
      // Another widget class counts as one widget: a branch that shows a
      // different screen shouldn't outweigh this screen's own UI.
      ObjectValue() =>
        (d.isWidget ? 1 : 0) +
            [
              ...d.positional,
              ...d.named.values,
            ].fold(0, (n, a) => n + _richness(a, depth + 1)),
      ListValue(:final items) => items.fold(
        0,
        (n, i) => n + _richness(i, depth + 1),
      ),
      LoopValue(:final body) => _richness(body, depth + 1),
      FunctionValue(:final returns) => _richness(returns, depth + 1),
      ConditionalValue(:final then, :final otherwise) => max(
        _richness(then, depth + 1),
        _richness(otherwise, depth + 1),
      ),
      _ => 0,
    };
    return min(score, 1000);
  }

  /// Children of a list-valued argument, with loops expanded. Loops over
  /// known items were already unrolled by the analyzer; a collection `for`
  /// or `items.map((x) => Widget(...))` over runtime data repeats its body
  /// [listPreviewCount] times.
  List<DartValue>? _items(DartValue? v) {
    final d = eval.deref(v);
    if (d is ListValue) return [for (final i in d.items) ..._expand(i)];
    final repeated = _expand(d);
    return identical(repeated.firstOrNull, d) ? null : repeated;
  }

  List<DartValue> _expand(DartValue? item) {
    final d = eval.deref(item);
    if (d is ListValue) return [for (final i in d.items) ..._expand(i)];
    final (String? loop, DartValue? body) = switch (d) {
      LoopValue(:final loop, :final body) => ('for ($loop)', body),
      CallValue(method: 'toList' || 'toSet', target: final t?) => switch (eval
          .deref(t)) {
        ListValue() => ('', null),
        CallValue(method: 'map', positional: [FunctionValue(:final returns)])
            when returns != null =>
          ('.map()', returns),
        _ => (null, null),
      },
      CallValue(method: 'map', positional: [FunctionValue(:final returns)])
          when returns != null =>
        ('.map()', returns),
      _ => (null, null),
    };
    // `.toList()` on a list the analyzer already unrolled.
    if (loop == '' && d is CallValue) return _expand(d.target);
    if (loop == null || body == null) return [?d];
    _warn(
      '`$loop`: rendered $listPreviewCount sample items',
      d,
      severity: IrSeverity.info,
    );
    return List.filled(listPreviewCount, body);
  }

  bool _isLiteral(DartValue? v, Object? value) =>
      v is LiteralValue && v.value == value;

  IrSizing _hugOrFill(bool fill) =>
      fill ? const IrSizing.fill() : const IrSizing.hug();

  IrFrame _placeholder(String name, DartValue? at, _Ctx c) => IrFrame(
    name: '⚠ $name',
    role: 'placeholder',
    width: c.box.forceW ? const IrSizing.fill() : const IrSizing.fixed(120),
    height: const IrSizing.fixed(40),
    mainAlign: IrMainAlign.center,
    crossAlign: IrCrossAlign.center,
    fill: const IrColor(1, 0, 1, 0.08),
    stroke: const IrStroke(color: IrColor(1, 0, 1, 0.6)),
    source: at?.source,
    children: [
      IrText(
        name: name,
        text: name,
        style: TextStyleSpec(
          fontSize: 11,
          color: const IrColor(0.6, 0, 0.6),
        ).resolve(theme.fontFamily),
      ),
    ],
  );

  IrFrame _empty(ObjectValue w) => IrFrame(
    name: w.type,
    origin: [w.type],
    width: const IrSizing.fixed(0),
    height: const IrSizing.fixed(0),
  );

  /// Axis sizing for a box with an optional explicit dimension.
  IrSizing _axis(
    double? dimension, {
    required bool forced,
    required bool bounded,
    required bool expands,
  }) {
    if (dimension != null) {
      if (dimension.isInfinite) {
        return bounded ? const IrSizing.fill() : const IrSizing.hug();
      }
      return IrSizing.fixed(dimension);
    }
    if (forced) return const IrSizing.fill();
    if (expands && bounded) return const IrSizing.fill();
    return const IrSizing.hug();
  }

  /// Child constraints inside a frame with the given sizing.
  _Box _inner(IrSizing w, IrSizing h, _Box outer, {bool loose = false}) => _Box(
    forceW: !loose && !w.isHug,
    forceH: !loose && !h.isHug,
    boundedW: !w.isHug || outer.boundedW,
    boundedH: !h.isHug || outer.boundedH,
  );

  (IrMainAlign, IrCrossAlign) _alignFor(
    (double, double)? a,
    IrLayoutDirection direction,
  ) {
    if (a == null) return (IrMainAlign.start, IrCrossAlign.start);
    IrMainAlign main(double v) => v < 0
        ? IrMainAlign.start
        : v > 0
        ? IrMainAlign.end
        : IrMainAlign.center;
    IrCrossAlign cross(double v) => v < 0
        ? IrCrossAlign.start
        : v > 0
        ? IrCrossAlign.end
        : IrCrossAlign.center;
    final (x, y) = a;
    return direction == IrLayoutDirection.horizontal
        ? (main(x), cross(y))
        : (main(y), cross(x));
  }

  // -------------------------------------------------------------------------
  // Structure
  // -------------------------------------------------------------------------

  IrFrame _scaffold(ObjectValue w, _Ctx c) {
    final children = <IrNode>[];
    final appBar = w['appBar'];
    if (appBar != null) {
      children.add(_widget(appBar, c.withBox(const _Box(forceW: true))));
    }
    final body = w['body'];
    if (body != null) {
      children.add(
        _widget(body, c.withBox(const _Box(forceW: true, forceH: false))),
      );
    }
    final fab = w['floatingActionButton'];
    if (fab != null) {
      children.add(
        _widget(fab, c.withBox(const _Box()))
          ..position = const IrPosition(right: 16, bottom: 16),
      );
    }
    for (final slot in ['bottomNavigationBar', 'drawer', 'bottomSheet']) {
      if (w[slot] != null) _warn('Scaffold.$slot is not exported yet', w[slot]);
    }
    return IrFrame(
      name: 'Scaffold',
      origin: ['Scaffold'],
      width: const IrSizing.fill(),
      height: const IrSizing.fill(),
      fill:
          eval.color(w['backgroundColor']) ??
          theme.scaffoldBackground ??
          theme.color('surface'),
      children: children,
    );
  }

  IrFrame _appBar(ObjectValue w, _Ctx c) {
    final appBarTheme = theme.appBar;
    final foreground =
        eval.color(w['foregroundColor']) ??
        appBarTheme.foregroundColor ??
        theme.color('onSurface');
    final titleStyle =
        eval.textStyle(w['titleTextStyle']) ??
        appBarTheme.titleTextStyle ??
        TextStyleSpec(color: foreground);
    final titleCtx = c
        .withText(
          theme.textStyle('titleLarge')!.merge(titleStyle),
          iconColor: foreground,
        )
        .withBox(const _Box(forceW: true));
    final leading = w['leading'];
    final title = w['title'];
    final actions = _items(w['actions']) ?? const [];
    final hasActions = actions.isNotEmpty;
    final centerTitle = switch (w['centerTitle']) {
      LiteralValue(value: final bool b) => b,
      _ => appBarTheme.centerTitle ?? false,
    };

    final titleNode = title == null ? null : _widget(title, titleCtx);
    if (titleNode is IrText && centerTitle) {
      titleNode.align = IrTextAlign.center;
    }

    return IrFrame(
      name: 'AppBar',
      role: 'app-bar',
      origin: ['AppBar'],
      direction: IrLayoutDirection.horizontal,
      width: const IrSizing.fill(),
      height: IrSizing.fixed(
        eval.number(w['toolbarHeight']) ?? appBarTheme.toolbarHeight ?? 64,
      ),
      crossAlign: IrCrossAlign.center,
      gap: leading != null ? 16 : 0,
      padding: IrInsets(
        left: leading != null ? 4 : 16,
        right: hasActions ? 4 : 16,
      ),
      fill:
          eval.color(w['backgroundColor']) ??
          appBarTheme.backgroundColor ??
          theme.color('surface'),
      shadows: theme.shadows(
        eval.number(w['elevation']) ?? appBarTheme.elevation ?? 0,
      ),
      children: [
        if (leading != null) _widget(leading, titleCtx.withBox(const _Box())),
        if (titleNode != null) titleNode..width = const IrSizing.fill(),
        if (titleNode == null && hasActions)
          IrFrame(
            name: 'Spacer',
            width: const IrSizing.fill(),
            height: const IrSizing.fixed(0),
          ),
        if (hasActions)
          for (final a in actions) _widget(a, titleCtx.withBox(const _Box())),
      ],
    );
  }

  IrNode _padding(ObjectValue w, _Ctx c) {
    final padding = eval.insets(w['padding']) ?? IrInsets.zero;
    final width = _hugOrFill(c.box.forceW);
    final height = _hugOrFill(c.box.forceH);
    return IrFrame(
      name: 'Padding',
      origin: ['Padding'],
      width: width,
      height: height,
      padding: padding,
      children: [
        if (w['child'] != null)
          _widget(w['child'], c.withBox(_inner(width, height, c.box))),
      ],
    );
  }

  IrNode _align(ObjectValue w, _Ctx c) {
    final widthFactor = eval.number(w['widthFactor']);
    final heightFactor = eval.number(w['heightFactor']);
    final width = _axis(
      null,
      forced: c.box.forceW,
      bounded: c.box.boundedW,
      expands: widthFactor == null,
    );
    final height = _axis(
      null,
      forced: c.box.forceH,
      bounded: c.box.boundedH,
      expands: heightFactor == null,
    );
    final alignment = w.type == 'Center'
        ? (0.0, 0.0)
        : eval.alignment(w['alignment']) ?? (0.0, 0.0);
    final (main, cross) = _alignFor(alignment, IrLayoutDirection.vertical);
    return IrFrame(
      name: w.type,
      origin: [w.type],
      width: width,
      height: height,
      mainAlign: main,
      crossAlign: cross,
      children: [
        if (w['child'] != null)
          _widget(
            w['child'],
            c.withBox(_inner(width, height, c.box, loose: true)),
          ),
      ],
    );
  }

  IrNode _sizedBox(ObjectValue w, _Ctx c) {
    double? width, height;
    switch (w.constructor) {
      case 'expand':
        width = height = double.infinity;
      case 'shrink':
        width = height = 0;
      case 'square':
        width = height = eval.number(w['dimension']);
      default:
        width = eval.number(w['width']);
        height = eval.number(w['height']);
    }
    final child = w['child'];
    final ws = _axis(
      width,
      forced: c.box.forceW,
      bounded: c.box.boundedW,
      expands: false,
    );
    final hs = _axis(
      height,
      forced: c.box.forceH,
      bounded: c.box.boundedH,
      expands: false,
    );
    if (child == null) {
      return IrFrame(
        name: 'SizedBox',
        role: 'spacer',
        origin: ['SizedBox'],
        width: ws.isHug ? const IrSizing.fixed(0) : ws,
        height: hs.isHug ? const IrSizing.fixed(0) : hs,
      );
    }
    return IrFrame(
      name: 'SizedBox',
      origin: ['SizedBox'],
      width: ws,
      height: hs,
      children: [_widget(child, c.withBox(_inner(ws, hs, c.box)))],
    );
  }

  IrNode _container(ObjectValue w, _Ctx c) {
    final alignment = eval.alignment(w['alignment']);
    final child = w['child'];
    var width = eval.number(w['width']);
    var height = eval.number(w['height']);
    final constraints = eval.deref(w['constraints']);
    double? minWidth, minHeight;
    if (constraints is ObjectValue && constraints.type == 'BoxConstraints') {
      switch (constraints.constructor) {
        case 'expand':
          width ??= eval.number(constraints['width']) ?? double.infinity;
          height ??= eval.number(constraints['height']) ?? double.infinity;
        case 'tightFor':
          width ??= eval.number(constraints['width']);
          height ??= eval.number(constraints['height']);
        default:
          minWidth = eval.number(constraints['minWidth']);
          minHeight = eval.number(constraints['minHeight']);
      }
    }

    final expands = child == null || alignment != null;
    final ws = _axis(
      width,
      forced: c.box.forceW,
      bounded: c.box.boundedW,
      expands: expands,
    );
    final hs = _axis(
      height,
      forced: c.box.forceH,
      bounded: c.box.boundedH,
      expands: expands,
    );

    final frame = _decorated(
      name: 'Container',
      decoration: w['decoration'],
      color: eval.color(w['color']),
      width: child == null && ws.isHug ? const IrSizing.fixed(0) : ws,
      height: child == null && hs.isHug ? const IrSizing.fixed(0) : hs,
    );
    final (main, cross) = _alignFor(alignment, IrLayoutDirection.vertical);
    frame
      ..padding = eval.insets(w['padding']) ?? IrInsets.zero
      ..mainAlign = main
      ..crossAlign = cross
      ..minWidth = minWidth
      ..minHeight = minHeight;
    if (w['clipBehavior'] case RefValue(last: final clip) when clip != 'none') {
      frame.clip = true;
    }
    if (child != null) {
      frame.children.add(
        _widget(
          child,
          c.withBox(_inner(ws, hs, c.box, loose: alignment != null)),
        ),
      );
    }
    return _withMargin(frame, eval.insets(w['margin']));
  }

  /// A frame painted from a `BoxDecoration`.
  IrFrame _decorated({
    required String name,
    DartValue? decoration,
    IrColor? color,
    IrSizing width = const IrSizing.hug(),
    IrSizing height = const IrSizing.hug(),
  }) {
    final frame = IrFrame(
      name: name,
      origin: [name],
      width: width,
      height: height,
      fill: color,
    );
    final d = eval.deref(decoration);
    if (d is ObjectValue && d.type == 'BoxDecoration') {
      frame
        ..fill = eval.color(d['color']) ?? color
        ..corners = eval.borderRadius(d['borderRadius']) ?? IrCorners.zero
        ..stroke = eval.border(d['border'])
        ..shadows = eval.boxShadows(d['boxShadow']);
      if (eval.enumName(d['shape']) == 'circle') {
        frame.corners = const IrCorners.all(9999);
      }
      final gradient = eval.deref(d['gradient']);
      if (gradient is ObjectValue) {
        final colors = eval.deref(gradient['colors']);
        if (colors is ListValue && colors.items.isNotEmpty) {
          frame.fill ??= eval.color(colors.items.first);
        }
        _warn(
          'Gradients are exported as a solid fill',
          gradient,
          severity: IrSeverity.info,
        );
      }
      final image = eval.deref(d['image']);
      if (image is ObjectValue && image.type == 'DecorationImage') {
        final (asset, _) = _imageProvider(image['image'], image);
        if (asset != null) {
          frame.image = IrImagePaint(
            asset.key,
            fit: _boxFit(image['fit'], asset),
          );
        }
      }
    } else if (d is ObjectValue && d.type == 'ShapeDecoration') {
      final (corners, stroke) = eval.shape(d['shape']);
      frame
        ..fill = eval.color(d['color']) ?? color
        ..corners = corners ?? IrCorners.zero
        ..stroke = stroke
        ..shadows = eval.boxShadows(d['shadows']);
    }
    return frame;
  }

  /// Wraps [inner] in a transparent frame carrying the margin. The wrapper
  /// takes the widget's name, since it is what the widget occupies.
  IrNode _withMargin(IrFrame inner, IrInsets? margin) {
    if (margin == null || margin.isZero) return inner;
    final name = inner.name;
    inner.name = '$name · surface';
    return IrFrame(
      name: name,
      origin: const ['margin'],
      width: inner.width.isFixed ? const IrSizing.hug() : inner.width,
      height: inner.height.isFixed ? const IrSizing.hug() : inner.height,
      padding: margin,
      children: [inner],
    );
  }

  /// Single-child box that paints but doesn't size itself.
  IrNode _boxLike(
    ObjectValue w,
    _Ctx c, {
    DartValue? decoration,
    IrColor? color,
    IrCorners? corners,
    bool clip = false,
  }) {
    final ws = _hugOrFill(c.box.forceW);
    final hs = _hugOrFill(c.box.forceH);
    final frame = _decorated(
      name: w.type,
      decoration: decoration,
      color: color,
      width: ws,
      height: hs,
    );
    if (corners != null) frame.corners = corners;
    frame.clip = clip;
    if (w['child'] != null) {
      frame.children.add(_widget(w['child'], c.withBox(_inner(ws, hs, c.box))));
    }
    return frame;
  }

  IrNode _card(ObjectValue w, _Ctx c) {
    final ws = _hugOrFill(c.box.forceW);
    final hs = _hugOrFill(c.box.forceH);
    final cardTheme = theme.card;
    final (shapeCorners, shapeStroke) = eval.shape(w['shape']);
    final (themeCorners, themeStroke) = eval.shape(cardTheme.shape);
    final (
      defaultFill,
      defaultElevation,
      defaultStroke,
    ) = switch (w.constructor) {
      'filled' => (theme.color('surfaceContainerHighest'), 0.0, null),
      'outlined' => (
        theme.color('surface'),
        0.0,
        IrStroke(color: theme.color('outlineVariant')),
      ),
      _ => (theme.color('surfaceContainerLow'), 1.0, null),
    };
    final frame = IrFrame(
      name: 'Card',
      role: 'card',
      origin: ['Card'],
      width: ws,
      height: hs,
      fill: eval.color(w['color']) ?? cardTheme.color ?? defaultFill,
      corners: shapeCorners ?? themeCorners ?? const IrCorners.all(12),
      stroke: shapeStroke ?? themeStroke ?? defaultStroke,
      shadows: theme.shadows(
        eval.number(w['elevation']) ?? cardTheme.elevation ?? defaultElevation,
      ),
      clip: w['clipBehavior'] != null,
    );
    if (w['child'] != null) {
      frame.children.add(_widget(w['child'], c.withBox(_inner(ws, hs, c.box))));
    }
    return _withMargin(
      frame,
      eval.insets(w['margin']) ?? cardTheme.margin ?? const IrInsets.all(4),
    );
  }

  IrNode _material(ObjectValue w, _Ctx c) {
    final ws = _hugOrFill(c.box.forceW);
    final hs = _hugOrFill(c.box.forceH);
    final (shapeCorners, shapeStroke) = eval.shape(w['shape']);
    final frame = IrFrame(
      name: 'Material',
      origin: ['Material'],
      width: ws,
      height: hs,
      fill: eval.color(w['color']),
      corners:
          eval.borderRadius(w['borderRadius']) ??
          shapeCorners ??
          IrCorners.zero,
      stroke: shapeStroke,
      shadows: theme.shadows(eval.number(w['elevation']) ?? 0),
    );
    if (w['child'] != null) {
      frame.children.add(_widget(w['child'], c.withBox(_inner(ws, hs, c.box))));
    }
    return frame;
  }

  IrFrame _flex(ObjectValue w, _Ctx c, IrLayoutDirection direction) {
    final vertical = direction == IrLayoutDirection.vertical;
    final mainMax = eval.enumName(w['mainAxisSize']) != 'min';
    final crossName = eval.enumName(w['crossAxisAlignment']) ?? 'center';
    final mainName = eval.enumName(w['mainAxisAlignment']) ?? 'start';

    final boundedMain = vertical ? c.box.boundedH : c.box.boundedW;
    final forcedMain = vertical ? c.box.forceH : c.box.forceW;
    final boundedCross = vertical ? c.box.boundedW : c.box.boundedH;
    final forcedCross = vertical ? c.box.forceW : c.box.forceH;
    final stretch = crossName == 'stretch' && boundedCross;

    final mainSizing = _hugOrFill(forcedMain || (mainMax && boundedMain));
    final crossSizing = _hugOrFill(forcedCross || stretch);

    final mainAlign = switch (mainName) {
      'center' => IrMainAlign.center,
      'end' => IrMainAlign.end,
      'spaceBetween' => IrMainAlign.spaceBetween,
      'spaceAround' || 'spaceEvenly' => IrMainAlign.spaceBetween,
      _ => IrMainAlign.start,
    };
    if (mainName == 'spaceAround' || mainName == 'spaceEvenly') {
      _warn(
        'MainAxisAlignment.$mainName approximated as spaceBetween',
        w,
        severity: IrSeverity.info,
      );
    }
    final crossAlign = switch (crossName) {
      'start' || 'stretch' => IrCrossAlign.start,
      'end' => IrCrossAlign.end,
      'baseline' => IrCrossAlign.baseline,
      _ => IrCrossAlign.center,
    };

    final frame = IrFrame(
      name: w.type,
      origin: [w.type],
      direction: direction,
      width: vertical ? crossSizing : mainSizing,
      height: vertical ? mainSizing : crossSizing,
      mainAlign: mainAlign,
      crossAlign: crossAlign,
      gap: eval.number(w['spacing']) ?? 0,
    );

    // Children: unbounded on the main axis, loose (or tight for stretch) on
    // the cross axis.
    final childBox = _Box(
      forceW: vertical ? stretch : false,
      forceH: vertical ? false : stretch,
      boundedW: vertical ? boundedCross || !crossSizing.isHug : false,
      boundedH: vertical ? false : boundedCross || !crossSizing.isHug,
    );
    final items = _items(w['children']);
    if (items != null) {
      for (final item in items) {
        final child = _flexChild(item, c.withBox(childBox), frame, direction);
        if (child != null) frame.children.add(child);
      }
    }
    _extractGap(frame);
    return frame;
  }

  IrNode? _flexChild(
    DartValue item,
    _Ctx c,
    IrFrame parent,
    IrLayoutDirection direction,
  ) => _widget(item, c.inFlex(parent, direction));

  /// `Expanded` / `Flexible` in a Row or Column: fill (or share) the main axis.
  IrNode _expanded(ObjectValue w, _Ctx c, _FlexSlot slot) {
    final vertical = slot.direction == IrLayoutDirection.vertical;
    final parent = slot.parent;
    final tight = w.type == 'Expanded' || eval.enumName(w['fit']) == 'tight';
    final mainFill = !(vertical ? parent.height : parent.width).isHug;
    if (!mainFill) {
      _warn('${w.type} inside a ${parent.name} with unbounded main axis', w);
    }
    final box = vertical
        ? c.box.copyWith(forceH: tight && mainFill, boundedH: mainFill)
        : c.box.copyWith(forceW: tight && mainFill, boundedW: mainFill);
    final node = _widget(w['child'], c.withBox(box));
    node.origin = [w.type, ...node.origin];
    node.source ??= w.source;
    if (tight && mainFill) {
      if (vertical) {
        node.height = const IrSizing.fill();
      } else {
        node.width = const IrSizing.fill();
      }
    }
    return node;
  }

  IrFrame _spacer(ObjectValue w, _Ctx c, IrLayoutDirection direction) {
    final vertical = direction == IrLayoutDirection.vertical;
    return IrFrame(
      name: 'Spacer',
      origin: ['Spacer'],
      width: vertical ? const IrSizing.fixed(0) : const IrSizing.fill(),
      height: vertical ? const IrSizing.fill() : const IrSizing.fixed(0),
      source: w.source,
    );
  }

  /// `[a, SizedBox(16), b, SizedBox(16), c]` → gap 16 with `[a, b, c]`.
  void _extractGap(IrFrame frame) {
    final vertical = frame.direction == IrLayoutDirection.vertical;
    final kids = frame.children;
    double? size(IrNode n) {
      if (n is! IrFrame || n.role != 'spacer') return null;
      final s = vertical ? n.height : n.width;
      return s.isFixed ? s.value : null;
    }

    if (frame.gap == 0 && kids.length >= 3 && kids.length.isOdd) {
      final gaps = <double>{};
      var alternates = true;
      for (var i = 0; i < kids.length; i++) {
        final s = size(kids[i]);
        if (i.isOdd) {
          if (s == null) alternates = false;
          gaps.add(s ?? -1);
        } else if (s != null) {
          alternates = false;
        }
      }
      if (alternates && gaps.length == 1) {
        final spacers = [for (var i = 1; i < kids.length; i += 2) kids[i]];
        frame.gap = gaps.single;
        frame.children = [for (var i = 0; i < kids.length; i += 2) kids[i]];
        frame.origin = {
          ...frame.origin,
          for (final s in spacers) ...s.origin,
        }.toList();
        return;
      }
    }
    for (final k in kids) {
      if (k is IrFrame && k.role == 'spacer') {
        final label = size(k)?.toStringAsFixed(0) ?? '';
        k
          ..role = null
          ..name = 'Spacer $label'.trim();
      }
    }
  }

  IrFrame _stack(ObjectValue w, _Ctx c) {
    final fit = eval.enumName(w['fit']);
    final ws = _axis(
      null,
      forced: c.box.forceW,
      bounded: c.box.boundedW,
      expands: true,
    );
    final hs = _axis(
      null,
      forced: c.box.forceH,
      bounded: c.box.boundedH,
      expands: true,
    );
    if (ws.isHug || hs.isHug) {
      _warn('Stack in unbounded space: size is approximated', w);
    }
    final frame = IrFrame(
      name: 'Stack',
      origin: ['Stack'],
      direction: IrLayoutDirection.stack,
      width: ws.isHug ? IrSizing.fixed(screenWidth) : ws,
      height: hs.isHug ? const IrSizing.fixed(200) : hs,
      clip: eval.enumName(w['clipBehavior']) != 'none',
    );
    final alignment = eval.alignment(w['alignment']) ?? (-1.0, -1.0);
    final items = _items(w['children']);
    if (items != null) {
      for (final item in items) {
        final child = _asWidget(item);
        if (child != null &&
            child.isFlutter &&
            child.displayName.startsWith('Positioned')) {
          final node = _widget(
            child['child'],
            c.withBox(const _Box(boundedW: false, boundedH: false)),
          );
          final width = eval.number(child['width']);
          final height = eval.number(child['height']);
          if (width != null) node.width = IrSizing.fixed(width);
          if (height != null) node.height = IrSizing.fixed(height);
          final fill = child.constructor == 'fill';
          node
            ..origin = ['Positioned', ...node.origin]
            ..position = IrPosition(
              left: eval.number(child['left']) ?? (fill ? 0 : null),
              top: eval.number(child['top']) ?? (fill ? 0 : null),
              right: eval.number(child['right']) ?? (fill ? 0 : null),
              bottom: eval.number(child['bottom']) ?? (fill ? 0 : null),
            );
          frame.children.add(node);
        } else {
          final expand = fit == 'expand';
          final node = _widget(
            item,
            c.withBox(_Box(forceW: expand, forceH: expand)),
          );
          final (x, y) = alignment;
          // StackFit.expand: children get the Stack's size, i.e. are
          // pinned on all four sides (so they keep stretching with it).
          node.position = expand
              ? const IrPosition(left: 0, top: 0, right: 0, bottom: 0)
              : IrPosition(
                  left: x < 0 ? 0 : null,
                  right: x > 0 ? 0 : null,
                  top: y < 0 ? 0 : null,
                  bottom: y > 0 ? 0 : null,
                );
          frame.children.add(node);
        }
      }
    }
    return frame;
  }

  // -------------------------------------------------------------------------
  // Content
  // -------------------------------------------------------------------------

  IrText _text(ObjectValue w, _Ctx c, String text, {TextStyleSpec? spanStyle}) {
    final style = c.text.merge(spanStyle).merge(eval.textStyle(w['style']));
    final align = switch (eval.enumName(w['textAlign'])) {
      'center' => IrTextAlign.center,
      'right' || 'end' => IrTextAlign.right,
      'justify' => IrTextAlign.justify,
      _ => IrTextAlign.left,
    };
    final label = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    return IrText(
      name: label.isEmpty ? 'Text' : label,
      origin: [w.type],
      text: text,
      style: _withTextToken(style.resolve(theme.fontFamily)),
      align: align,
      maxLines: eval.integer(w['maxLines']),
      width: _hugOrFill(c.box.forceW),
    );
  }

  /// Keeps the text style token only if the final typography still matches
  /// it; otherwise looks for a theme style with identical typography.
  IrTextStyle _withTextToken(IrTextStyle style) {
    IrTextStyle? tokenStyle(String name) =>
        theme.textStyle(name)?.resolve(theme.fontFamily);
    final claimed = MaterialTheme.textStyleName(style.token);
    if (claimed != null && tokenStyle(claimed)?.sameTypography(style) == true) {
      return style;
    }
    for (final name in theme.textTheme.keys) {
      if (tokenStyle(name)!.sameTypography(style)) {
        return style.withToken(MaterialTheme.textToken(name));
      }
    }
    return style.withToken(null);
  }

  IrFrame _icon(ObjectValue w, _Ctx c) {
    final size = eval.number(w['size']) ?? 24;
    final iconRef = w.arg(0);
    var named = iconRef;
    while (named is ConditionalValue) {
      named = named.then;
    }
    final name = named is RefValue ? named.last : 'icon';
    final color = eval.color(w['color']) ?? c.iconColor;
    final frame = IrFrame(
      name: 'Icon/$name',
      role: 'icon',
      origin: ['Icon'],
      direction: IrLayoutDirection.stack,
      width: IrSizing.fixed(size),
      height: IrSizing.fixed(size),
    );

    // An icon chosen by an unknown condition shows its `true` branch, like
    // other values.
    var data = eval.deref(iconRef);
    for (var i = 0; i < 8 && data is ConditionalValue; i++) {
      data = eval.deref(data.then);
    }
    final glyph = switch (data) {
      ObjectValue(type: 'IconData') =>
        iconFonts[eval.string(data['fontFamily'])]?.glyph(
          eval.integer(data.arg(0)) ?? -1,
          size,
        ),
      _ => null,
    };
    if (glyph == null) {
      _warn(
        'Icons outside known icon fonts are exported as placeholders',
        w,
        severity: IrSeverity.info,
      );
      return frame
        ..fill = color.withAlpha(color.a * 0.24)
        ..corners = IrCorners.all(size / 6);
    }
    if (!glyph.isEmpty) {
      frame.children.add(
        IrVector(
          name: name,
          path: glyph.path,
          fill: color,
          width: IrSizing.fixed(max(0.01, glyph.width)),
          height: IrSizing.fixed(max(0.01, glyph.height)),
          position: IrPosition(left: glyph.x, top: glyph.y),
        ),
      );
    }
    return frame;
  }

  IrFrame _image(ObjectValue w, _Ctx c) {
    // `double.infinity` takes the available space, like tight constraints.
    final rawWidth = eval.number(w['width']);
    final rawHeight = eval.number(w['height']);
    final width = rawWidth?.isFinite ?? false ? rawWidth : null;
    final height = rawHeight?.isFinite ?? false ? rawHeight : null;
    final fillW =
        width == null &&
        (c.box.forceW || (rawWidth?.isInfinite ?? false) && c.box.boundedW);
    final fillH =
        height == null &&
        (c.box.forceH || (rawHeight?.isInfinite ?? false) && c.box.boundedH);
    final (asset, label) = switch (w.constructor) {
      'asset' => _assetImage(w.arg(0), eval.string(w['package']), w),
      null when w.type == 'Image' => _imageProvider(w['image'], w),
      _ => _unembedded(w),
    };
    final name = 'Image/${p.basename(label)}';
    if (asset == null) {
      return IrFrame(
        name: name,
        role: 'image',
        origin: [w.type],
        width: width != null
            ? IrSizing.fixed(width)
            : fillW
            ? const IrSizing.fill()
            : const IrSizing.fixed(120),
        height: height != null
            ? IrSizing.fixed(height)
            : fillH
            ? const IrSizing.fill()
            : const IrSizing.fixed(120),
        fill: theme.color('surfaceContainerHighest'),
      );
    }

    // RenderImage: the given dimensions, else the intrinsic size, keeping
    // the aspect ratio when only one side is known.
    final aspect = asset.width / asset.height;
    IrSizing w0, h0;
    if (fillW || fillH) {
      // Stretched across space of unknown size; a free side follows the
      // aspect ratio, estimated from the screen width.
      w0 = fillW ? const IrSizing.fill() : IrSizing.fixed(width ?? asset.width);
      h0 = fillH
          ? const IrSizing.fill()
          : IrSizing.fixed(height ?? (width ?? screenWidth) / aspect);
    } else if (width != null && height != null) {
      (w0, h0) = (IrSizing.fixed(width), IrSizing.fixed(height));
    } else if (width != null) {
      (w0, h0) = (IrSizing.fixed(width), IrSizing.fixed(width / aspect));
    } else if (height != null) {
      (w0, h0) = (IrSizing.fixed(height * aspect), IrSizing.fixed(height));
    } else {
      var iw = asset.width, ih = asset.height;
      if (c.box.boundedW && iw > screenWidth) {
        (iw, ih) = (screenWidth, screenWidth / aspect);
      }
      (w0, h0) = (IrSizing.fixed(iw), IrSizing.fixed(ih));
    }
    return IrFrame(
      name: name,
      role: 'image',
      origin: [w.type],
      direction: IrLayoutDirection.stack,
      width: w0,
      height: h0,
      image: IrImagePaint(asset.key, fit: _boxFit(w['fit'], asset)),
    );
  }

  /// Network, file and in-memory images: only a placeholder.
  (IrImageAsset?, String) _unembedded(ObjectValue w) {
    _warn(
      '${w.displayName} images are exported as placeholders; only assets '
      'are embedded',
      w,
      severity: IrSeverity.info,
    );
    final source = eval.string(w.arg(0));
    return (null, source ?? w.constructor ?? 'image');
  }

  /// `BoxFit` of an image; SVGs default to `contain` like `SvgPicture`,
  /// raster images to `scaleDown` like `paintImage`.
  IrBoxFit _boxFit(DartValue? fit, IrImageAsset asset) {
    final name = eval.enumName(fit);
    return IrBoxFit.values.where((f) => f.name == name).firstOrNull ??
        (asset.isSvg ? IrBoxFit.contain : IrBoxFit.scaleDown);
  }

  /// An `ImageProvider`: `AssetImage` / `ExactAssetImage` are embedded,
  /// anything else is reported. Returns the asset and a name for the layer.
  (IrImageAsset?, String) _imageProvider(DartValue? provider, DartValue at) {
    final v = eval.deref(provider);
    if (v is ObjectValue &&
        (v.type == 'AssetImage' || v.type == 'ExactAssetImage')) {
      return _assetImage(v.arg(0), eval.string(v['package']), at);
    }
    final label = v is ObjectValue ? eval.string(v.arg(0)) ?? v.type : 'image';
    _warn(
      '${v is ObjectValue ? v.type : 'Image'} images are exported as '
      'placeholders; only assets are embedded',
      at,
      severity: IrSeverity.info,
    );
    return (null, label);
  }

  (IrImageAsset?, String) _assetImage(
    DartValue? nameValue,
    String? package,
    DartValue at,
  ) {
    final name = eval.string(nameValue);
    if (name == null) {
      _warn('Image asset name is only known at runtime', at);
      return (null, 'image');
    }
    final lookup = assets?.resolve(name, package: package);
    final asset = lookup?.asset;
    if (asset == null) {
      _warn('Image not embedded: ${lookup?.problem ?? 'no project'}', at);
      return (null, name);
    }
    _images[asset.key] = asset;
    return (asset, name);
  }

  IrNode _button(ObjectValue w, _Ctx c) {
    final enabled = w['onPressed'] != null && !_isLiteral(w['onPressed'], null);
    final kind = w.type;
    final tonal = w.constructor?.startsWith('tonal') ?? false;
    final hasIcon = w.constructor?.toLowerCase().endsWith('icon') ?? false;

    IrColor? background;
    IrColor foreground;
    IrStroke? stroke;
    var elevation = 0.0;
    var padding = kind == 'TextButton'
        ? const IrInsets.symmetric(horizontal: 12, vertical: 8)
        : const IrInsets.symmetric(horizontal: 24);
    switch (kind) {
      case 'ElevatedButton':
        background = theme.color('surfaceContainerLow');
        foreground = theme.color('primary');
        elevation = 1;
      case 'FilledButton':
        background = theme.color(tonal ? 'secondaryContainer' : 'primary');
        foreground = theme.color(tonal ? 'onSecondaryContainer' : 'onPrimary');
      case 'OutlinedButton':
        foreground = theme.color('primary');
        stroke = IrStroke(color: theme.color('outline'));
      default:
        foreground = theme.color('primary');
    }
    if (hasIcon) {
      padding = kind == 'TextButton'
          ? const IrInsets(left: 12, right: 16, top: 8, bottom: 8)
          : const IrInsets(left: 16, right: 24);
    }
    if (!enabled) {
      final onSurface = theme.color('onSurface');
      if (background != null) background = onSurface.withAlpha(0.12);
      foreground = onSurface.withAlpha(0.38);
      if (stroke != null) stroke = IrStroke(color: onSurface.withAlpha(0.12));
      elevation = 0;
    }

    var corners = const IrCorners.all(20);
    double? fixedWidth, fixedHeight;
    var minWidth = 64.0, minHeight = 40.0;
    final style = eval.deref(w['style']);
    Map<String, DartValue>? widgetStyle;
    if (style is CallValue && style.method == 'styleFrom') {
      widgetStyle = style.named;
    }
    if (style is ObjectValue && style.type == 'ButtonStyle') {
      widgetStyle = style.named;
    }
    TextStyleSpec? labelStyle;
    String? tapTargetSize;
    // Theme style first, then the widget's own: per property, the widget wins.
    for (final overrides in [theme.buttonStyles[kind], widgetStyle].nonNulls) {
      tapTargetSize =
          eval.enumName(overrides['tapTargetSize']) ?? tapTargetSize;
      final (bgKey, fgKey) = enabled
          ? ('backgroundColor', 'foregroundColor')
          : ('disabledBackgroundColor', 'disabledForegroundColor');
      background = eval.color(overrides[bgKey]) ?? background;
      foreground = eval.color(overrides[fgKey]) ?? foreground;
      labelStyle =
          eval.textStyle(eval.unwrapStateProperty(overrides['textStyle'])) ??
          labelStyle;
      padding = eval.insets(overrides['padding']) ?? padding;
      elevation =
          eval.number(eval.unwrapStateProperty(overrides['elevation'])) ??
          elevation;
      final (shapeCorners, shapeStroke) = eval.shape(overrides['shape']);
      corners = shapeCorners ?? corners;
      stroke = eval.borderSide(overrides['side']) ?? shapeStroke ?? stroke;
      final min = eval.deref(
        eval.unwrapStateProperty(overrides['minimumSize']),
      );
      if (min is ObjectValue && min.type == 'Size') {
        minWidth = eval.number(min.arg(0)) ?? minWidth;
        minHeight = eval.number(min.arg(1)) ?? minHeight;
      }
      final fixed = eval.deref(
        eval.unwrapStateProperty(overrides['fixedSize']),
      );
      if (fixed is ObjectValue && fixed.type == 'Size') {
        fixedWidth = eval.number(fixed.arg(0));
        fixedHeight = eval.number(fixed.arg(1));
      }
    }

    // `Size(double.infinity, 52)`: as large as the constraints allow.
    final fullWidth = minWidth.isInfinite || (fixedWidth?.isInfinite ?? false);
    final fullHeight =
        minHeight.isInfinite || (fixedHeight?.isInfinite ?? false);

    final childCtx = c
        .withText(
          theme
              .textStyle('labelLarge')!
              .merge(labelStyle)
              .merge(TextStyleSpec(color: foreground)),
          iconColor: foreground,
        )
        .withBox(const _Box(boundedW: false, boundedH: false));
    final children = <IrNode>[
      if (hasIcon && w['icon'] != null) _widget(w['icon'], childCtx),
      if (hasIcon && w['label'] != null) _widget(w['label'], childCtx),
      if (!hasIcon && w['child'] != null) _widget(w['child'], childCtx),
    ];
    // A button whose content is a label (optionally with an icon) is an
    // instance of the Button component.
    final labelled =
        children.isNotEmpty &&
        children.last is IrText &&
        children.length == (hasIcon ? 2 : 1);
    final button = IrFrame(
      name: '${w.displayName}${enabled ? '' : ' (disabled)'}',
      instance: labelled
          ? IrInstanceRef('Button', {
              'Type': switch (kind) {
                'ElevatedButton' => 'Elevated',
                'FilledButton' => tonal ? 'Tonal' : 'Filled',
                'OutlinedButton' => 'Outlined',
                _ => 'Text',
              },
              'State': enabled ? 'Enabled' : 'Disabled',
              if (hasIcon) 'Icon': 'Leading',
            })
          : null,
      role: 'button',
      origin: [w.type],
      direction: IrLayoutDirection.horizontal,
      width: fixedWidth != null && fixedWidth.isFinite
          ? IrSizing.fixed(fixedWidth)
          : _hugOrFill(c.box.forceW || (c.box.boundedW && fullWidth)),
      height: fixedHeight != null && fixedHeight.isFinite
          ? IrSizing.fixed(fixedHeight)
          : _hugOrFill(c.box.forceH || (c.box.boundedH && fullHeight)),
      minWidth: minWidth.isFinite ? minWidth : 64,
      minHeight: minHeight.isFinite ? minHeight : 40,
      mainAlign: IrMainAlign.center,
      crossAlign: IrCrossAlign.center,
      gap: hasIcon ? 8 : 0,
      padding: padding,
      fill: background,
      stroke: stroke,
      corners: corners,
      shadows: theme.shadows(elevation),
      children: children,
    );
    return _tapTarget(button, padded: _padded(tapTargetSize));
  }

  /// Whether a control gets Flutter's 48 px tap target
  /// (`MaterialTapTargetSize.padded`, the default on phones): the widget's
  /// own setting, else the theme's.
  bool _padded(String? widgetSetting) => switch (widgetSetting) {
    'padded' => true,
    'shrinkWrap' => false,
    _ => theme.tapTargetPadded,
  };

  /// Wraps [control] in the transparent space Flutter lays it out in:
  /// buttons are drawn 40 px tall but take at least 48 px, so everything
  /// after them sits where it does in the app.
  IrNode _tapTarget(
    IrFrame control, {
    required bool padded,
    double minWidth = _kMinInteractiveDimension,
    double minHeight = _kMinInteractiveDimension,
  }) {
    // Tag the control itself: `_widget` only tags the node it returns, which
    // is now the (shadowless) target.
    control.shadowToken ??= theme.shadowToken(control.shadows);
    if (!padded) return control;
    final target = IrFrame(
      name: 'Tap target',
      role: 'tap-target',
      origin: const ['MaterialTapTargetSize.padded'],
      width: control.width.isFill
          ? const IrSizing.fill()
          : const IrSizing.hug(),
      height: control.height.isFill
          ? const IrSizing.fill()
          : const IrSizing.hug(),
      minWidth: minWidth,
      minHeight: minHeight,
      mainAlign: IrMainAlign.center,
      crossAlign: IrCrossAlign.center,
      position: control.position,
      children: [control],
    );
    control.position = null;
    return target;
  }

  IrNode _iconButton(ObjectValue w, _Ctx c) {
    final (background, foreground) = switch (w.constructor) {
      'filled' => (theme.color('primary'), theme.color('onPrimary')),
      'filledTonal' => (
        theme.color('secondaryContainer'),
        theme.color('onSecondaryContainer'),
      ),
      _ => (null, eval.color(w['color']) ?? theme.color('onSurfaceVariant')),
    };
    final childCtx = c
        .withText(null, iconColor: foreground)
        .withBox(const _Box());
    final style = eval.deref(w['style']);
    final styleArgs = switch (style) {
      CallValue(method: 'styleFrom', :final named) => named,
      ObjectValue(type: 'ButtonStyle', :final named) => named,
      _ => const <String, DartValue>{},
    };
    final button = IrFrame(
      name: w.displayName,
      role: 'button',
      origin: [w.type],
      width: const IrSizing.fixed(40),
      height: const IrSizing.fixed(40),
      mainAlign: IrMainAlign.center,
      crossAlign: IrCrossAlign.center,
      fill: background,
      stroke: w.constructor == 'outlined'
          ? IrStroke(color: theme.color('outline'))
          : null,
      corners: const IrCorners.all(20),
      children: [if (w['icon'] != null) _widget(w['icon'], childCtx)],
    );
    return _tapTarget(
      button,
      padded: _padded(eval.enumName(styleArgs['tapTargetSize'])),
    );
  }

  IrFrame _fab(ObjectValue w, _Ctx c) {
    final foreground =
        eval.color(w['foregroundColor']) ?? theme.color('onPrimaryContainer');
    final childCtx = c
        .withText(
          theme
              .textStyle('labelLarge')!
              .merge(TextStyleSpec(color: foreground)),
          iconColor: foreground,
        )
        .withBox(const _Box(boundedW: false, boundedH: false));
    final extended = w.constructor == 'extended';
    return IrFrame(
      name: w.displayName,
      role: 'button',
      origin: [w.type],
      direction: IrLayoutDirection.horizontal,
      width: extended ? const IrSizing.hug() : const IrSizing.fixed(56),
      height: const IrSizing.fixed(56),
      minWidth: extended ? 80 : null,
      padding: extended
          ? const IrInsets.symmetric(horizontal: 16)
          : IrInsets.zero,
      gap: extended ? 8 : 0,
      mainAlign: IrMainAlign.center,
      crossAlign: IrCrossAlign.center,
      fill: eval.color(w['backgroundColor']) ?? theme.color('primaryContainer'),
      corners: const IrCorners.all(16),
      shadows: theme.shadows(eval.number(w['elevation']) ?? 6),
      children: [
        if (w['icon'] != null) _widget(w['icon'], childCtx),
        if (w['label'] != null) _widget(w['label'], childCtx),
        if (w['child'] != null) _widget(w['child'], childCtx),
      ],
    );
  }

  /// An empty, unfocused M3 text field: label (or hint) in place, with the
  /// decoration's border. Defaults from `_InputDecoratorDefaultsM3`.
  IrFrame _textField(ObjectValue w, _Ctx c) {
    final deco = eval.deref(w['decoration']);
    final d = deco is ObjectValue && deco.type == 'InputDecoration'
        ? deco
        : ObjectValue(type: 'InputDecoration');
    final borderValue = eval.deref(d['border']);
    final border = switch (borderValue) {
      ObjectValue(type: 'OutlineInputBorder') => 'outline',
      RefValue(dotted: 'InputBorder.none') => 'none',
      _ => 'underline',
    };
    final filled = _isLiteral(d['filled'], true);
    final value = eval.string(w['initialValue']);
    final placeholder =
        eval.string(d['labelText']) ?? eval.string(d['hintText']);
    final textColor = value != null
        ? theme.color('onSurface')
        : theme.color('onSurfaceVariant');
    final iconCtx = c
        .withText(null, iconColor: theme.color('onSurfaceVariant'))
        .withBox(const _Box());
    final contentPadding =
        eval.insets(d['contentPadding']) ??
        IrInsets.symmetric(
          horizontal: border == 'underline' && !filled ? 0 : 12,
        );

    final row = IrFrame(
      name: 'Input',
      direction: IrLayoutDirection.horizontal,
      width: const IrSizing.fill(),
      crossAlign: IrCrossAlign.center,
      gap: 12,
      padding: contentPadding,
      minHeight: border == 'underline' ? 55 : 56,
      children: [
        if (d['prefixIcon'] != null) _widget(d['prefixIcon'], iconCtx),
        IrText(
          name: value ?? placeholder ?? 'Text field',
          origin: const ['InputDecoration'],
          text: value ?? placeholder ?? '',
          width: const IrSizing.fill(),
          style: _withTextToken(
            theme
                .textStyle('bodyLarge')!
                .merge(TextStyleSpec(color: textColor))
                .resolve(theme.fontFamily),
          ),
        ),
        if (d['suffixIcon'] != null) _widget(d['suffixIcon'], iconCtx),
      ],
    );
    final width = c.box.boundedW
        ? const IrSizing.fill()
        : const IrSizing.fixed(280);
    if (!c.box.boundedW) {
      _warn('${w.type} in unbounded width: shown 280 wide', w);
    }
    final fill = filled
        ? eval.color(d['fillColor']) ?? theme.color('surfaceContainerHighest')
        : null;

    if (border == 'underline') {
      return IrFrame(
        name: w.type,
        role: 'text-field',
        origin: [w.type],
        width: width,
        fill: fill,
        corners: filled
            ? const IrCorners(topLeft: 4, topRight: 4)
            : IrCorners.zero,
        children: [
          row,
          IrFrame(
            name: 'Underline',
            width: const IrSizing.fill(),
            height: const IrSizing.fixed(1),
            fill: theme.color('onSurfaceVariant'),
          ),
        ],
      );
    }
    final (corners, _) = eval.shape(borderValue);
    return row
      ..name = w.type
      ..role = 'text-field'
      ..origin = [w.type]
      ..width = width
      ..fill = fill
      ..stroke = border == 'outline'
          ? IrStroke(
              color:
                  eval
                      .borderSide(
                        eval.deref(
                          borderValue is ObjectValue
                              ? borderValue['borderSide']
                              : null,
                        ),
                      )
                      ?.color ??
                  theme.color('outline'),
            )
          : null
      ..corners = border == 'outline'
          ? (corners == null || corners.isZero
                ? const IrCorners.all(4)
                : corners)
          : IrCorners.zero;
  }

  /// `value:` as a known bool, else [fallback] with a note.
  bool _state(ObjectValue w, String arg, bool fallback) {
    final v = eval.deref(w[arg]);
    if (v is LiteralValue && v.value is bool) return v.value as bool;
    _warn(
      '${w.displayName}: `$arg` is runtime state; drawn '
      '${fallback ? 'on' : 'off'}',
      w,
      severity: IrSeverity.info,
    );
    return fallback;
  }

  /// M3 switch (`_SwitchDefaultsM3`): 52×32 track, 24/16 px thumb.
  IrNode _switch(ObjectValue w) {
    final on = _state(w, 'value', false);
    final thumb = on ? 24.0 : 16.0;
    final track = IrFrame(
      name: 'Track',
      role: 'switch',
      origin: [w.type],
      direction: IrLayoutDirection.horizontal,
      width: const IrSizing.fixed(52),
      height: const IrSizing.fixed(32),
      mainAlign: on ? IrMainAlign.end : IrMainAlign.start,
      crossAlign: IrCrossAlign.center,
      padding: IrInsets.symmetric(horizontal: (32 - thumb) / 2),
      fill:
          eval.color(w[on ? 'activeTrackColor' : 'inactiveTrackColor']) ??
          theme.color(on ? 'primary' : 'surfaceContainerHighest'),
      stroke: on ? null : IrStroke(color: theme.color('outline'), width: 2),
      corners: const IrCorners.all(16),
      children: [
        IrFrame(
          name: 'Thumb',
          width: IrSizing.fixed(thumb),
          height: IrSizing.fixed(thumb),
          fill:
              eval.color(w[on ? 'activeColor' : 'inactiveThumbColor']) ??
              theme.color(on ? 'onPrimary' : 'outline'),
          corners: IrCorners.all(thumb / 2),
        ),
      ],
    );
    // Flutter lays the 52×32 track out in a 60×48 box (60×40 when
    // shrink-wrapped): 4 px padding each side, plus the tap target.
    final padded = _padded(eval.enumName(w['materialTapTargetSize']));
    return IrFrame(
      name: w.displayName,
      origin: [w.type],
      width: const IrSizing.fixed(60),
      height: IrSizing.fixed(padded ? _kMinInteractiveDimension : 40),
      mainAlign: IrMainAlign.center,
      crossAlign: IrCrossAlign.center,
      children: [track],
    );
  }

  /// M3 checkbox: an 18 px box in a 40 px target.
  IrFrame _checkbox(ObjectValue w) {
    final checked = _state(w, 'value', false);
    return _selectionTarget(
      w,
      IrFrame(
        name: 'Box',
        width: const IrSizing.fixed(18),
        height: const IrSizing.fixed(18),
        fill: checked
            ? eval.color(w['activeColor']) ?? theme.color('primary')
            : null,
        stroke: checked
            ? null
            : IrStroke(color: theme.color('onSurfaceVariant'), width: 2),
        corners: const IrCorners.all(2),
      ),
    );
  }

  /// M3 radio: a 20 px ring (with a 10 px dot when selected) in a 40 px
  /// target. Selected when `value == groupValue` is statically known.
  IrFrame _radio(ObjectValue w) {
    final value = eval.deref(w['value']);
    final group = eval.deref(w['groupValue']);
    final selected =
        (value is LiteralValue &&
            group is LiteralValue &&
            value.value == group.value) ||
        (value is RefValue &&
            group is RefValue &&
            value.dotted == group.dotted);
    final color = selected
        ? eval.color(w['activeColor']) ?? theme.color('primary')
        : theme.color('onSurfaceVariant');
    return _selectionTarget(
      w,
      IrFrame(
        name: 'Ring',
        width: const IrSizing.fixed(20),
        height: const IrSizing.fixed(20),
        mainAlign: IrMainAlign.center,
        crossAlign: IrCrossAlign.center,
        stroke: IrStroke(color: color, width: 2),
        corners: const IrCorners.all(10),
        children: [
          if (selected)
            IrFrame(
              name: 'Dot',
              width: const IrSizing.fixed(10),
              height: const IrSizing.fixed(10),
              fill: color,
              corners: const IrCorners.all(5),
            ),
        ],
      ),
    );
  }

  double _selectionSize(ObjectValue w) =>
      _padded(eval.enumName(w['materialTapTargetSize']))
      ? _kMinInteractiveDimension
      : 40;

  /// Checkbox and Radio take 48×48 (40×40 when shrink-wrapped).
  IrFrame _selectionTarget(ObjectValue w, IrFrame mark) => IrFrame(
    name: w.displayName,
    role: w.type.toLowerCase(),
    origin: [w.type],
    width: IrSizing.fixed(_selectionSize(w)),
    height: IrSizing.fixed(_selectionSize(w)),
    mainAlign: IrMainAlign.center,
    crossAlign: IrCrossAlign.center,
    children: [mark],
  );

  /// Grids become rows of equal cells. Cell height comes from the delegate's
  /// aspect ratio and an estimated width (the screen's, minus padding),
  /// since Figma can't tie height to width.
  IrFrame _grid(ObjectValue w, _Ctx c) {
    final delegate = eval.deref(w['gridDelegate']);
    ObjectValue? d = delegate is ObjectValue ? delegate : null;
    if (w.constructor == 'count' || w.constructor == 'extent') d = w;
    DartValue? arg(String name) => d?[name];
    final padding = eval.insets(w['padding']) ?? IrInsets.zero;
    final mainSpacing = eval.number(arg('mainAxisSpacing')) ?? 0;
    final crossSpacing = eval.number(arg('crossAxisSpacing')) ?? 0;
    final aspect = eval.number(arg('childAspectRatio')) ?? 1;
    final available = screenWidth - padding.horizontal;
    final maxExtent = eval.number(arg('maxCrossAxisExtent'));
    final columns = max(
      1,
      eval.integer(arg('crossAxisCount')) ??
          (maxExtent == null
              ? 2
              : ((available + crossSpacing) / (maxExtent + crossSpacing))
                    .ceil()),
    );
    final cellWidth = (available - crossSpacing * (columns - 1)) / columns;
    final cellHeight = (cellWidth / aspect * 100).roundToDouble() / 100;

    // Items: a children list, or itemBuilder × itemCount.
    List<DartValue> items;
    if (w.constructor == 'builder') {
      final builder = eval.deref(w['itemBuilder']);
      final count = eval.integer(w['itemCount']);
      if (count == null) {
        _warn(
          'GridView.builder: item count is dynamic, rendered '
          '${listPreviewCount * columns} sample items',
          w,
          severity: IrSeverity.info,
        );
      }
      final n = (count ?? listPreviewCount * columns).clamp(0, 60);
      items = builder is FunctionValue && builder.returns != null
          ? List.filled(n, builder.returns!)
          : const [];
    } else {
      items = _items(w['children']) ?? const [];
    }
    _warn(
      '${w.displayName}: cell height estimated from the screen width',
      w,
      severity: IrSeverity.info,
    );

    final shrinkWrap = _isLiteral(w['shrinkWrap'], true);
    final grid = IrFrame(
      name: w.displayName,
      role: 'grid',
      origin: ['GridView'],
      width: _hugOrFill(c.box.boundedW),
      height: shrinkWrap || !c.box.boundedH
          ? const IrSizing.hug()
          : const IrSizing.fill(),
      padding: padding,
      gap: mainSpacing,
      clip: true,
    );
    final cellCtx = c.withBox(const _Box(forceW: true, forceH: true));
    for (var start = 0; start < items.length; start += columns) {
      final row = IrFrame(
        name: 'Row ${start ~/ columns + 1}',
        direction: IrLayoutDirection.horizontal,
        width: const IrSizing.fill(),
        gap: crossSpacing,
      );
      for (var i = start; i < start + columns; i++) {
        row.children.add(
          IrFrame(
            name: 'Cell ${i + 1}',
            width: const IrSizing.fill(),
            height: IrSizing.fixed(cellHeight),
            children: [if (i < items.length) _widget(items[i], cellCtx)],
          ),
        );
      }
      grid.children.add(row);
    }
    return grid;
  }

  /// A full ring: Figma frames can't draw the partial arc.
  IrFrame _circularProgress(ObjectValue w) {
    _warn(
      'Progress indicators are drawn at a fixed value',
      w,
      severity: IrSeverity.info,
    );
    return IrFrame(
      name: w.type,
      role: 'progress',
      origin: [w.type],
      width: const IrSizing.fixed(36),
      height: const IrSizing.fixed(36),
      stroke: IrStroke(
        color: eval.color(w['color']) ?? theme.color('primary'),
        width: eval.number(w['strokeWidth']) ?? 4,
      ),
      corners: const IrCorners.all(9999),
    );
  }

  /// Track with a 40% indicator (or `value` when given).
  IrFrame _linearProgress(ObjectValue w, _Ctx c) {
    _warn(
      'Progress indicators are drawn at a fixed value',
      w,
      severity: IrSeverity.info,
    );
    final value = eval.number(w['value'])?.clamp(0.0, 1.0) ?? 0.4;
    final height = eval.number(w['minHeight']) ?? 4;
    final trackWidth = c.box.boundedW ? null : 240.0;
    return IrFrame(
      name: w.type,
      role: 'progress',
      origin: [w.type],
      direction: IrLayoutDirection.horizontal,
      width: trackWidth == null
          ? const IrSizing.fill()
          : IrSizing.fixed(trackWidth),
      height: IrSizing.fixed(height),
      fill:
          eval.color(w['backgroundColor']) ?? theme.color('secondaryContainer'),
      clip: true,
      children: [
        IrFrame(
          name: 'Indicator',
          width: IrSizing.fixed((trackWidth ?? 240) * value),
          height: const IrSizing.fill(),
          fill: eval.color(w['color']) ?? theme.color('primary'),
        ),
      ],
    );
  }

  IrFrame _divider(ObjectValue w, _Ctx c) {
    final vertical = w.type == 'VerticalDivider';
    final extent = eval.number(w[vertical ? 'width' : 'height']) ?? 16;
    final thickness = eval.number(w['thickness']) ?? 1;
    final color = eval.color(w['color']) ?? theme.color('outlineVariant');
    final line = IrFrame(
      name: 'Line',
      width: vertical ? IrSizing.fixed(thickness) : const IrSizing.fill(),
      height: vertical ? const IrSizing.fill() : IrSizing.fixed(thickness),
      fill: color,
    );
    return IrFrame(
      name: w.type,
      origin: [w.type],
      direction: vertical
          ? IrLayoutDirection.horizontal
          : IrLayoutDirection.vertical,
      width: vertical ? IrSizing.fixed(extent) : const IrSizing.fill(),
      height: vertical ? const IrSizing.fill() : IrSizing.fixed(extent),
      mainAlign: IrMainAlign.center,
      padding: vertical
          ? IrInsets(
              top: eval.number(w['indent']) ?? 0,
              bottom: eval.number(w['endIndent']) ?? 0,
            )
          : IrInsets(
              left: eval.number(w['indent']) ?? 0,
              right: eval.number(w['endIndent']) ?? 0,
            ),
      children: [line],
    );
  }

  IrFrame _scrollView(ObjectValue w, _Ctx c) {
    final horizontal = eval.enumName(w['scrollDirection']) == 'horizontal';
    final frame = IrFrame(
      name: 'SingleChildScrollView',
      origin: ['SingleChildScrollView'],
      direction: horizontal
          ? IrLayoutDirection.horizontal
          : IrLayoutDirection.vertical,
      width: _hugOrFill(c.box.boundedW),
      height: _hugOrFill(c.box.boundedH),
      padding: eval.insets(w['padding']) ?? IrInsets.zero,
      clip: true,
    );
    final childBox = horizontal
        ? _Box(forceH: c.box.boundedH, boundedW: false)
        : _Box(forceW: c.box.boundedW, boundedH: false);
    if (w['child'] != null) {
      frame.children.add(_widget(w['child'], c.withBox(childBox)));
    }
    return frame;
  }

  IrFrame _listView(ObjectValue w, _Ctx c) {
    final horizontal = eval.enumName(w['scrollDirection']) == 'horizontal';
    final shrinkWrap = _isLiteral(w['shrinkWrap'], true);
    final frame = IrFrame(
      name: w.displayName,
      origin: ['ListView'],
      direction: horizontal
          ? IrLayoutDirection.horizontal
          : IrLayoutDirection.vertical,
      width: horizontal && shrinkWrap
          ? const IrSizing.hug()
          : _hugOrFill(c.box.boundedW),
      height: !horizontal && shrinkWrap
          ? const IrSizing.hug()
          : _hugOrFill(c.box.boundedH),
      padding: eval.insets(w['padding']) ?? IrInsets.zero,
      clip: true,
    );
    final itemCtx = c.withBox(
      horizontal
          ? _Box(forceH: c.box.boundedH, boundedW: false)
          : _Box(forceW: c.box.boundedW, boundedH: false),
    );

    if (w.constructor == null) {
      final items = _items(w['children']);
      if (items != null) {
        for (final i in items) {
          frame.children.add(_widget(i, itemCtx));
        }
      }
      return frame;
    }

    final literalCount = eval.integer(w['itemCount']);
    final count = literalCount == null
        ? listPreviewCount
        : literalCount.clamp(0, listPreviewCount * 3);
    if (literalCount == null) {
      _warn(
        '${w.displayName}: item count is dynamic, rendered $count sample items',
        w,
        severity: IrSeverity.info,
      );
    }
    final builder = eval.deref(w['itemBuilder']);
    final separator = eval.deref(w['separatorBuilder']);
    for (var i = 0; i < count; i++) {
      if (builder is FunctionValue && builder.returns != null) {
        frame.children.add(
          _widget(builder.returns, itemCtx)..name += ' #${i + 1}',
        );
      }
      if (i < count - 1 &&
          separator is FunctionValue &&
          separator.returns != null) {
        frame.children.add(_widget(separator.returns, itemCtx));
      }
    }
    return frame;
  }
}
