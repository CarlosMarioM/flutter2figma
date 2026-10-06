import 'dart:math';
import 'dart:typed_data';

import 'package:flutter2figma/ir.dart';

import '../compiler/icon_font.dart';
import '../compiler/material_theme.dart';
import 'auto_layout.dart';
import 'runtime_capture.dart';

/// Turns a [CapturedScreen] into an [IrScreen]: every recorded node at its
/// exact position (absolute layout), colors and text bound to the theme's
/// tokens when their values match the theme the screen rendered with.
class CaptureConverter {
  CaptureConverter({this.iconFonts = const {}, this.autoLayout = true});

  final Map<String, IconFont> iconFonts;

  /// Rebuild Figma auto layout where it reproduces Flutter's positions.
  final bool autoLayout;

  // What auto layout inference needs to know about the converted nodes.
  final _boxes = Expando<Box>();
  final _flexDirection = Expando<IrLayoutDirection>();
  final _flexFactor = Expando<int>();

  /// Images used by the converted screens, embedded in the document.
  final images = <String, IrImageAsset>{};

  late Map<int, String> _colorRoles;
  late Map<int, String> _rgbRoles;
  late Map<String, Map<String, Object?>> _textStyles;
  late CapturedScreen _screen;

  IrScreen convert(CapturedScreen screen, {String? source}) {
    _screen = screen;
    final scheme = (screen.theme['colorScheme'] as Map?) ?? const {};
    _colorRoles = {};
    _rgbRoles = {};
    for (final MapEntry(:key, :value) in scheme.entries) {
      final argb = _argb(value as String?);
      if (argb == null) continue;
      _colorRoles.putIfAbsent(argb, () => key as String);
      if (argb >> 24 == 0xff) {
        _rgbRoles.putIfAbsent(argb & 0xffffff, () => key as String);
      }
    }
    _textStyles = {
      for (final MapEntry(:key, :value)
          in ((screen.theme['textTheme'] as Map?) ?? const {}).entries)
        key as String: (value as Map).cast<String, Object?>(),
    };

    final root = IrFrame(
      name: screen.name,
      role: 'screen',
      origin: const ['runtime'],
      direction: IrLayoutDirection.stack,
      width: IrSizing.fixed(screen.width),
      height: IrSizing.fixed(screen.height),
      clip: true,
      children: [
        for (final n in screen.tree)
          ..._node(n, 0, 0, 1, (0, 0, screen.width, screen.height)),
      ],
    );
    _boxes[root] = (0, 0, screen.width, screen.height);
    if (autoLayout) {
      AutoLayout(
        boxes: _boxes,
        flexDirection: _flexDirection,
        flexFactor: _flexFactor,
      ).apply(root);
    }
    return IrScreen(
      name: screen.name,
      width: screen.width,
      height: screen.height,
      root: root,
      source: source,
    );
  }

  /// [visible] is the area not clipped away by ancestors (x, y, w, h):
  /// nodes entirely outside it (items a scroll view keeps laid out past
  /// its edge) are dropped.
  /// Converts capture node [n] and records each resulting node's box (and
  /// Row/Column facts) for auto layout.
  List<IrNode> _node(
    Map<String, Object?> n,
    double px,
    double py,
    double opacity,
    (double, double, double, double) visible, [
    double parentAngle = 0,
  ]) {
    final nodes = _convert(n, px, py, opacity, visible, parentAngle);
    final [x, y, w, h] = [
      for (final v in (n['rect'] as List).cast<num>()) v.toDouble(),
    ];
    final flex = (n['flexFactor'] as num?)?.toInt();
    for (final node in nodes) {
      _boxes[node] ??= (x - px, y - py, w, h);
      if (flex != null) _flexFactor[node] ??= flex;
    }
    return nodes;
  }

