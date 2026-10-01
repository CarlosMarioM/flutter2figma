/// The Flutter2Figma intermediate representation.
///
/// Nothing in this file knows about Flutter or Figma. Producers (the Flutter
/// compiler) and consumers (the Figma renderer, and later HTML/React) meet here.
library;

import '../version.dart';

const irFormat = 'flutter2figma/ir';
const irVersion = 3;

class IrDocument {
  IrDocument({
    required this.project,
    required this.screens,
    this.designSystem,
    this.diagnostics = const [],
  });

  final String project;
  final List<IrScreen> screens;

  /// Tokens and components the screens reference.
  final IrDesignSystem? designSystem;
  final List<IrDiagnostic> diagnostics;

  Map<String, Object?> toJson() => {
    'format': irFormat,
    'version': irVersion,
    'generator': {'name': 'flutter2figma', 'version': packageVersion},
    'project': project,
    'screens': [for (final s in screens) s.toJson()],
    if (designSystem != null) 'designSystem': designSystem!.toJson(),
    'diagnostics': [for (final d in diagnostics) d.toJson()],
  };

  factory IrDocument.fromJson(Map<String, Object?> json) {
    if (json['format'] != irFormat) {
      throw FormatException('Not a $irFormat document: ${json['format']}');
    }
    if ((json['version'] as num? ?? 0) > irVersion) {
      throw FormatException(
        'IR version ${json['version']} is newer than $irVersion',
      );
    }
    return IrDocument(
      project: json['project'] as String,
      screens: [
        for (final s in json['screens'] as List)
          IrScreen.fromJson(s as Map<String, Object?>),
      ],
      designSystem: json['designSystem'] == null
          ? null
          : IrDesignSystem.fromJson(
              json['designSystem'] as Map<String, Object?>,
            ),
      diagnostics: [
        for (final d in (json['diagnostics'] as List? ?? const []))
          IrDiagnostic.fromJson(d as Map<String, Object?>),
      ],
    );
  }
}

class IrScreen {
  IrScreen({
    required this.name,
    required this.width,
    required this.height,
    required this.root,
    this.source,
  });

  final String name;
  final double width;
  final double height;
  final IrFrame root;
  final String? source;

  Map<String, Object?> toJson() => {
    'name': name,
    'width': width,
    'height': height,
    if (source != null) 'source': source,
    'root': root.toJson(),
  };

  factory IrScreen.fromJson(Map<String, Object?> json) => IrScreen(
    name: json['name'] as String,
    width: _d(json['width'])!,
    height: _d(json['height'])!,
    source: json['source'] as String?,
    root: IrNode.fromJson(json['root'] as Map<String, Object?>) as IrFrame,
  );
}

enum IrSeverity { info, warning, error }

class IrDiagnostic {
  const IrDiagnostic(this.severity, this.message, {this.source});

  final IrSeverity severity;
  final String message;
  final String? source;

  Map<String, Object?> toJson() => {
    'severity': severity.name,
    'message': message,
    if (source != null) 'source': source,
  };

  factory IrDiagnostic.fromJson(Map<String, Object?> json) => IrDiagnostic(
    IrSeverity.values.byName(json['severity'] as String),
    json['message'] as String,
    source: json['source'] as String?,
  );

  @override
  String toString() =>
      '${severity.name}: $message${source == null ? '' : ' ($source)'}';
}

// ---------------------------------------------------------------------------
// Sizing & layout
// ---------------------------------------------------------------------------

enum SizingMode { fixed, hug, fill }

/// How a node sizes itself along one axis.
///
/// [fill] means "take all the space the parent offers on this axis". Along a
/// parent's main axis that is flex-grow; along its cross axis it is stretch.
class IrSizing {
  const IrSizing.fixed(double this.value) : mode = SizingMode.fixed;
  const IrSizing.hug() : mode = SizingMode.hug, value = null;
  const IrSizing.fill() : mode = SizingMode.fill, value = null;

