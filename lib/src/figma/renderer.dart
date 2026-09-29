import 'package:flutter2figma/ir.dart';

import '../version.dart';

const designFormat = 'flutter2figma/design';
const designVersion = 2;

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

  Map<String, Object?> render(IrDocument doc) {
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
      'screens': screens,
      'diagnostics': [
        for (final d in [...doc.diagnostics, ..._diagnostics]) d.toJson(),
      ],
    };
  }

  Map<String, Object?> _node(IrNode node, {required IrFrame? parent}) {
    final json = switch (node) {
      IrFrame() => _frame(node),
      IrText() => _text(node),
    };

    final absolute = node.position != null;
    final autoLayoutParent =
        parent != null && parent.direction != IrLayoutDirection.stack;
    if (absolute) {
      if (autoLayoutParent) json['layoutPositioning'] = 'ABSOLUTE';
      json['position'] = node.position!.toJson();
    }

    json['layoutSizingHorizontal'] = _sizing(
      node.width,
      node,
      parent,
      horizontal: true,
    );
    json['layoutSizingVertical'] = _sizing(
      node.height,
      node,
      parent,
      horizontal: false,
    );
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
        final parentAxis = horizontal ? parent.width : parent.height;
        if (parentAxis.isHug) {
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
        'paddingTop': f.padding.top,
        'paddingRight': f.padding.right,
        'paddingBottom': f.padding.bottom,
        'paddingLeft': f.padding.left,
      });
    }
    if (f.minWidth != null) json['minWidth'] = f.minWidth;
    if (f.minHeight != null) json['minHeight'] = f.minHeight;
    json['fills'] = [if (f.fill != null) _paint(f.fill!)];
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
    if (f.shadows.isNotEmpty) {
      json['effects'] = [for (final e in f.shadows) _effect(e)];
      if (f.shadowToken != null) json['effectStyle'] = f.shadowToken;
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
