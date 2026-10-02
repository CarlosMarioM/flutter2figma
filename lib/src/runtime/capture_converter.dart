import 'dart:math';
import 'dart:typed_data';

import 'package:flutter2figma/ir.dart';

import '../compiler/icon_font.dart';
import '../compiler/material_theme.dart';
import 'runtime_capture.dart';

/// Turns a [CapturedScreen] into an [IrScreen]: every recorded node at its
/// exact position (absolute layout), colors and text bound to the theme's
/// tokens when their values match the theme the screen rendered with.
class CaptureConverter {
  CaptureConverter({this.iconFonts = const {}});

  final Map<String, IconFont> iconFonts;

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
  List<IrNode> _node(
    Map<String, Object?> n,
    double px,
    double py,
    double opacity,
    (double, double, double, double) visible,
  ) {
    final rect = (n['rect'] as List)
        .cast<num>()
        .map((v) => v.toDouble())
        .toList();
    final [x, y, w, h] = rect;
    final (vx, vy, vw, vh) = visible;
    if (x >= vx + vw || y >= vy + vh || x + w <= vx || y + h <= vy) {
      return const [];
    }
    final inner = n['clip'] == true
        ? (
            max(x, vx),
            max(y, vy),
            min(x + w, vx + vw) - max(x, vx),
            min(y + h, vy + vh) - max(y, vy),
          )
        : visible;
    final position = IrPosition(left: _r(x - px), top: _r(y - py));
    final name = n['name'] as String? ?? n['type'] as String;
    List<IrNode> kids(double alpha) => [
      for (final c
          in (n['children'] as List? ?? const []).cast<Map<String, Object?>>())
        ..._node(c, x, y, alpha, inner),
    ];

    switch (n['type']) {
      case 'group':
        final alpha = opacity * ((n['opacity'] as num?)?.toDouble() ?? 1);
        final clip = n['clip'] == true;
        final children = kids(alpha);
        // A group that only arranges: keep it when it groups several
        // children (structure), else let its child stand in.
        if (!clip && children.length <= 1) {
          return [
            for (final c in children)
              c..position = _shift(c.position, x - px, y - py),
          ];
        }
        return [
          _frame(name, position, w, h)
            ..clip = clip
            ..corners = _corners(n['radius'], w, h)
            ..children.addAll(children),
        ];
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
            edge.add(
              IrFrame(
                name: 'Border',
                origin: const ['Border'],
                width: IrSizing.fixed(w),
                height: IrSizing.fixed(width),
                fill: strokeColor,
                position: IrPosition(
                  left: 0,
                  top: side == 'bottom' ? _r(h - width) : 0,
                ),
              ),
            );
          } else {
            frame.stroke = IrStroke(color: strokeColor, width: width);
          }
        }
        frame.shadows = _shadows(n);
        if (n['gradient'] case final Map gradient) {
          frame.gradient = _gradient(gradient.cast<String, Object?>(), opacity);
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
        return [
          IrText(
            name: label.isEmpty ? 'Text' : label,
            origin: [name],
            text: text,
            style: _textStyle(style, opacity),
            // Fixed width keeps Flutter's line breaks; height follows.
            width: IrSizing.fixed(_r(w + 0.5)),
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

  IrGradient? _gradient(Map<String, Object?> g, double opacity) {
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
      begin: point(g['begin'], (0, 0.5)),
      end: point(g['end'], (1, 0.5)),
      center: point(g['center'], (0.5, 0.5)),
      radius: (g['radius'] as num?)?.toDouble() ?? 0.5,
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
