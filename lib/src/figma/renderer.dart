import 'dart:convert';
import 'dart:math';

import 'package:flutter2figma/ir.dart';

import '../version.dart';

const designFormat = 'flutter2figma/design';
const designVersion = 4;

/// The first Figma plugin release that reads [designVersion]. Bump both
/// together (see doc/releasing.md): the export tells people which plugin
/// they need.
const minPluginVersion = '0.3.0';

/// Renders IR into `design.json`: a tree of nodes whose properties use Figma
/// Plugin API names and enums, so the plugin can apply them almost verbatim.
///
/// This layer knows nothing about Flutter.
class FigmaRenderer {
  FigmaRenderer({this.screenSpacing = 120});

  /// Horizontal distance between screens on the canvas.
  final double screenSpacing;

  final _fonts = <String, Map<String, String>>{};
  final _diagnostics = <IrDiagnostic>[];
  IrDocument? _doc;

  Map<String, Object?> render(IrDocument doc) {
    _doc = doc;
    _rendered.clear();
    _fonts.clear();
    _diagnostics.clear();
    var x = 0.0;
    final screens = <Map<String, Object?>>[];
    for (final screen in doc.screens) {
      final node = _node(screen.root, parent: null);
      node['x'] = x;
      node['y'] = 0;
      if (screen.source != null) {
        (node['pluginData'] as Map<String, Object?>)['source'] = screen.source;
      }
      screens.add(node);
      x += screen.width + screenSpacing;
    }
    final system = doc.designSystem;
    final designSystem = system == null ? null : _designSystem(doc, system);
    return {
      'format': designFormat,
      'version': designVersion,
      'generator': {'name': 'flutter2figma', 'version': packageVersion},
      'name': doc.project,
      'fonts': _fonts.values.toList(),
      'designSystem': ?designSystem,
      if (doc.images.isNotEmpty)
        'images': {
          for (final MapEntry(:key, :value) in doc.images.entries)
            key: {
              'format': value.format,
              'width': value.width,
              'height': value.height,
              // SVG markup as text (for createNodeFromSvg); raster as base64.
              'data': value.isSvg
                  ? utf8.decode(value.data, allowMalformed: true)
                  : base64Encode(value.data),
            },
        },
      'screens': screens,
      'diagnostics': [
        for (final d in [...doc.diagnostics, ..._diagnostics]) d.toJson(),
      ],
    };
  }

  /// Sizing as rendered, which can differ from the IR after a downgrade:
  /// children decide FILL against what their parent really became.
  final _rendered = <IrNode, (String, String)>{};

  Map<String, Object?> _node(IrNode node, {required IrFrame? parent}) {
    // Sizing first, so children see this node's rendered sizing.
    final horizontal = _sizing(node.width, node, parent, horizontal: true);
    final vertical = _sizing(node.height, node, parent, horizontal: false);
    _rendered[node] = (horizontal, vertical);
    final json = switch (node) {
      IrFrame() => _frame(node),
      IrText() => _text(node),
      IrVector() => _vector(node),
    };

    final absolute = node.position != null;
    final autoLayoutParent =
        parent != null && parent.direction != IrLayoutDirection.stack;
    if (absolute) {
      if (autoLayoutParent) json['layoutPositioning'] = 'ABSOLUTE';
      json['position'] = node.position!.toJson();
      if (node.rotation != 0) json['rotation'] = node.rotation;
    }

    json['layoutSizingHorizontal'] = horizontal;
    json['layoutSizingVertical'] = vertical;
    if (node.width.isFixed) json['width'] = node.width.value;
    if (node.height.isFixed) json['height'] = node.height.value;

    if (node.instance case final ref?) {
      json['instance'] = {
        'component': ref.component,
        'variant': ref.key,
        if (ref.props.isNotEmpty) 'props': ref.props,
      };
    }
    json['pluginData'] = {
      if (node.origin.isNotEmpty) 'origin': node.origin,
      if (node.source != null) 'source': node.source,
      if (node is IrFrame && node.role != null) 'role': node.role,
    };
    return json;
  }

