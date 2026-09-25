/// The Flutter2Figma intermediate representation.
///
/// Nothing in this file knows about Flutter or Figma. Producers (the Flutter
/// compiler) and consumers (the Figma renderer, and later HTML/React) meet here.
library;

const irFormat = 'flutter2figma/ir';
const irVersion = 1;

class IrDocument {
  IrDocument({
    required this.project,
    required this.screens,
    this.diagnostics = const [],
  });

  final String project;
  final List<IrScreen> screens;
  final List<IrDiagnostic> diagnostics;

  Map<String, Object?> toJson() => {
    'format': irFormat,
    'version': irVersion,
    'project': project,
    'screens': [for (final s in screens) s.toJson()],
    'diagnostics': [for (final d in diagnostics) d.toJson()],
  };

  factory IrDocument.fromJson(Map<String, Object?> json) {
    if (json['format'] != irFormat) {
      throw FormatException('Not a $irFormat document: ${json['format']}');
    }
    return IrDocument(
      project: json['project'] as String,
      screens: [
        for (final s in json['screens'] as List)
          IrScreen.fromJson(s as Map<String, Object?>),
      ],
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
  const IrColor(this.r, this.g, this.b, [this.a = 1]);

  factory IrColor.fromArgb32(int argb) => IrColor(
    ((argb >> 16) & 0xff) / 255,
    ((argb >> 8) & 0xff) / 255,
    (argb & 0xff) / 255,
    ((argb >> 24) & 0xff) / 255,
  );

  /// Parses `#RRGGBB` or `#RRGGBBAA`.
  factory IrColor.fromHex(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6 && h.length != 8) {
      throw FormatException('Bad color: $hex');
    }
    int c(int i) => int.parse(h.substring(i, i + 2), radix: 16);
    return IrColor(
      c(0) / 255,
      c(2) / 255,
      c(4) / 255,
      h.length == 8 ? c(6) / 255 : 1,
    );
  }

  static const black = IrColor(0, 0, 0);
  static const white = IrColor(1, 1, 1);
  static const transparent = IrColor(0, 0, 0, 0);

  final double r, g, b, a;

  IrColor withAlpha(double alpha) => IrColor(r, g, b, alpha);

  int toArgb32() {
    int c(double v) => (v * 255).round().clamp(0, 255);
    return (c(a) << 24) | (c(r) << 16) | (c(g) << 8) | c(b);
  }

  String toHex() {
    String c(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${c(r)}${c(g)}${c(b)}${a == 1 ? '' : c(a)}'.toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      other is IrColor && other.toHex() == toHex();

  @override
  int get hashCode => toHex().hashCode;

  @override
  String toString() => toHex();
}

class IrStroke {
  const IrStroke({required this.color, this.width = 1});

  final IrColor color;
  final double width;

  Map<String, Object?> toJson() => {'color': color.toHex(), 'width': width};

  static IrStroke? fromJson(Object? json) {
    if (json == null) return null;
    final m = json as Map<String, Object?>;
    return IrStroke(
      color: IrColor.fromHex(m['color'] as String),
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
    'color': color.toHex(),
    'x': x,
    'y': y,
    'blur': blur,
    'spread': spread,
  };

  static IrShadow fromJson(Object? json) {
    final m = json as Map<String, Object?>;
    return IrShadow(
      color: IrColor.fromHex(m['color'] as String),
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
  });

  String name;
  IrSizing width;
  IrSizing height;

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
    ..._props(),
  };

  Map<String, Object?> _props();

  static IrNode fromJson(Map<String, Object?> json) {
    final node = switch (json['type']) {
      'frame' => IrFrame._fromJson(json),
      'text' => IrText._fromJson(json),
      _ => throw FormatException('Unknown IR node type: ${json['type']}'),
    };
    node
      ..origin = [...(json['origin'] as List? ?? const []).cast<String>()]
      ..source = json['source'] as String?
      ..position = IrPosition.fromJson(json['position']);
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
    this.direction = IrLayoutDirection.vertical,
    this.gap = 0,
    this.padding = IrInsets.zero,
    this.mainAlign = IrMainAlign.start,
    this.crossAlign = IrCrossAlign.start,
    this.fill,
    this.corners = IrCorners.zero,
    this.stroke,
    this.shadows = const [],
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
    if (fill != null) 'fill': fill!.toHex(),
    if (!corners.isZero) 'corners': corners.toJson(),
    if (stroke != null) 'stroke': stroke!.toJson(),
    if (shadows.isNotEmpty) 'shadows': [for (final s in shadows) s.toJson()],
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
      fill: json['fill'] == null
          ? null
          : IrColor.fromHex(json['fill'] as String),
      corners: IrCorners.fromJson(json['corners']),
      stroke: IrStroke.fromJson(json['stroke']),
      shadows: [
        for (final s in (json['shadows'] as List? ?? const []))
          IrShadow.fromJson(s),
      ],
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
  });

  final String fontFamily;
  final double fontSize;
  final int fontWeight;
  final bool italic;
  final IrColor color;

  /// Absolute line height in logical pixels; null means font default.
  final double? lineHeight;
  final double letterSpacing;

  Map<String, Object?> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    if (italic) 'italic': true,
    'color': color.toHex(),
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
      color: IrColor.fromHex(m['color'] as String),
      lineHeight: _d(m['lineHeight']),
      letterSpacing: _d(m['letterSpacing']) ?? 0,
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

double? _d(Object? v) => (v as num?)?.toDouble();