  List<IrNode> _convert(
    Map<String, Object?> n,
    double px,
    double py,
    double opacity,
    (double, double, double, double) visible,
    double parentAngle,
  ) {
    final rect = (n['rect'] as List)
        .cast<num>()
        .map((v) => v.toDouble())
        .toList();
    var [x, y, w, h] = rect;
    if (n['local'] == true) {
      // Drawn by a custom painter: already in the parent's coordinates,
      // maybe turned around its own corner (text drawn rotated).
      final nodes = _convertAt(n, x, y, w, h, 0, 0, opacity, visible, 0);
      final turn = (n['turn'] as num?)?.toDouble() ?? 0;
      for (final node in nodes) {
        if ((turn * 180 / pi).abs() > 0.01) node.rotation = _r(turn * 180 / pi);
        _boxes[node] ??= (x, y, w, h);
      }
      return nodes;
    }
    final (vx, vy, vw, vh) = visible;
    if (x >= vx + vw || y >= vy + vh || x + w <= vx || y + h <= vy) {
      return const [];
    }
    // A turned node (under a Transform.rotate), or one inside a turned
    // parent: placed by its own top-left corner in the parent's turned
    // coordinates, at its own size, and turned by the difference.
    final angle = (n['angle'] as num?)?.toDouble() ?? 0;
    final turned = angle != 0 || parentAngle != 0;
    var rotation = 0.0;
    if (turned) {
      final origin = (n['origin'] as List?)?.cast<num>();
      final size = (n['size'] as List?)?.cast<num>();
      final dx = (origin?[0].toDouble() ?? x) - px;
      final dy = (origin?[1].toDouble() ?? y) - py;
      final c = cos(parentAngle), sn = sin(parentAngle);
      x = dx * c + dy * sn;
      y = -dx * sn + dy * c;
      px = py = 0;
      if (size != null) [w, h] = [size[0].toDouble(), size[1].toDouble()];
      rotation = (angle - parentAngle) * 180 / pi;
    }
    final nodes = _convertAt(n, x, y, w, h, px, py, opacity, visible, angle);
    if (turned) {
      for (final node in nodes) {
        if (rotation.abs() > 0.01) node.rotation = _r(rotation);
        _boxes[node] ??= (x, y, w, h);
      }
    }
    return nodes;
  }