  final SizingMode mode;
  final double? value;

  bool get isFixed => mode == SizingMode.fixed;
  bool get isFill => mode == SizingMode.fill;
  bool get isHug => mode == SizingMode.hug;

  Object toJson() => isFixed ? value! : mode.name;

  static IrSizing fromJson(Object? json) => switch (json) {
    num v => IrSizing.fixed(v.toDouble()),
    'hug' => const IrSizing.hug(),
    'fill' => const IrSizing.fill(),
    _ => throw FormatException('Bad sizing: $json'),
  };

  @override
  bool operator ==(Object other) =>
      other is IrSizing && other.mode == mode && other.value == value;

  @override
  int get hashCode => Object.hash(mode, value);

  @override
  String toString() => toJson().toString();
}

/// `stack` children are positioned absolutely via [IrNode.position].
enum IrLayoutDirection { vertical, horizontal, stack }

enum IrMainAlign { start, center, end, spaceBetween }

enum IrCrossAlign { start, center, end, baseline }

class IrInsets {
  const IrInsets({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });
  const IrInsets.all(double v) : this(top: v, right: v, bottom: v, left: v);
  const IrInsets.symmetric({double horizontal = 0, double vertical = 0})
    : this(
        top: vertical,
        right: horizontal,
        bottom: vertical,
        left: horizontal,
      );

  static const zero = IrInsets();

  final double top, right, bottom, left;

  bool get isZero => top == 0 && right == 0 && bottom == 0 && left == 0;
  double get horizontal => left + right;
  double get vertical => top + bottom;

  IrInsets operator +(IrInsets o) => IrInsets(
    top: top + o.top,
    right: right + o.right,
    bottom: bottom + o.bottom,
    left: left + o.left,
  );

  Map<String, Object?> toJson() => {
    'top': top,
    'right': right,
    'bottom': bottom,
    'left': left,
  };