  /// Maps IR sizing to Figma's `layoutSizing*`, downgrading combinations
  /// Figma rejects.
  String _sizing(
    IrSizing s,
    IrNode node,
    IrFrame? parent, {
    required bool horizontal,
  }) {
    final autoLayoutSelf =
        node is IrText ||
        (node is IrFrame && node.direction != IrLayoutDirection.stack);
    switch (s.mode) {
      case SizingMode.fixed:
        return 'FIXED';
      case SizingMode.hug:
        if (!autoLayoutSelf) {
          _warn(
            '${node.name}: absolute-layout frames cannot hug; using fixed',
            node,
          );
          return 'FIXED';
        }
        return 'HUG';
      case SizingMode.fill:
        if (parent == null) return 'FIXED';
        // Stack children stretch via constraints; the plugin sizes them.
        if (parent.direction == IrLayoutDirection.stack) return 'FILL';
        final rendered = _rendered[parent];
        final parentHugs = rendered == null
            ? (horizontal ? parent.width : parent.height).isHug
            : (horizontal ? rendered.$1 : rendered.$2) == 'HUG';
        if (parentHugs) {
          _warn(
            '${node.name}: fills a parent that hugs its content; using hug',
            node,
          );
          return autoLayoutSelf ? 'HUG' : 'FIXED';
        }
        return 'FILL';
    }
  }

  Map<String, Object?> _frame(IrFrame f) {
    final json = <String, Object?>{
      'type': 'FRAME',
      'name': f.name,
      'layoutMode': switch (f.direction) {
        IrLayoutDirection.vertical => 'VERTICAL',
        IrLayoutDirection.horizontal => 'HORIZONTAL',
        IrLayoutDirection.stack => 'NONE',
      },
    };
    if (f.direction != IrLayoutDirection.stack) {
      json.addAll({
        'primaryAxisAlignItems': switch (f.mainAlign) {
          IrMainAlign.start => 'MIN',
          IrMainAlign.center => 'CENTER',
          IrMainAlign.end => 'MAX',
          IrMainAlign.spaceBetween => 'SPACE_BETWEEN',
        },
        'counterAxisAlignItems': switch (f.crossAlign) {
          IrCrossAlign.start => 'MIN',
          IrCrossAlign.center => 'CENTER',
          IrCrossAlign.end => 'MAX',
          IrCrossAlign.baseline =>
            f.direction == IrLayoutDirection.horizontal ? 'BASELINE' : 'MIN',
        },
        'itemSpacing': f.gap,
        if (f.wrap) 'layoutWrap': 'WRAP',
        if (f.wrap) 'counterAxisSpacing': f.runGap,
        'paddingTop': f.padding.top,
        'paddingRight': f.padding.right,
        'paddingBottom': f.padding.bottom,
        'paddingLeft': f.padding.left,
      });
    }
    if (f.minWidth != null) json['minWidth'] = f.minWidth;
    if (f.minHeight != null) json['minHeight'] = f.minHeight;
    final image = f.image;
    final svg = image != null && (_doc?.images[image.asset]?.isSvg ?? false);
    json['fills'] = [
      if (f.fill != null) _paint(f.fill!),
      if (f.gradient != null)
        _gradient(
          f.gradient!,
          f.width.value ?? f.gradient!.size?.$1,
          f.height.value ?? f.gradient!.size?.$2,
        ),
      if (image != null && !svg)
        {
          'type': 'IMAGE',
          'image': image.asset,
          'scaleMode': _scaleMode(image.fit),
        },
    ];
    if (svg) {
      json['svg'] = {'image': image.asset, 'scaleMode': _scaleMode(image.fit)};
    }
    if (f.stroke != null) {
      json['strokes'] = [_paint(f.stroke!.color)];
      json['strokeWeight'] = f.stroke!.width;
      json['strokeAlign'] = 'INSIDE';
    }
    final c = f.corners;
    if (!c.isZero) {
      if (c.isUniform) {
        json['cornerRadius'] = c.topLeft;
      } else {
        json.addAll({
          'topLeftRadius': c.topLeft,
          'topRightRadius': c.topRight,
          'bottomRightRadius': c.bottomRight,
          'bottomLeftRadius': c.bottomLeft,
        });
      }
    }
    if (f.shadows.isNotEmpty || f.backgroundBlur != null) {
      json['effects'] = [
        for (final e in f.shadows) _effect(e),
        if (f.backgroundBlur case final radius?)
          {
            'type': 'BACKGROUND_BLUR',
            'blurType': 'NORMAL',
            'radius': radius,
            'visible': true,
          },
      ];
      // An effect style holds only the shadows.
      if (f.shadowToken != null && f.backgroundBlur == null) {
        json['effectStyle'] = f.shadowToken;
      }
    }
    json['clipsContent'] = f.clip;
    json['children'] = [
      for (final child in f.children) _node(child, parent: f),
    ];
    return json;
  }