  List<IrNode> _convertAt(
    Map<String, Object?> n,
    double x,
    double y,
    double w,
    double h,
    double px,
    double py,
    double opacity,
    (double, double, double, double) visible,
    double angle,
  ) {
    final [rx, ry, rw, rh] = [
      for (final v in (n['rect'] as List).cast<num>()) v.toDouble(),
    ];
    final (vx, vy, vw, vh) = visible;
    final inner = n['clip'] == true && angle == 0
        ? (
            max(rx, vx),
            max(ry, vy),
            min(rx + rw, vx + vw) - max(rx, vx),
            min(ry + rh, vy + vh) - max(ry, vy),
          )
        : visible;
    final position = IrPosition(left: _r(x - px), top: _r(y - py));
    final name = n['name'] as String? ?? n['type'] as String;
    // Children are placed from this node's top-left corner: on screen
    // ([rx], [ry]) when upright, its turned corner otherwise.
    final origin = (n['origin'] as List?)?.cast<num>();
    final (cx, cy) = origin == null
        ? (rx, ry)
        : (origin[0].toDouble(), origin[1].toDouble());
    List<IrNode> kids(double alpha) => [
      for (final c
          in (n['children'] as List? ?? const []).cast<Map<String, Object?>>())
        ..._node(c, cx, cy, alpha, inner, angle),
    ];

    switch (n['type']) {
      case 'group':
        final alpha = opacity * ((n['opacity'] as num?)?.toDouble() ?? 1);
        final clip = n['clip'] == true;
        final children = kids(alpha);
        if (n['blur'] case final num sigma) {
          // Figma's radius is about twice Flutter's sigma. It shows through
          // a translucent fill: put it on the backdrop's own background
          // when it has one.
          final radius = _r(sigma * 2.0);
          final first = children.firstOrNull;
          if (first is IrFrame &&
              (first.fill != null || first.gradient != null) &&
              (first.width.value ?? -1) >= w - 0.5 &&
              (first.height.value ?? -1) >= h - 0.5) {
            first.backgroundBlur = radius;
          } else {
            final group = _frame(name, position, w, h)
              ..backgroundBlur = radius
              ..fill = const IrColor(1, 1, 1, 0.01)
              ..children.addAll(children);
            return [group];
          }
        }
        // A group that only arranges: keep it when it groups several
        // children (structure), else let its child stand in.
        if (!clip &&
            children.length <= 1 &&
            n['align'] != true &&
            angle == 0 &&
            children.every((c) => c.rotation == 0)) {
          for (final c in children) {
            c.position = _shift(c.position, x - px, y - py);
            if (_boxes[c] case (final cx, final cy, final cw, final ch)) {
              _boxes[c] = (cx + x - px, cy + y - py, cw, ch);
            }
          }
          return children;
        }
        final group = _frame(name, position, w, h)
          ..clip = clip
          ..corners = _corners(n['radius'], w, h)
          ..children.addAll(children);
        if (n['flex'] case final String direction) {
          _flexDirection[group] = direction == 'vertical'
              ? IrLayoutDirection.vertical
              : IrLayoutDirection.horizontal;
        }
        return [group];
      case 'box':
        final frame = _frame(name, position, w, h)
          ..fill = _color(n['fill'], opacity)
          ..corners = _corners(n['radius'], w, h)
          ..clip = n['clip'] == true;
        final stroke = n['stroke'] as Map?;
        final strokeColor = _color(stroke?['color'], opacity);
        final edge = <IrNode>[];
        if (strokeColor != null && strokeColor.a > 0) {
          final width = (stroke!['width'] as num?)?.toDouble() ?? 1;
          if (stroke['side'] case final String side) {
            // A one-sided border (dividers): a line along that edge.
            final top = side == 'bottom' ? h - width : 0.0;
            edge.add(
              IrFrame(
                name: 'Border',
                origin: const ['Border'],
                width: IrSizing.fixed(w),
                height: IrSizing.fixed(width),
                fill: strokeColor,
                position: IrPosition(left: 0, top: _r(top)),
              ),
            );
            _boxes[edge.last] = (0, top, w, width);
          } else {
            frame.stroke = IrStroke(color: strokeColor, width: width);
          }
        }
        frame.shadows = _shadows(n);
        if (n['gradient'] case final Map gradient) {
          frame.gradient = _gradient(
            gradient.cast<String, Object?>(),
            opacity,
            (w, h),
          );
        }
        if (n['image'] case final String id when _image(id) != null) {
          frame.image = IrImagePaint(_image(id)!, fit: _fit(n['fit']));
        }
        frame.children.addAll([...kids(opacity), ...edge]);
        return [frame];
      case 'text':
        final style = (n['style'] as Map).cast<String, Object?>();
        final text = n['text'] as String? ?? '';
        // An empty text field's input: nothing to draw.
        if (text.isEmpty) return const [];
        final label = text.length > 40 ? '${text.substring(0, 40)}…' : text;
        final irStyle = _textStyle(style, opacity);
        final lineHeight = irStyle.lineHeight ?? irStyle.fontSize * 1.2;
        final singleLine =
            n['maxLines'] == null &&
            !text.contains('\n') &&
            h < lineHeight * 1.5;
        return [
          IrText(
            name: label.isEmpty ? 'Text' : label,
            origin: [name],
            text: text,
            style: irStyle,
            // A single line hugs its text, so edits resize it; wrapped text
            // keeps Flutter's width (and so its line breaks).
            width: singleLine
                ? const IrSizing.hug()
                : IrSizing.fixed(_r(w + 0.5)),
            align: switch (n['align']) {
              'center' => IrTextAlign.center,
              'right' || 'end' => IrTextAlign.right,
              'justify' => IrTextAlign.justify,
              _ => IrTextAlign.left,
            },
            maxLines: (n['maxLines'] as num?)?.toInt(),
            position: position,
          ),
        ];
      case 'icon':
        final size = (n['size'] as num?)?.toDouble() ?? w;
        final color = _color(n['color'], opacity) ?? IrColor.black;
        final frame = IrFrame(
          name: 'Icon',
          role: 'icon',
          origin: [name],
          direction: IrLayoutDirection.stack,
          width: IrSizing.fixed(w),
          height: IrSizing.fixed(h),
          position: position,
        );
        final glyph = iconFonts[n['family']]?.glyph(
          (n['codePoint'] as num).toInt(),
          size,
        );
        if (glyph == null) {
          frame
            ..fill = color.withAlpha(color.a * 0.24)
            ..corners = IrCorners.all(size / 6);
        } else if (!glyph.isEmpty) {
          frame.children.add(
            IrVector(
              name: 'Glyph',
              path: glyph.path,
              fill: color,
              width: IrSizing.fixed(max(0.01, glyph.width)),
              height: IrSizing.fixed(max(0.01, glyph.height)),
              position: IrPosition(
                left: _r(glyph.x + (w - size) / 2),
                top: _r(glyph.y + (h - size) / 2),
              ),
            ),
          );
        }
        return [frame];
      case 'vector':
        final fill = _color(n['fill'], opacity);
        final stroke = (n['stroke'] as Map?)?.cast<String, Object?>();
        final strokeColor = _color(stroke?['color'], opacity);
        final imageKey = n['image'] is String
            ? _image(n['image'] as String)
            : null;
        if (fill == null && strokeColor == null && imageKey == null) {
          return const [];
        }
        return [
          IrVector(
            name: name,
            origin: [name],
            path: n['path'] as String,
            fill: fill,
            image: imageKey == null
                ? null
                : IrImagePaint(imageKey, fit: IrBoxFit.fill),
            stroke: strokeColor == null
                ? null
                : IrStroke(
                    color: strokeColor,
                    width: (stroke!['width'] as num?)?.toDouble() ?? 1,
                  ),
            strokeCap: switch (n['cap']) {
              'round' => IrStrokeCap.round,
              'square' => IrStrokeCap.square,
              _ => IrStrokeCap.none,
            },
            evenOdd: n['evenOdd'] == true,
            width: IrSizing.fixed(max(0.01, _r(w))),
            height: IrSizing.fixed(max(0.01, _r(h))),
            position: position,
          ),
        ];
      case 'image':
        final key = _image(n['image'] as String);
        if (key == null) return const [];
        return [
          _frame(n['name'] as String? ?? name, position, w, h)
            ..role = 'image'
            ..image = IrImagePaint(key, fit: _fit(n['fit'])),
        ];
    }
    return const [];
  }