  static IrInsets fromJson(Object? json) {
    if (json == null) return zero;
    final m = json as Map<String, Object?>;
    return IrInsets(
      top: _d(m['top']) ?? 0,
      right: _d(m['right']) ?? 0,
      bottom: _d(m['bottom']) ?? 0,
      left: _d(m['left']) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IrInsets &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// Absolute placement inside a `stack` parent. Unset edges are unconstrained.
class IrPosition {
  const IrPosition({this.left, this.top, this.right, this.bottom});

  final double? left, top, right, bottom;

  Map<String, Object?> toJson() => {
    if (left != null) 'left': left,
    if (top != null) 'top': top,
    if (right != null) 'right': right,
    if (bottom != null) 'bottom': bottom,
  };

  static IrPosition? fromJson(Object? json) {
    if (json == null) return null;
    final m = json as Map<String, Object?>;
    return IrPosition(
      left: _d(m['left']),
      top: _d(m['top']),
      right: _d(m['right']),
      bottom: _d(m['bottom']),
    );
  }
}

// ---------------------------------------------------------------------------
// Paint
// ---------------------------------------------------------------------------

/// sRGB color with components in 0..1.
class IrColor {
  const IrColor(this.r, this.g, this.b, [this.a = 1]) : token = null;

  const IrColor._(this.r, this.g, this.b, this.a, this.token);

  factory IrColor.fromArgb32(int argb, {String? token}) => IrColor._(
    ((argb >> 16) & 0xff) / 255,
    ((argb >> 8) & 0xff) / 255,
    (argb & 0xff) / 255,
    ((argb >> 24) & 0xff) / 255,
    token,
  );

  /// Parses `#RRGGBB` or `#RRGGBBAA`.
  factory IrColor.fromHex(String hex, {String? token}) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6 && h.length != 8) {
      throw FormatException('Bad color: $hex');
    }
    int c(int i) => int.parse(h.substring(i, i + 2), radix: 16);
    return IrColor._(
      c(0) / 255,
      c(2) / 255,
      c(4) / 255,
      h.length == 8 ? c(6) / 255 : 1,
      token,
    );
  }

  /// A hex string, or `{"value": hex, "token": name}` for token colors.
  static IrColor fromJson(Object? json) => switch (json) {
    String hex => IrColor.fromHex(hex),
    {'value': String hex, 'token': String token} => IrColor.fromHex(
      hex,
      token: token,
    ),
    _ => throw FormatException('Bad color: $json'),
  };

  static const black = IrColor(0, 0, 0);
  static const white = IrColor(1, 1, 1);
  static const transparent = IrColor(0, 0, 0, 0);

  final double r, g, b, a;

  /// The design token this color was taken from, e.g. `ColorScheme/primary`.
  /// Kept through [withAlpha]: renderers bind the token and apply the alpha
  /// as paint opacity.
  final String? token;

  IrColor withAlpha(double alpha) => IrColor._(r, g, b, alpha, token);

  IrColor withToken(String? token) => IrColor._(r, g, b, a, token);

  int toArgb32() {
    int c(double v) => (v * 255).round().clamp(0, 255);
    return (c(a) << 24) | (c(r) << 16) | (c(g) << 8) | c(b);
  }

  String toHex() {
    String c(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${c(r)}${c(g)}${c(b)}${a == 1 ? '' : c(a)}'.toUpperCase();
  }

  Object toJson() =>
      token == null ? toHex() : {'value': toHex(), 'token': token};

  @override
  bool operator ==(Object other) =>
      other is IrColor && other.toHex() == toHex() && other.token == token;

  @override
  int get hashCode => Object.hash(toHex(), token);

  @override
  String toString() => token == null ? toHex() : '${toHex()} ($token)';
}

class IrStroke {
  const IrStroke({required this.color, this.width = 1});

  final IrColor color;
  final double width;

  Map<String, Object?> toJson() => {'color': color.toJson(), 'width': width};

  static IrStroke? fromJson(Object? json) {
    if (json == null) return null;
    final m = json as Map<String, Object?>;
    return IrStroke(
      color: IrColor.fromJson(m['color']),
      width: _d(m['width']) ?? 1,
    );
  }
}

class IrShadow {
  const IrShadow({
    required this.color,
    this.x = 0,
    this.y = 0,
    this.blur = 0,
    this.spread = 0,
  });

  final IrColor color;
  final double x, y, blur, spread;

  Map<String, Object?> toJson() => {
    'color': color.toJson(),
    'x': x,
    'y': y,
    'blur': blur,
    'spread': spread,
  };

  static IrShadow fromJson(Object? json) {
    final m = json as Map<String, Object?>;
    return IrShadow(
      color: IrColor.fromJson(m['color']),
      x: _d(m['x']) ?? 0,
      y: _d(m['y']) ?? 0,
      blur: _d(m['blur']) ?? 0,
      spread: _d(m['spread']) ?? 0,
    );
  }
}

class IrCorners {
  const IrCorners({
    this.topLeft = 0,
    this.topRight = 0,
    this.bottomRight = 0,
    this.bottomLeft = 0,
  });
  const IrCorners.all(double r)
    : this(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r);

  static const zero = IrCorners();

  final double topLeft, topRight, bottomRight, bottomLeft;

  bool get isZero =>
      topLeft == 0 && topRight == 0 && bottomRight == 0 && bottomLeft == 0;
  bool get isUniform =>
      topLeft == topRight &&
      topRight == bottomRight &&
      bottomRight == bottomLeft;

  Object toJson() => isUniform
      ? topLeft
      : {
          'topLeft': topLeft,
          'topRight': topRight,
          'bottomRight': bottomRight,
          'bottomLeft': bottomLeft,
        };

  static IrCorners fromJson(Object? json) => switch (json) {
    null => zero,
    num r => IrCorners.all(r.toDouble()),
    Map<String, Object?> m => IrCorners(
      topLeft: _d(m['topLeft']) ?? 0,
      topRight: _d(m['topRight']) ?? 0,
      bottomRight: _d(m['bottomRight']) ?? 0,
      bottomLeft: _d(m['bottomLeft']) ?? 0,
    ),
    _ => throw FormatException('Bad corners: $json'),
  };
}

// ---------------------------------------------------------------------------
// Nodes
// ---------------------------------------------------------------------------

sealed class IrNode {
  IrNode({
    required this.name,
    required this.width,
    required this.height,
    this.origin = const [],
    this.source,
    this.position,
    this.instance,
  });

  String name;
  IrSizing width;
  IrSizing height;

  /// Set when this subtree is an occurrence of a component. The subtree is
  /// still complete, so renderers without components can ignore it.
  IrInstanceRef? instance;

  /// The Flutter widgets (outermost first) that were folded into this node.
  List<String> origin;

  /// `path:line` of the widget that produced this node.
  String? source;

  /// Only meaningful when the parent is a `stack` frame.
  IrPosition? position;

  String get type;

  Map<String, Object?> toJson() => {
    'type': type,
    'name': name,
    'width': width.toJson(),
    'height': height.toJson(),
    if (origin.isNotEmpty) 'origin': origin,
    if (source != null) 'source': source,
    if (position != null) 'position': position!.toJson(),
    if (instance != null) 'instance': instance!.toJson(),
    ..._props(),
  };

  Map<String, Object?> _props();

  static IrNode fromJson(Map<String, Object?> json) {
    final node = switch (json['type']) {
      'frame' => IrFrame._fromJson(json),
      'text' => IrText._fromJson(json),
      'vector' => IrVector._fromJson(json),
      _ => throw FormatException('Unknown IR node type: ${json['type']}'),
    };
    node
      ..origin = [...(json['origin'] as List? ?? const []).cast<String>()]
      ..source = json['source'] as String?
      ..position = IrPosition.fromJson(json['position'])
      ..instance = IrInstanceRef.fromJson(json['instance']);
    return node;
  }
}

class IrFrame extends IrNode {
  IrFrame({
    required super.name,
    super.width = const IrSizing.hug(),
    super.height = const IrSizing.hug(),
    super.origin,
    super.source,
    super.position,
    super.instance,
    this.direction = IrLayoutDirection.vertical,
    this.gap = 0,
    this.padding = IrInsets.zero,
    this.mainAlign = IrMainAlign.start,
    this.crossAlign = IrCrossAlign.start,
    this.fill,
    this.corners = IrCorners.zero,
    this.stroke,
    this.shadows = const [],
    this.shadowToken,
    this.clip = false,
    this.minWidth,
    this.minHeight,
    this.role,
    List<IrNode>? children,
  }) : children = children ?? [];

  IrLayoutDirection direction;
  double gap;
  IrInsets padding;
  IrMainAlign mainAlign;
  IrCrossAlign crossAlign;
  IrColor? fill;
  IrCorners corners;
  IrStroke? stroke;
  List<IrShadow> shadows;

  /// Effect style [shadows] came from, e.g. `Elevation/level1`.
  String? shadowToken;
  bool clip;
  double? minWidth;
  double? minHeight;

  /// Semantic hint for renderers: `screen`, `app-bar`, `button`, `card`, ...
  String? role;
  List<IrNode> children;

  /// True when the frame paints nothing itself and is purely structural.
  bool get isBare => fill == null && stroke == null && shadows.isEmpty && !clip;

  @override
  String get type => 'frame';

  @override
  Map<String, Object?> _props() => {
    if (role != null) 'role': role,
    'layout': {
      'direction': direction.name,
      if (gap != 0) 'gap': gap,
      'mainAlign': mainAlign.name,
      'crossAlign': crossAlign.name,
    },
    if (!padding.isZero) 'padding': padding.toJson(),
    if (minWidth != null) 'minWidth': minWidth,
    if (minHeight != null) 'minHeight': minHeight,
    if (fill != null) 'fill': fill!.toJson(),
    if (!corners.isZero) 'corners': corners.toJson(),
    if (stroke != null) 'stroke': stroke!.toJson(),
    if (shadows.isNotEmpty) 'shadows': [for (final s in shadows) s.toJson()],
    if (shadowToken != null) 'shadowToken': shadowToken,
    if (clip) 'clip': true,
    'children': [for (final c in children) c.toJson()],
  };

  static IrFrame _fromJson(Map<String, Object?> json) {
    final layout = json['layout'] as Map<String, Object?>? ?? const {};
    return IrFrame(
      name: json['name'] as String,
      width: IrSizing.fromJson(json['width']),
      height: IrSizing.fromJson(json['height']),
      role: json['role'] as String?,
      direction: IrLayoutDirection.values.byName(
        layout['direction'] as String? ?? 'vertical',
      ),
      gap: _d(layout['gap']) ?? 0,
      mainAlign: IrMainAlign.values.byName(
        layout['mainAlign'] as String? ?? 'start',
      ),
      crossAlign: IrCrossAlign.values.byName(
        layout['crossAlign'] as String? ?? 'start',
      ),
      padding: IrInsets.fromJson(json['padding']),
      minWidth: _d(json['minWidth']),
      minHeight: _d(json['minHeight']),
      fill: json['fill'] == null ? null : IrColor.fromJson(json['fill']),
      corners: IrCorners.fromJson(json['corners']),
      stroke: IrStroke.fromJson(json['stroke']),
      shadows: [
        for (final s in (json['shadows'] as List? ?? const []))
          IrShadow.fromJson(s),
      ],
      shadowToken: json['shadowToken'] as String?,
      clip: json['clip'] as bool? ?? false,
      children: [
        for (final c in (json['children'] as List? ?? const []))
          IrNode.fromJson(c as Map<String, Object?>),
      ],
    );
  }
}

enum IrTextAlign { left, center, right, justify }

class IrTextStyle {
  const IrTextStyle({
    required this.fontFamily,
    required this.fontSize,
    required this.color,
    this.fontWeight = 400,
    this.italic = false,
    this.lineHeight,
    this.letterSpacing = 0,
    this.token,
  });

  final String fontFamily;
  final double fontSize;
  final int fontWeight;
  final bool italic;
  final IrColor color;

  /// Absolute line height in logical pixels; null means font default.
  final double? lineHeight;
  final double letterSpacing;

  /// Text style token whose typography this matches exactly, e.g.
  /// `TextTheme/bodyMedium`. Color is not part of typography.
  final String? token;

  IrTextStyle withToken(String? token) => IrTextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    italic: italic,
    color: color,
    lineHeight: lineHeight,
    letterSpacing: letterSpacing,
    token: token,
  );

  /// Same font, size, weight, slant, line height and letter spacing.
  bool sameTypography(IrTextStyle o) =>
      fontFamily == o.fontFamily &&
      fontSize == o.fontSize &&
      fontWeight == o.fontWeight &&
      italic == o.italic &&
      lineHeight == o.lineHeight &&
      letterSpacing == o.letterSpacing;

  Map<String, Object?> toJson() => {
    if (token != null) 'token': token,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    if (italic) 'italic': true,
    'color': color.toJson(),
    if (lineHeight != null) 'lineHeight': lineHeight,
    if (letterSpacing != 0) 'letterSpacing': letterSpacing,
  };

  static IrTextStyle fromJson(Object? json) {
    final m = json as Map<String, Object?>;
    return IrTextStyle(
      fontFamily: m['fontFamily'] as String,
      fontSize: _d(m['fontSize'])!,
      fontWeight: (m['fontWeight'] as num?)?.toInt() ?? 400,
      italic: m['italic'] as bool? ?? false,
      color: IrColor.fromJson(m['color']),
      lineHeight: _d(m['lineHeight']),
      letterSpacing: _d(m['letterSpacing']) ?? 0,
      token: m['token'] as String?,
    );
  }
}

class IrText extends IrNode {
  IrText({
    required super.name,
    required this.text,
    required this.style,
    super.width = const IrSizing.hug(),
    super.height = const IrSizing.hug(),
    super.origin,
    super.source,
    super.position,
    super.instance,
    this.align = IrTextAlign.left,
    this.maxLines,
  });