  Map<String, Object?> _text(IrText t) {
    final s = t.style;
    return {
      'type': 'TEXT',
      'name': t.name,
      'characters': t.text,
      ..._typography(s),
      if (s.token != null) 'textStyle': s.token,
      'fills': [_paint(s.color)],
      'textAlignHorizontal': switch (t.align) {
        IrTextAlign.left => 'LEFT',
        IrTextAlign.center => 'CENTER',
        IrTextAlign.right => 'RIGHT',
        IrTextAlign.justify => 'JUSTIFIED',
      },
      'textAutoResize': t.width.isHug ? 'WIDTH_AND_HEIGHT' : 'HEIGHT',
      if (t.maxLines != null) 'maxLines': t.maxLines,
    };
  }

  Map<String, Object?> _vector(IrVector v) => {
    'type': 'VECTOR',
    'name': v.name,
    'vectorPaths': [
      {'windingRule': v.evenOdd ? 'EVENODD' : 'NONZERO', 'data': v.path},
    ],
    'fills': [
      if (v.fill != null) _paint(v.fill!),
      if (v.image case final image?)
        {
          'type': 'IMAGE',
          'image': image.asset,
          'scaleMode': _scaleMode(image.fit),
        },
    ],
    if (v.stroke case final stroke?) ...{
      'strokes': [_paint(stroke.color)],
      'strokeWeight': stroke.width,
      'strokeAlign': 'CENTER',
      'strokeCap': switch (v.strokeCap) {
        IrStrokeCap.none => 'NONE',
        IrStrokeCap.round => 'ROUND',
        IrStrokeCap.square => 'SQUARE',
      },
    },
  };

  /// Font, size, line height and letter spacing, in Figma's shape.
  Map<String, Object?> _typography(IrTextStyle s) {
    final fontName = {
      'family': s.fontFamily,
      'style': figmaFontStyle(s.fontWeight, italic: s.italic),
    };
    _fonts['${fontName['family']}/${fontName['style']}'] = fontName;
    return {
      'fontName': fontName,
      'fontSize': s.fontSize,
      'lineHeight': s.lineHeight == null
          ? {'unit': 'AUTO'}
          : {'unit': 'PIXELS', 'value': s.lineHeight},
      'letterSpacing': {'unit': 'PIXELS', 'value': s.letterSpacing},
    };
  }

  /// A Figma gradient paint. `gradientTransform` maps the node's unit
  /// square to gradient space, where a linear gradient runs from (0, 0.5)
  /// to (1, 0.5) and a radial one is the circle around (0.5, 0.5) of
  /// radius 0.5.
  Map<String, Object?> _gradient(IrGradient g, double? width, double? height) {
    List<List<double>> transform;
    if (g.sweep) {
      // Figma's angular gradient starts toward +x of its unit square and
      // turns clockwise, like Flutter's. Angles are kept true in pixels on
      // a non-square frame, and the start is turned by [rotation].
      final (cx, cy) = g.center;
      final w = width ?? 1, h = height ?? 1;
      final k = 1 / (w > h ? w : h);
      final c = cos(g.rotation), s = sin(g.rotation);
      transform = [
        [c * w * k, s * h * k, 0.5 - c * cx * w * k - s * cy * h * k],
        [-s * w * k, c * h * k, 0.5 + s * cx * w * k - c * cy * h * k],
      ];
    } else if (g.radial) {
      final (cx, cy) = g.center;
      // The radius is a fraction of the shortest side; in the unit square
      // that is a different fraction per axis (unknown sizes: square).
      final shortest = width != null && height != null
          ? (width < height ? width : height)
          : null;
      final rx = shortest == null ? g.radius : g.radius * shortest / width!;
      final ry = shortest == null ? g.radius : g.radius * shortest / height!;
      transform = [
        [1 / (2 * rx), 0, 0.5 - cx / (2 * rx)],
        [0, 1 / (2 * ry), 0.5 - cy / (2 * ry)],
      ];
    } else {
      final (x0, y0) = g.begin;
      final (x1, y1) = g.end;
      final dx = x1 - x0, dy = y1 - y0;
      final len2 = dx * dx + dy * dy;
      transform = len2 == 0
          ? [
              [1, 0, 0],
              [0, 1, 0],
            ]
          : [
              [dx / len2, dy / len2, -(x0 * dx + y0 * dy) / len2],
              [-dy / len2, dx / len2, 0.5 - (-x0 * dy + y0 * dx) / len2],
            ];
    }
    return {
      'type': g.sweep
          ? 'GRADIENT_ANGULAR'
          : g.radial
          ? 'GRADIENT_RADIAL'
          : 'GRADIENT_LINEAR',
      'gradientTransform': transform,
      'gradientStops': [
        for (var i = 0; i < g.colors.length; i++)
          {'color': _rgba(g.colors[i]), 'position': g.stops[i]},
      ],
    };
  }