  IrFrame _frame(String name, IrPosition position, double w, double h) =>
      IrFrame(
        name: name,
        origin: [name],
        direction: IrLayoutDirection.stack,
        width: IrSizing.fixed(max(0.01, _r(w))),
        height: IrSizing.fixed(max(0.01, _r(h))),
        position: position,
      );

  IrPosition? _shift(IrPosition? p, double dx, double dy) => p == null
      ? null
      : IrPosition(left: _r((p.left ?? 0) + dx), top: _r((p.top ?? 0) + dy));

  /// The embedded asset for a captured image id, keyed per screen.
  String? _image(String id) {
    final bytes = _screen.images[id];
    if (bytes == null) return null;
    final key = 'runtime/${_screen.name}/$id.png';
    images.putIfAbsent(key, () {
      final data = Uint8List.fromList(bytes);
      final header = ByteData.sublistView(data);
      // Captured at 2x: logical size is half the pixels.
      return IrImageAsset(
        key: key,
        format: 'png',
        width: data.length >= 24 ? header.getUint32(16) / 2 : 0,
        height: data.length >= 24 ? header.getUint32(20) / 2 : 0,
        data: data,
      );
    });
    return key;
  }

  IrGradient? _gradient(
    Map<String, Object?> g,
    double opacity,
    (double, double) size,
  ) {
    final colors = [
      for (final c in (g['colors'] as List? ?? const [])) _color(c, opacity),
    ];
    if (colors.isEmpty || colors.contains(null)) return null;
    (double, double) point(Object? v, (double, double) fallback) {
      final l = (v as List?)?.cast<num>();
      return l == null ? fallback : (l[0].toDouble(), l[1].toDouble());
    }

    final stops = (g['stops'] as List?)?.cast<num>();
    return IrGradient(
      colors: colors.cast<IrColor>(),
      stops: stops?.length == colors.length
          ? [for (final s in stops!) s.toDouble()]
          : null,
      radial: g['type'] == 'radial',
      sweep: g['type'] == 'sweep',
      rotation: (g['rotation'] as num?)?.toDouble() ?? 0,
      begin: point(g['begin'], (0, 0.5)),
      end: point(g['end'], (1, 0.5)),
      center: point(g['center'], (0.5, 0.5)),
      radius: (g['radius'] as num?)?.toDouble() ?? 0.5,
      size: size,
    );
  }