  String text;
  IrTextStyle style;
  IrTextAlign align;
  int? maxLines;

  @override
  String get type => 'text';

  @override
  Map<String, Object?> _props() => {
    'text': text,
    'style': style.toJson(),
    if (align != IrTextAlign.left) 'align': align.name,
    if (maxLines != null) 'maxLines': maxLines,
  };

  static IrText _fromJson(Map<String, Object?> json) => IrText(
    name: json['name'] as String,
    text: json['text'] as String,
    style: IrTextStyle.fromJson(json['style']),
    width: IrSizing.fromJson(json['width']),
    height: IrSizing.fromJson(json['height']),
    align: IrTextAlign.values.byName(json['align'] as String? ?? 'left'),
    maxLines: (json['maxLines'] as num?)?.toInt(),
  );
}

/// A filled outline, such as an icon glyph.
class IrVector extends IrNode {
  IrVector({
    required super.name,
    required this.path,
    required this.fill,
    required super.width,
    required super.height,
    super.origin,
    super.source,
    super.position,
  });

  /// SVG path data (`M`, `L`, `Q`, `C`, `Z`) in this node's coordinates,
  /// filled with the nonzero rule.
  String path;
  IrColor fill;

  @override
  String get type => 'vector';

  @override
  Map<String, Object?> _props() => {'path': path, 'fill': fill.toJson()};

