import 'package:flutter2figma_analyzer/flutter2figma_analyzer.dart';
import 'package:flutter2figma_ir/flutter2figma_ir.dart';

import 'component_extractor.dart';
import 'evaluator.dart';
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

class _Ctx {
  const _Ctx({required this.box, required this.text, required this.iconColor});

  final _Box box;

  /// Inherited `DefaultTextStyle`.
  final TextStyleSpec text;

  /// Inherited `IconTheme` color.
  final IrColor iconColor;

  _Ctx withBox(_Box box) => _Ctx(box: box, text: text, iconColor: iconColor);

  _Ctx withText(TextStyleSpec? style, {IrColor? iconColor}) => _Ctx(
    box: box,
    text: text.merge(style),
    iconColor: iconColor ?? this.iconColor,
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
  'AnimatedContainer',
  'AnimatedOpacity',
  'AnimatedSwitcher',
  'AnimatedSize',
  'AnimatedPadding',
  'Flexible',
  'Expanded',
};

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
  }) : eval = ValueEvaluator(theme);

  /// Emit an [IrDesignSystem]: color variables (per theme mode), text and
  /// effect styles, and components.
  final bool designSystem;

  /// A project widget becomes a component once used this many times.
  final int minComponentUses;

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
      root: simplify(root) as IrFrame,
    );
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
      case ConditionalValue(:final condition, :final then):
        _warn(
          'Conditional UI `$condition`: exported the `true` branch only',
          d,
          severity: IrSeverity.info,
        );
        return _asWidget(then);
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
    final node = w.isFlutter ? _flutterWidget(w, c) : _projectWidget(w, c);
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
      case 'Padding':
        return _padding(w, c);
      case 'Center' || 'Align':
        return _align(w, c);
      case 'SizedBox' ||
          'SizedBox.expand' ||
          'SizedBox.shrink' ||
          'SizedBox.square' ||
          'SizedBox.fromSize':
        return _sizedBox(w, c);
      case 'Container':
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
        return _spacer(w, c, IrLayoutDirection.vertical);
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
          'Image.memory':
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

    if (_passThrough.contains(w.type) && w['child'] != null) {
      if (w.type == 'Expanded' || w.type == 'Flexible') {
        _warn('${w.type} outside of a Row/Column', w);
      }
      final node = _widget(w['child'], c);
      node.origin = [w.type, ...node.origin];
      return node;
    }

    // Unknown widget: keep the subtree visible and flag it.
    _warn('Unsupported widget `${w.displayName}`', w);
    final child = w['child'];
    if (child != null) {
      final node = _widget(child, c);
      node.origin = [w.type, ...node.origin];
      return node;
    }
    final children = eval.deref(w['children']);
    if (children is ListValue) {
      return IrFrame(
        name: w.displayName,
        origin: [w.type],
        children: [
          for (final i in children.items) _widget(i, c.withBox(c.box.loose)),
        ],
      );
    }
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
    final actions = eval.deref(w['actions']);
    final hasActions = actions is ListValue && actions.items.isNotEmpty;
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
          for (final a in actions.items)
            _widget(a, titleCtx.withBox(const _Box())),
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
      if (d['image'] != null) {
        _warn('Decoration images are not exported yet', d['image']);
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
    final items = eval.deref(w['children']);
    if (items is ListValue) {
      for (final item in items.items) {
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
  ) {
    final vertical = direction == IrLayoutDirection.vertical;
    final w = _asWidget(item);
    if (w != null && w.isFlutter && w.type == 'Spacer') {
      return _spacer(w, c, direction);
    }
    if (w != null &&
        w.isFlutter &&
        (w.type == 'Expanded' || w.type == 'Flexible')) {
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
    return _widget(item, c);
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
    final items = eval.deref(w['children']);
    if (items is ListValue) {
      for (final item in items.items) {
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
          node.position = IrPosition(
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
    final name = iconRef is RefValue ? iconRef.last : 'icon';
    final color = eval.color(w['color']) ?? c.iconColor;
    _warn('Icons are exported as placeholders', w, severity: IrSeverity.info);
    return IrFrame(
      name: 'Icon/$name',
      role: 'icon',
      origin: ['Icon'],
      width: IrSizing.fixed(size),
      height: IrSizing.fixed(size),
      fill: color.withAlpha(color.a * 0.24),
      corners: IrCorners.all(size / 6),
    );
  }

  IrFrame _image(ObjectValue w, _Ctx c) {
    final width = eval.number(w['width']);
    final height = eval.number(w['height']);
    final src = eval.string(w.arg(0)) ?? 'image';
    _warn('Images are exported as placeholders', w, severity: IrSeverity.info);
    return IrFrame(
      name: 'Image/$src',
      role: 'image',
      origin: [w.type],
      width:
          _axis(
            width,
            forced: c.box.forceW,
            bounded: c.box.boundedW,
            expands: false,
          ).isHug
          ? const IrSizing.fixed(120)
          : _axis(
              width,
              forced: c.box.forceW,
              bounded: c.box.boundedW,
              expands: false,
            ),
      height: height == null
          ? const IrSizing.fixed(120)
          : IrSizing.fixed(height),
      fill: theme.color('surfaceContainerHighest'),
    );
  }

  IrFrame _button(ObjectValue w, _Ctx c) {
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
    // Theme style first, then the widget's own: per property, the widget wins.
    for (final overrides in [theme.buttonStyles[kind], widgetStyle].nonNulls) {
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
    return IrFrame(
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
      width: fixedWidth != null
          ? IrSizing.fixed(fixedWidth)
          : _hugOrFill(c.box.forceW),
      height: fixedHeight != null
          ? IrSizing.fixed(fixedHeight)
          : _hugOrFill(c.box.forceH),
      minWidth: minWidth,
      minHeight: minHeight,
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
  }

  IrFrame _iconButton(ObjectValue w, _Ctx c) {
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
    return IrFrame(
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
      final items = eval.deref(w['children']);
      if (items is ListValue) {
        for (final i in items.items) {
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