  IrBoxFit _fit(Object? fit) =>
      IrBoxFit.values.where((f) => f.name == fit).firstOrNull ?? IrBoxFit.fill;

  IrCorners _corners(Object? radius, double w, double h) {
    final r = (radius as num?)?.toDouble() ?? 0;
    if (r <= 0) return IrCorners.zero;
    return IrCorners.all(_r(min(r, min(w, h) / 2)));
  }

  List<IrShadow> _shadows(Map<String, Object?> n) {
    final explicit = (n['shadows'] as List? ?? const []).cast<Map>();
    if (explicit.isNotEmpty) {
      return [
        for (final s in explicit)
          IrShadow(
            color: _color(s['color'], 1, bind: false) ?? IrColor.black,
            x: (s['x'] as num).toDouble(),
            y: (s['y'] as num).toDouble(),
            blur: (s['blur'] as num).toDouble(),
            spread: (s['spread'] as num).toDouble(),
          ),
      ];
    }
    final elevation = (n['elevation'] as num?)?.toDouble() ?? 0;
    final shadowColor = _argb(n['shadowColor'] as String?);
    if (elevation <= 0 || shadowColor == null || shadowColor >> 24 == 0) {
      return const [];
    }
    return const MaterialTheme().shadows(elevation);
  }

  /// A captured color, bound to the color scheme role with the same value
  /// (or the same RGB, keeping the alpha: `onSurface` at 38%).
  IrColor? _color(Object? hex, double opacity, {bool bind = true}) {
    final argb = _argb(hex as String?);
    if (argb == null) return null;
    final alpha = ((argb >> 24) & 0xff) / 255 * opacity;
    final role = !bind
        ? null
        : alpha >= 1
        ? _colorRoles[argb]
        : _rgbRoles[argb & 0xffffff];
    final color = IrColor.fromArgb32(
      argb | 0xff000000,
      token: role == null ? null : MaterialTheme.colorToken(role),
    );
    return alpha >= 1 ? color : color.withAlpha(alpha);
  }

  IrTextStyle _textStyle(Map<String, Object?> s, double opacity) {
    double? num_(String k) => (s[k] as num?)?.toDouble();
    final size = num_('size') ?? 14;
    final height = num_('height');
    final style = IrTextStyle(
      fontFamily: s['family'] as String? ?? 'Roboto',
      fontSize: size,
      fontWeight: (s['weight'] as num?)?.toInt() ?? 400,
      italic: s['italic'] == true,
      color: _color(s['color'], opacity) ?? IrColor.black,
      lineHeight: height == null ? null : _r(height * size),
      letterSpacing: num_('letterSpacing') ?? 0,
    );
    for (final MapEntry(key: name, value: t) in _textStyles.entries) {
      final tSize = (t['size'] as num?)?.toDouble();
      final tHeight = (t['height'] as num?)?.toDouble();
      if (t['family'] == s['family'] &&
          tSize == size &&
          (t['weight'] as num?)?.toInt() == style.fontWeight &&
          tHeight == height &&
          ((t['letterSpacing'] as num?)?.toDouble() ?? 0) ==
              style.letterSpacing) {
        return style.withToken(MaterialTheme.textToken(name));
      }
    }
    return style;
  }

  static int? _argb(String? hex) =>
      hex == null ? null : int.tryParse(hex.substring(1), radix: 16);

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}