  static IrVector _fromJson(Map<String, Object?> json) => IrVector(
    name: json['name'] as String,
    path: json['path'] as String,
    fill: IrColor.fromJson(json['fill']),
    width: IrSizing.fromJson(json['width']),
    height: IrSizing.fromJson(json['height']),
  );
}

// ---------------------------------------------------------------------------
// Design system
// ---------------------------------------------------------------------------

/// Marks a node as an occurrence of [component], in the variant selected by
/// [props] (empty for components without variants).
class IrInstanceRef {
  IrInstanceRef(this.component, [Map<String, String>? props])
    : props = props ?? {};

  final String component;
  final Map<String, String> props;

  /// Figma-style variant name: `Type=Filled, State=Enabled`.
  String get variantName =>
      [for (final e in props.entries) '${e.key}=${e.value}'].join(', ');

  /// Identifies the variant across the document.
  String get key => props.isEmpty ? component : '$component[$variantName]';

  Map<String, Object?> toJson() => {
    'component': component,
    if (props.isNotEmpty) 'props': props,
  };

  static IrInstanceRef? fromJson(Object? json) {
    if (json == null) return null;
    final m = json as Map<String, Object?>;
    return IrInstanceRef(
      m['component'] as String,
      (m['props'] as Map?)?.cast<String, String>(),
    );
  }
}

class IrDesignSystem {
  IrDesignSystem({
    required this.modes,
    required this.activeMode,
    this.colors = const [],
    this.textStyles = const [],
    this.shadows = const [],
    this.components = const [],
  });