  /// Figma's closest scale mode: `CROP` without a transform stretches.
  String _scaleMode(IrBoxFit fit) => switch (fit) {
    IrBoxFit.cover || IrBoxFit.fitWidth || IrBoxFit.fitHeight => 'FILL',
    IrBoxFit.contain || IrBoxFit.scaleDown || IrBoxFit.none => 'FIT',
    IrBoxFit.fill => 'CROP',
  };

  /// A solid paint. Token colors name the variable to bind; the alpha stays
  /// on the paint so e.g. `onSurface` at 38% binds to `onSurface`.
  Map<String, Object?> _paint(IrColor c) => {
    'type': 'SOLID',
    'color': {'r': c.r, 'g': c.g, 'b': c.b},
    'opacity': c.a,
    if (c.token != null) 'variable': c.token,
  };

  Map<String, Object?> _designSystem(IrDocument doc, IrDesignSystem ds) => {
    'collection': '${doc.project} theme',
    'modes': ds.modes,
    'activeMode': ds.activeMode,
    'variables': [
      for (final c in ds.colors)
        {
          'name': c.name,
          'type': 'COLOR',
          'values': {
            for (final MapEntry(key: mode, value: v) in c.values.entries)
              mode: _rgba(v),
          },
        },
    ],
    'textStyles': [
      for (final t in ds.textStyles) {'name': t.name, ..._typography(t.style)},
    ],
    'effectStyles': [
      for (final s in ds.shadows)
        {
          'name': s.name,
          'effects': [for (final e in s.shadows) _effect(e)],
        },
    ],
    'components': [
      for (final c in ds.components)
        {
          'name': c.name,
          if (c.source != null) 'source': c.source,
          'variants': [
            for (final v in c.variants)
              {
                'key': IrInstanceRef(c.name, v.props).key,
                'name': IrInstanceRef(c.name, v.props).variantName,
                'uses': v.uses,
              },
          ],
        },
    ],
  };

  Map<String, Object?> _effect(IrShadow s) => {
    'type': 'DROP_SHADOW',
    'color': _rgba(s.color),
    'offset': {'x': s.x, 'y': s.y},
    'radius': s.blur,
    'spread': s.spread,
    'visible': true,
    'blendMode': 'NORMAL',
  };

  Map<String, Object?> _rgba(IrColor c) => {
    'r': c.r,
    'g': c.g,
    'b': c.b,
    'a': c.a,
  };

  void _warn(String message, IrNode node) => _diagnostics.add(
    IrDiagnostic(IrSeverity.warning, message, source: node.source),
  );
}

/// Figma font style name for a CSS-style weight, e.g. `700` → `Bold`.
String figmaFontStyle(int weight, {bool italic = false}) {
  final base = switch ((weight / 100).round().clamp(1, 9)) {
    1 => 'Thin',
    2 => 'ExtraLight',
    3 => 'Light',
    4 => 'Regular',
    5 => 'Medium',
    6 => 'SemiBold',
    7 => 'Bold',
    8 => 'ExtraBold',
    _ => 'Black',
  };
  if (!italic) return base;
  return base == 'Regular' ? 'Italic' : '$base Italic';
}
