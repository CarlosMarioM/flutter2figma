/// The part of the runtime harness (see `harness.dart`) that turns what a
/// `CustomPainter` draws into vectors.
///
/// The painter runs on [_VectorCanvas], which records each draw call:
///
/// - Shapes (`drawRect`, `drawRRect`, `drawDRRect`, `drawCircle`,
///   `drawOval`, `drawArc`, `drawLine`, `drawPath`) become vector nodes in
///   the painter's coordinates, through the canvas transform. Rects, rounded
///   rects, ovals and arcs are exact Béziers; a `Path` can't be read back, so
///   its contours are traced and simplified, keeping its corners.
/// - A solid fill or stroke becomes the vector's fill or stroke; a shader
///   (gradient) fill is the shape filled with an image of the shader.
/// - What vectors can't express (blurs, blend modes, shadows, images, text:
///   a `Paragraph` can't give its text back) is drawn alone into an image
///   where it paints. Text keeps its turn: it is drawn upright and rotated.
///
/// A painter that does something that changes everything after it (a
/// layer with a filter or blend, vertices, atlases, pictures), or draws too
/// many things, is kept as one image, as before.
library;

const vectorCanvasSource = r'''
// ---------------------------------------------------------------------------
// Custom painters as vectors.
// ---------------------------------------------------------------------------

/// A clip in force, as the painter set it.
class _Clip {
  _Clip(this.matrix, this.apply, this.bounds, {required this.rect});

  final Float64List matrix;
  final void Function(ui.Canvas) apply;

  /// Where it lets paint through, in the painter's coordinates.
  final ui.Rect bounds;

  /// Exactly [bounds] (an axis-aligned rect), so shapes inside it are
  /// untouched.
  final bool rect;
}

/// One draw call: how to replay it, and what it becomes.
class _Op {
  _Op(this.draw, this.matrix, this.clips, this.alpha);

  final void Function(ui.Canvas) draw;
  final Float64List matrix;
  final List<_Clip> clips;
  final double alpha;
}

class _VectorCanvas implements ui.Canvas {
  _VectorCanvas(this.recorder, this.size, this.name);

  final _Recorder recorder;
  final ui.Size size;
  final String name;

  /// Recorded nodes, in paint order (painter coordinates, `local`).
  final nodes = <Map<String, Object?>>[];

  /// Set when only an image of the whole painter shows what it drew.
  bool whole = false;

  r.Matrix4 _matrix = r.Matrix4.identity();
  List<_Clip> _clips = const [];
  double _alpha = 1;
  final _saves = <(r.Matrix4, List<_Clip>, double)>[];

  static const _maxNodes = 300;

  // --- State ---

  @override
  void save() => _saves.add((_matrix.clone(), _clips, _alpha));

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    save();
    // A layer that only fades its content: its opacity. Anything else
    // (filters, blend modes) changes how everything in it combines.
    if (_plain(paint) && paint.shader == null) {
      _alpha *= paint.color.a;
    } else {
      whole = true;
    }
  }

  @override
  void restore() {
    if (_saves.isEmpty) return;
    final (m, c, a) = _saves.removeLast();
    _matrix = m;
    _clips = c;
    _alpha = a;
  }

  @override
  void restoreToCount(int count) {
    while (_saves.length >= count && _saves.isNotEmpty) {
      restore();
    }
  }

  @override
  int getSaveCount() => _saves.length + 1;

  @override
  void translate(double dx, double dy) => _matrix.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => _matrix.scale(sx, sy ?? sx, 1);

  @override
  void rotate(double radians) => _matrix.rotateZ(radians);

  @override
  void skew(double sx, double sy) =>
      _matrix.multiply(r.Matrix4.skew(math.atan(sx), math.atan(sy)));

  @override
  void transform(Float64List matrix4) => _matrix.multiply(r.Matrix4.fromFloat64List(matrix4));

  @override
  Float64List getTransform() => Float64List.fromList(_matrix.storage);

  // --- Clips ---

  void _clip(void Function(ui.Canvas) apply, ui.Rect local, {required bool rect}) {
    final bounds = r.MatrixUtils.transformRect(_matrix, local);
    _clips = [
      ..._clips,
      _Clip(Float64List.fromList(_matrix.storage), apply, bounds, rect: rect && _axisAligned),
    ];
  }

  @override
  void clipRect(ui.Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.difference) {
      // Cuts a hole: shapes can't show it.
      _clip((c) => c.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias), _everywhere, rect: false);
      return;
    }
    _clip((c) => c.clipRect(rect, doAntiAlias: doAntiAlias), rect, rect: true);
  }

  @override
  void clipRRect(ui.RRect rrect, {bool doAntiAlias = true}) =>
      _clip((c) => c.clipRRect(rrect, doAntiAlias: doAntiAlias), rrect.outerRect, rect: false);

  @override
  void clipRSuperellipse(ui.RSuperellipse rsuperellipse, {bool doAntiAlias = true}) => _clip(
    (c) => c.clipRSuperellipse(rsuperellipse, doAntiAlias: doAntiAlias),
    rsuperellipse.outerRect,
    rect: false,
  );

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    final copy = ui.Path.from(path);
    _clip((c) => c.clipPath(copy, doAntiAlias: doAntiAlias), copy.getBounds(), rect: false);
  }

  ui.Rect get _clipBounds {
    var bounds = _everywhere;
    for (final c in _clips) {
      bounds = bounds.intersect(c.bounds);
    }
    return bounds;
  }

  @override
  ui.Rect getLocalClipBounds() {
    final inverse = r.Matrix4.tryInvert(_matrix);
    return inverse == null ? ui.Rect.zero : r.MatrixUtils.transformRect(inverse, _clipBounds);
  }

  @override
  ui.Rect getDestinationClipBounds() => _clipBounds;

  /// What `drawPaint` and `drawColor` cover: the painter, within the clips
  /// (current coordinates).
  ui.Rect get _paintArea {
    final inverse = r.Matrix4.tryInvert(_matrix);
    final area = (ui.Offset.zero & size).intersect(_clipBounds);
    return inverse == null || area.isEmpty ? ui.Rect.zero : r.MatrixUtils.transformRect(inverse, area);
  }

  /// Far beyond the painter, for paint that covers everything.
  ui.Rect get _everywhere => (ui.Offset.zero & size).inflate(size.longestSide + 100);

  // --- Shapes ---

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) {
    final paint = ui.Paint()
      ..color = color
      ..blendMode = blendMode;
    _shape('Color', [_Contour.rect(_paintArea)], paint, (c) => c.drawColor(color, blendMode), fillOnly: true);
  }

  @override
  void drawPaint(ui.Paint paint) {
    final p = _copy(paint);
    _shape('Paint', [_Contour.rect(_paintArea)], p, (c) => c.drawPaint(p), fillOnly: true);
  }

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    final p = _copy(paint);
    _shape('Rect', [_Contour.rect(rect)], p, (c) => c.drawRect(rect, p));
  }

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    final p = _copy(paint);
    _shape('Rounded rect', [_Contour.rrect(rrect)], p, (c) => c.drawRRect(rrect, p));
  }

  @override
  void drawDRRect(ui.RRect outer, ui.RRect inner, ui.Paint paint) {
    final p = _copy(paint);
    _shape(
      'Ring',
      [_Contour.rrect(outer), _Contour.rrect(inner)],
      p,
      (c) => c.drawDRRect(outer, inner, p),
      evenOdd: true,
    );
  }

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, ui.Paint paint) {
    final p = _copy(paint);
    _pixels(
      'Superellipse',
      rsuperellipse.outerRect.inflate(p.strokeWidth / 2 + 2),
      (c) => c.drawRSuperellipse(rsuperellipse, p),
    );
  }

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {
    final p = _copy(paint);
    _shape('Oval', [_Contour.arc(rect, 0, 2 * math.pi, center: false)], p, (c) => c.drawOval(rect, p));
  }

  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) {
    final p = _copy(paint);
    final rect = ui.Rect.fromCircle(center: c, radius: radius);
    _shape('Circle', [_Contour.arc(rect, 0, 2 * math.pi, center: false)], p, (cv) => cv.drawCircle(c, radius, p));
  }

  @override
  void drawArc(ui.Rect rect, double startAngle, double sweepAngle, bool useCenter, ui.Paint paint) {
    final p = _copy(paint);
    _shape(
      'Arc',
      [_Contour.arc(rect, startAngle, sweepAngle, center: useCenter)],
      p,
      (c) => c.drawArc(rect, startAngle, sweepAngle, useCenter, p),
    );
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    final p = _copy(paint)..style = ui.PaintingStyle.stroke;
    _shape('Line', [_Contour.line(p1, p2)], p, (c) => c.drawLine(p1, p2, p));
  }

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    final p = _copy(paint);
    final copy = ui.Path.from(path);
    _shape(
      'Path',
      _Contour.path(copy),
      p,
      (c) => c.drawPath(copy, p),
      evenOdd: copy.fillType == ui.PathFillType.evenOdd,
    );
  }

  // --- What only pixels show ---

  @override
  void drawShadow(ui.Path path, ui.Color color, double elevation, bool transparentOccluder) {
    final copy = ui.Path.from(path);
    _pixels(
      'Shadow',
      copy.getBounds().inflate(elevation * 3 + 4),
      (c) => c.drawShadow(copy, color, elevation, transparentOccluder),
    );
  }

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) {
    final p = _copy(paint);
    _pixels(
      'Image',
      offset & ui.Size(image.width.toDouble(), image.height.toDouble()),
      (c) => c.drawImage(image, offset, p),
    );
  }

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
    final p = _copy(paint);
    _pixels('Image', dst, (c) => c.drawImageRect(image, src, dst, p));
  }

  @override
  void drawImageNine(ui.Image image, ui.Rect center, ui.Rect dst, ui.Paint paint) {
    final p = _copy(paint);
    _pixels('Image', dst, (c) => c.drawImageNine(image, center, dst, p));
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<ui.Offset> points, ui.Paint paint) {
    if (points.isEmpty) return;
    final p = _copy(paint);
    final copy = List<ui.Offset>.of(points);
    var bounds = ui.Rect.fromPoints(copy.first, copy.first);
    for (final o in copy) {
      bounds = bounds.expandToInclude(ui.Rect.fromPoints(o, o));
    }
    _pixels('Points', bounds.inflate(p.strokeWidth + 2), (c) => c.drawPoints(pointMode, copy, p));
  }

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, ui.Paint paint) => drawPoints(pointMode, [
    for (var i = 0; i + 1 < points.length; i += 2) ui.Offset(points[i], points[i + 1]),
  ], paint);

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) {
    const pad = 4.0; // shadows and glyphs that overhang their box
    // Laid out without a max width (TextPainter.layout()), a paragraph is
    // infinitely wide; its text starts at the left and is the longest line.
    final width = paragraph.width.isFinite ? paragraph.width : paragraph.longestLine;
    if (!width.isFinite || !paragraph.height.isFinite) return;
    final box = ui.Rect.fromLTWH(
      offset.dx - pad,
      offset.dy - pad,
      width + 2 * pad,
      paragraph.height + 2 * pad,
    );
    final m = _matrix.storage;
    final scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final similar = _affine &&
        (m[0] - m[5]).abs() < 1e-6 &&
        (m[1] + m[4]).abs() < 1e-6 &&
        scale > 0;
    final turned = r.MatrixUtils.transformRect(_matrix, box);
    if (!similar || !_inside(turned)) {
      _pixels('Text', box, (c) => c.drawParagraph(paragraph, offset));
      return;
    }
    // Upright, at its own size, then turned in Figma: crisp and rotatable.
    final w = box.width * scale, h = box.height * scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(_scale * scale)
      ..translate(-box.left, -box.top);
    _fade(canvas, () => canvas.drawParagraph(paragraph, offset));
    final id = _finish(recorder, w, h);
    final corner = r.MatrixUtils.transformPoint(_matrix, box.topLeft);
    _add({
      'type': 'image',
      'name': 'Text',
      'local': true,
      'rect': [corner.dx, corner.dy, w, h],
      'turn': math.atan2(m[1], m[0]),
      'image': id,
      'fit': 'fill',
    });
  }

  @override
  void drawPicture(ui.Picture picture) => whole = true;

  @override
  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, ui.Paint paint) => whole = true;

  @override
  void drawAtlas(
    ui.Image atlas,
    List<ui.RSTransform> transforms,
    List<ui.Rect> rects,
    List<ui.Color>? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) => whole = true;

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) => whole = true;

  /// Canvas methods newer than this harness.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    whole = true;
    return null;
  }

  // --- Recording ---

  bool get _affine {
    final m = _matrix.storage;
    return m[3] == 0 && m[7] == 0 && m[11] == 0 && m[15] == 1;
  }

  bool get _axisAligned {
    final m = _matrix.storage;
    return _affine && m[1] == 0 && m[4] == 0;
  }

  /// Whether [bounds] (painter coordinates) is untouched by the clips.
  bool _inside(ui.Rect bounds) {
    for (final c in _clips) {
      if (!c.rect) return false;
      final b = c.bounds;
      if (bounds.left < b.left - 0.01 ||
          bounds.top < b.top - 0.01 ||
          bounds.right > b.right + 0.01 ||
          bounds.bottom > b.bottom + 0.01) {
        return false;
      }
    }
    return true;
  }

  /// Paint that a vector shows as is: no blur, filter or blend.
  static bool _plain(ui.Paint p) =>
      p.blendMode == ui.BlendMode.srcOver &&
      p.maskFilter == null &&
      p.imageFilter == null &&
      p.colorFilter == null &&
      !p.invertColors;

  static ui.Paint _copy(ui.Paint p) => ui.Paint()
    ..color = p.color
    ..blendMode = p.blendMode
    ..style = p.style
    ..strokeWidth = p.strokeWidth
    ..strokeCap = p.strokeCap
    ..strokeJoin = p.strokeJoin
    ..strokeMiterLimit = p.strokeMiterLimit
    ..isAntiAlias = p.isAntiAlias
    ..shader = p.shader
    ..maskFilter = p.maskFilter
    ..filterQuality = p.filterQuality
    ..colorFilter = p.colorFilter
    ..imageFilter = p.imageFilter
    ..invertColors = p.invertColors;

  void _add(Map<String, Object?> node) {
    nodes.add(node);
    if (nodes.length > _maxNodes) whole = true;
  }

  /// Draws [draw] under this layer's opacity.
  void _fade(ui.Canvas canvas, void Function() draw) {
    if (_alpha >= 1) return draw();
    canvas.saveLayer(null, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, _alpha));
    draw();
    canvas.restore();
  }

  /// [draw] replayed alone, as the painter drew it, cropped to [area]
  /// (painter coordinates).
  String _replay(ui.Rect area, void Function(ui.Canvas) draw) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(_scale)
      ..translate(-area.left, -area.top);
    for (final c in _clips) {
      canvas.save();
      canvas.transform(c.matrix);
      c.apply(canvas);
      // Back to painter coordinates, keeping the clip.
      final inverse = r.Matrix4.tryInvert(r.Matrix4.fromFloat64List(c.matrix));
      if (inverse != null) canvas.transform(inverse.storage);
    }
    canvas.transform(_matrix.storage);
    _fade(canvas, () => draw(canvas));
    for (var i = 0; i < _clips.length; i++) {
      canvas.restore();
    }
    return _finish(recorder, area.width, area.height);
  }

  /// Ends [recorder] ([w] × [h] painter units) as one of the recorder's
  /// images, dropped later if nothing in it shows.
  String _finish(ui.PictureRecorder recorder, double w, double h) {
    final id = this.recorder._id();
    this.recorder._maybeEmpty.add(id);
    this.recorder._pending[id] = recorder.endRecording().toImage(
      math.max(1, (w * _scale).ceil()),
      math.max(1, (h * _scale).ceil()),
    );
    return id;
  }

  /// What only pixels show, drawn alone where it may paint ([local], in
  /// the canvas's current coordinates).
  void _pixels(String kind, ui.Rect local, void Function(ui.Canvas) draw) {
    var area = r.MatrixUtils.transformRect(_matrix, local).intersect(_clipBounds);
    area = area.intersect(_everywhere);
    if (area.isEmpty || area.width < 0.01 || area.height < 0.01) return;
    _add({
      'type': 'image',
      'name': kind,
      'local': true,
      'rect': [area.left, area.top, area.width, area.height],
      'image': _replay(area, draw),
      'fit': 'fill',
    });
  }

  void _shape(
    String kind,
    List<_Contour> contours,
    ui.Paint paint,
    void Function(ui.Canvas) draw, {
    bool evenOdd = false,
    bool fillOnly = false,
  }) {
    final stroke = paint.style == ui.PaintingStyle.stroke && !fillOnly;
    final m = _matrix.storage;
    final scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final uniform = (scale - math.sqrt(m[4] * m[4] + m[5] * m[5])).abs() < 1e-6;
    final width = paint.strokeWidth == 0 ? 1.0 : paint.strokeWidth * scale;
    final turned = [for (final c in contours) c.transform(m)];
    final bounds = _Contour.bounds(turned);
    final vector = _affine &&
        _plain(paint) &&
        !(stroke && (paint.shader != null || !uniform)) &&
        bounds != null &&
        _inside(stroke ? bounds.inflate(width / 2) : bounds);
    if (!vector) {
      final local = _Contour.bounds(contours) ?? ui.Rect.zero;
      final sigma = double.tryParse(
            RegExp(r'([\d.]+)\)$').firstMatch(paint.maskFilter?.toString() ?? '')?.group(1) ?? '',
          ) ??
          0;
      final spread = (stroke || paint.strokeWidth > 0 ? paint.strokeWidth / 2 : 0) + sigma * 3 + 2;
      _pixels(kind, fillOnly ? local : local.inflate(spread), draw);
      return;
    }
    final color = paint.color.withValues(alpha: paint.color.a * _alpha);
    if (!stroke && paint.shader == null && color.a == 0) return;
    final node = <String, Object?>{
      'type': 'vector',
      'name': kind,
      'local': true,
      'rect': [bounds!.left, bounds.top, bounds.width, bounds.height],
      'path': _Contour.svg(turned, bounds.topLeft),
      if (evenOdd) 'evenOdd': true,
    };
    if (stroke) {
      node['stroke'] = {'color': _hex(color), 'width': width};
      if (paint.strokeCap != ui.StrokeCap.butt) node['cap'] = paint.strokeCap.name;
    } else if (paint.shader != null) {
      // The shape stays a vector; the shader fills it as an image.
      node['image'] = _replay(bounds, draw);
    } else {
      node['fill'] = _hex(color);
    }
    _add(node);
  }
}

/// A run of path segments: `M`, then `L` and `C` (points are flat
/// `[x, y, ...]`), maybe closed.
class _Contour {
  _Contour(this.start, this.segments, {this.closed = false});

  final ui.Offset start;

  /// `L`: one point; `C`: three.
  final List<List<ui.Offset>> segments;
  final bool closed;

  factory _Contour.rect(ui.Rect r) => _Contour(r.topLeft, [
    [r.topRight],
    [r.bottomRight],
    [r.bottomLeft],
  ], closed: true);

  factory _Contour.line(ui.Offset a, ui.Offset b) => _Contour(a, [
    [b],
  ]);

  /// An elliptical arc of [rect] from [start] for [sweep] radians, as
  /// cubics of at most a quarter turn; through the center when [center].
  factory _Contour.arc(ui.Rect rect, double start, double sweep, {required bool center}) {
    final full = sweep.abs() >= 2 * math.pi - 1e-9;
    if (full) sweep = 2 * math.pi * sweep.sign;
    final c = rect.center;
    final rx = rect.width / 2, ry = rect.height / 2;
    ui.Offset at(double a) => ui.Offset(c.dx + rx * math.cos(a), c.dy + ry * math.sin(a));
    final segments = <List<ui.Offset>>[];
    final count = math.max(1, (sweep.abs() / (math.pi / 2) - 1e-9).ceil());
    final step = sweep / count;
    final k = 4 / 3 * math.tan(step / 4);
    var a = start;
    for (var i = 0; i < count; i++) {
      final b = a + step;
      final p0 = at(a), p3 = at(b);
      segments.add([
        p0 + ui.Offset(-rx * math.sin(a), ry * math.cos(a)) * k,
        p3 - ui.Offset(-rx * math.sin(b), ry * math.cos(b)) * k,
        p3,
      ]);
      a = b;
    }
    if (center && !full) {
      return _Contour(c, [
        [at(start)],
        ...segments,
      ], closed: true);
    }
    return _Contour(at(start), segments, closed: full);
  }

  factory _Contour.rrect(ui.RRect r) {
    if (r.isRect) return _Contour.rect(r.outerRect);
    final segments = <List<ui.Offset>>[];
    void corner(double cx, double cy, double rx, double ry, double from) {
      if (rx <= 0 || ry <= 0) return;
      final arc = _Contour.arc(
        ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2),
        from,
        math.pi / 2,
        center: false,
      );
      segments
        ..add([arc.start])
        ..addAll(arc.segments);
    }

    corner(r.right - r.trRadiusX, r.top + r.trRadiusY, r.trRadiusX, r.trRadiusY, -math.pi / 2);
    if (r.trRadiusX <= 0 || r.trRadiusY <= 0) segments.add([r.outerRect.topRight]);
    corner(r.right - r.brRadiusX, r.bottom - r.brRadiusY, r.brRadiusX, r.brRadiusY, 0);
    if (r.brRadiusX <= 0 || r.brRadiusY <= 0) segments.add([r.outerRect.bottomRight]);
    corner(r.left + r.blRadiusX, r.bottom - r.blRadiusY, r.blRadiusX, r.blRadiusY, math.pi / 2);
    if (r.blRadiusX <= 0 || r.blRadiusY <= 0) segments.add([r.outerRect.bottomLeft]);
    corner(r.left + r.tlRadiusX, r.top + r.tlRadiusY, r.tlRadiusX, r.tlRadiusY, math.pi);
    if (r.tlRadiusX <= 0 || r.tlRadiusY <= 0) segments.add([r.outerRect.topLeft]);
    return _Contour(ui.Offset(r.left + r.tlRadiusX, r.top), segments, closed: true);
  }

  /// A path's contours, traced: every pixel along them, corners found
  /// exactly, then simplified to within 0.05 px.
  static List<_Contour> path(ui.Path path) => [
    for (final metric in path.computeMetrics())
      if (metric.length > 0) _traced(metric),
  ];

  static _Contour _traced(ui.PathMetric metric) {
    final length = metric.length;
    final count = math.max(4, length.ceil());
    final points = <ui.Offset>[];
    ui.Tangent? previous;
    double previousAt = 0;
    for (var i = 0; i <= count; i++) {
      final at = length * i / count;
      final t = metric.getTangentForOffset(at);
      if (t == null) continue;
      if (previous != null && _turn(previous, t) > 0.3) {
        // A corner between the two samples: find where the direction jumps.
        var lo = previousAt, hi = at;
        for (var j = 0; j < 20; j++) {
          final mid = (lo + hi) / 2;
          final m = metric.getTangentForOffset(mid);
          if (m == null) break;
          if (_turn(previous, m) < _turn(m, t)) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        final corner = metric.getTangentForOffset((lo + hi) / 2);
        if (corner != null) points.add(corner.position);
      }
      points.add(t.position);
      previous = t;
      previousAt = at;
    }
    if (metric.isClosed && points.length > 1 && (points.last - points.first).distance < 0.01) {
      points.removeLast();
    }
    // A closed contour's last edge leads back to its start: simplify along
    // it too.
    var kept = _simplify([...points, if (metric.isClosed) points.first], 0.05);
    if (metric.isClosed && kept.length > 1) kept = kept.sublist(0, kept.length - 1);
    return _Contour(kept.first, [
      for (final p in kept.skip(1)) [p],
    ], closed: metric.isClosed);
  }

  static double _turn(ui.Tangent a, ui.Tangent b) {
    var d = (b.angle - a.angle).abs() % (2 * math.pi);
    if (d > math.pi) d = 2 * math.pi - d;
    return d;
  }

  /// Douglas–Peucker.
  static List<ui.Offset> _simplify(List<ui.Offset> points, double tolerance) {
    if (points.length < 3) return points;
    final keep = List<bool>.filled(points.length, false);
    keep[0] = keep[points.length - 1] = true;
    final stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (a, b) = stack.removeLast();
      var worst = 0.0;
      var index = -1;
      final pa = points[a], pb = points[b];
      final d = pb - pa;
      final len = d.distance;
      for (var i = a + 1; i < b; i++) {
        final p = points[i] - pa;
        final dist = len < 1e-9 ? p.distance : (p.dx * d.dy - p.dy * d.dx).abs() / len;
        if (dist > worst) {
          worst = dist;
          index = i;
        }
      }
      if (worst > tolerance && index > 0) {
        keep[index] = true;
        stack
          ..add((a, index))
          ..add((index, b));
      }
    }
    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  /// Through a 2D affine [m] (Matrix4 storage): Béziers stay exact.
  _Contour transform(Float64List m) {
    ui.Offset t(ui.Offset p) => ui.Offset(
      m[0] * p.dx + m[4] * p.dy + m[12],
      m[1] * p.dx + m[5] * p.dy + m[13],
    );
    return _Contour(t(start), [
      for (final s in segments) [for (final p in s) t(p)],
    ], closed: closed);
  }

  /// Tight bounds (curves sampled, not their control points).
  static ui.Rect? bounds(List<_Contour> contours) {
    double? l, t, r2, b;
    void add(ui.Offset p) {
      l = l == null ? p.dx : math.min(l!, p.dx);
      t = t == null ? p.dy : math.min(t!, p.dy);
      r2 = r2 == null ? p.dx : math.max(r2!, p.dx);
      b = b == null ? p.dy : math.max(b!, p.dy);
    }

    for (final c in contours) {
      var from = c.start;
      add(from);
      for (final s in c.segments) {
        if (s.length == 3) {
          for (var i = 1; i <= 16; i++) {
            final u = i / 16, v = 1 - u;
            add(from * (v * v * v) + s[0] * (3 * v * v * u) + s[1] * (3 * v * u * u) + s[2] * (u * u * u));
          }
        } else {
          add(s[0]);
        }
        from = s.last;
      }
    }
    if (l == null) return null;
    return ui.Rect.fromLTRB(l!, t!, r2!, b!);
  }

  /// SVG path data, relative to [origin].
  static String svg(List<_Contour> contours, ui.Offset origin) {
    String n(double v) {
      var s = v.toStringAsFixed(2);
      if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
      return s == '-0' ? '0' : s;
    }

    String p(ui.Offset o) => '${n(o.dx - origin.dx)} ${n(o.dy - origin.dy)}';
    final out = StringBuffer();
    for (final c in contours) {
      out.write('M ${p(c.start)} ');
      for (final s in c.segments) {
        out.write(s.length == 3 ? 'C ${p(s[0])} ${p(s[1])} ${p(s[2])} ' : 'L ${p(s[0])} ');
      }
      if (c.closed) out.write('Z ');
    }
    return out.toString().trim();
  }
}
''';