  /// Theme modes colors are defined for, e.g. `[Light, Dark]`.
  final List<String> modes;

  /// The mode the screens were exported in.
  final String activeMode;

  final List<IrColorToken> colors;
  final List<IrTextStyleToken> textStyles;
  final List<IrShadowToken> shadows;
  final List<IrComponent> components;

  Map<String, Object?> toJson() => {
    'modes': modes,
    'activeMode': activeMode,
    'colors': [for (final c in colors) c.toJson()],
    'textStyles': [for (final t in textStyles) t.toJson()],
    'shadows': [for (final s in shadows) s.toJson()],
    'components': [for (final c in components) c.toJson()],
  };

  factory IrDesignSystem.fromJson(Map<String, Object?> json) => IrDesignSystem(
    modes: (json['modes'] as List).cast<String>(),
    activeMode: json['activeMode'] as String,
    colors: [
      for (final c in json['colors'] as List? ?? const [])
        IrColorToken.fromJson(c as Map<String, Object?>),
    ],
    textStyles: [
      for (final t in json['textStyles'] as List? ?? const [])
        IrTextStyleToken.fromJson(t as Map<String, Object?>),
    ],
    shadows: [
      for (final s in json['shadows'] as List? ?? const [])
        IrShadowToken.fromJson(s as Map<String, Object?>),
    ],
    components: [
      for (final c in json['components'] as List? ?? const [])
        IrComponent.fromJson(c as Map<String, Object?>),
    ],
  );
}

/// A color variable with one value per mode.
class IrColorToken {
  IrColorToken(this.name, this.values);

  final String name;
  final Map<String, IrColor> values;

  Map<String, Object?> toJson() => {
    'name': name,
    'values': {for (final e in values.entries) e.key: e.value.toHex()},
  };

  factory IrColorToken.fromJson(Map<String, Object?> json) =>
      IrColorToken(json['name'] as String, {
        for (final e in (json['values'] as Map).entries)
          e.key as String: IrColor.fromHex(e.value as String),
      });
}

/// A named text style. Only typography: text color is a separate token.
class IrTextStyleToken {
  IrTextStyleToken(this.name, this.style);

  final String name;

  /// [IrTextStyle.color] is ignored.
  final IrTextStyle style;

  Map<String, Object?> toJson() => {
    'name': name,
    'fontFamily': style.fontFamily,
    'fontSize': style.fontSize,
    'fontWeight': style.fontWeight,
    if (style.italic) 'italic': true,
    if (style.lineHeight != null) 'lineHeight': style.lineHeight,
    if (style.letterSpacing != 0) 'letterSpacing': style.letterSpacing,
  };

  factory IrTextStyleToken.fromJson(Map<String, Object?> json) =>
      IrTextStyleToken(
        json['name'] as String,
        IrTextStyle.fromJson({...json, 'color': '#000000'}),
      );
}

class IrShadowToken {
  IrShadowToken(this.name, this.shadows);

  final String name;
  final List<IrShadow> shadows;

  Map<String, Object?> toJson() => {
    'name': name,
    'shadows': [for (final s in shadows) s.toJson()],
  };

  factory IrShadowToken.fromJson(Map<String, Object?> json) => IrShadowToken(
    json['name'] as String,
    [for (final s in json['shadows'] as List) IrShadow.fromJson(s)],
  );
}

/// A reusable UI element. Its variants are defined by their first
/// occurrence in the screens (see [IrNode.instance]).
class IrComponent {
  IrComponent({required this.name, required this.variants, this.source});

  final String name;
  final List<IrComponentVariant> variants;

  /// Where the widget is declared, for project widgets.
  final String? source;

  Map<String, Object?> toJson() => {
    'name': name,
    if (source != null) 'source': source,
    'variants': [for (final v in variants) v.toJson()],
  };

  factory IrComponent.fromJson(Map<String, Object?> json) => IrComponent(
    name: json['name'] as String,
    source: json['source'] as String?,
    variants: [
      for (final v in json['variants'] as List)
        IrComponentVariant.fromJson(v as Map<String, Object?>),
    ],
  );
}

class IrComponentVariant {
  IrComponentVariant(this.props, {this.uses = 1});

  final Map<String, String> props;

  /// How many occurrences the screens contain.
  final int uses;

  Map<String, Object?> toJson() => {'props': props, 'uses': uses};

  factory IrComponentVariant.fromJson(Map<String, Object?> json) =>
      IrComponentVariant(
        (json['props'] as Map).cast<String, String>(),
        uses: (json['uses'] as num?)?.toInt() ?? 1,
      );
}

double? _d(Object? v) => (v as num?)?.toDouble();
