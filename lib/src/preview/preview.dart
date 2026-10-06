import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../runtime/runtime_capture.dart' show flutterSdkRoot;
import 'preview_template.dart';

/// An HTML page that shows each screen of a `design.json` as a browser draws
/// it, beside Flutter's own render when there is one ([screenshots], PNG by
/// screen name): a quick check of an export without opening Figma.
///
/// Frames become absolutely positioned boxes or CSS flex (Figma auto layout
/// and flex follow the same rules), text keeps its font and metrics, vectors
/// are inline SVG, and gradients, shadows and blurs map to their CSS
/// equivalents. [fonts] (family → weight → font file bytes) are embedded so
/// text measures as in the app. It is the browser's reading of the file, not
/// Figma's.
String previewPage({
  required Map<String, Object?> design,
  required String title,
  Map<String, List<int>> screenshots = const {},
  Map<String, Map<int, List<int>>> fonts = const {},
}) => _Preview(design, screenshots).page(title, fonts);

/// The fonts a Flutter project bundles (from `pubspec.yaml`), plus Roboto
/// from its Flutter SDK, for [previewPage]: family → weight → file.
Map<String, Map<int, File>> projectFontFiles(String root) {
  final fonts = <String, Map<int, File>>{};
  final sdk = flutterSdkRoot(root);
  if (sdk != null) {
    final dir = Directory(
      p.join(sdk, 'bin', 'cache', 'artifacts', 'material_fonts'),
    );
    for (final MapEntry(key: name, value: weight) in _weights.entries) {
      final file = File(p.join(dir.path, 'Roboto-$name.ttf'));
      if (file.existsSync()) (fonts['Roboto'] ??= {})[weight] = file;
    }
  }
  try {
    final yaml = loadYaml(
      File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
    );
    final flutter = yaml is YamlMap ? yaml['flutter'] : null;
    final families = flutter is YamlMap ? flutter['fonts'] : null;
    for (final family in families is YamlList ? families : const []) {
      if (family is! YamlMap || family['family'] is! String) continue;
      for (final font
          in family['fonts'] is YamlList
              ? family['fonts'] as YamlList
              : const []) {
        if (font is! YamlMap || font['asset'] is! String) continue;
        if (font['style'] == 'italic') continue;
        final file = File(p.join(root, font['asset'] as String));
        if (!file.existsSync()) continue;
        (fonts[family['family'] as String] ??= {})[(font['weight'] as int?) ??
                400] =
            file;
      }
    }
  } on Exception {
    // No pubspec fonts.
  }
  return fonts;
}

/// Font files for the families and weights [design] uses, read from
/// [files] (see [projectFontFiles]): the nearest weight each family has.
Map<String, Map<int, List<int>>> usedFonts(
  Map<String, Object?> design,
  Map<String, Map<int, File>> files,
) {
  final out = <String, Map<int, List<int>>>{};
  for (final f in (design['fonts'] as List? ?? const []).cast<Map>()) {
    final available = files[f['family']];
    if (available == null || available.isEmpty) continue;
    final want = _weight(f['style'] as String? ?? 'Regular');
    final nearest = available.keys.reduce(
      (a, b) => (a - want).abs() <= (b - want).abs() ? a : b,
    );
    (out[f['family'] as String] ??= {})[nearest] ??= available[nearest]!
        .readAsBytesSync();
  }
  return out;
}

/// Flutter's render at 2x, halved: the page shows phones at 1x or less.
List<int> halfSize(List<int> png) {
  final image = img.decodePng(png as dynamic);
  if (image == null) return png;
  return img.encodePng(
    img.copyResize(
      image,
      width: image.width ~/ 2,
      interpolation: img.Interpolation.average,
    ),
  );
}

const _weights = {
  'Thin': 100,
  'ExtraLight': 200,
  'Light': 300,
  'Regular': 400,
  'Medium': 500,
  'SemiBold': 600,
  'Bold': 700,
  'ExtraBold': 800,
  'Black': 900,
};

int _weight(String style) =>
    _weights[style.replaceAll('Italic', '').trim()] ?? 400;

String _esc(String s) => const HtmlEscape().convert(s);

String _n(num v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

class _Preview {
  _Preview(this.design, this.screenshots)
    : images = (design['images'] as Map? ?? const {})
          .cast<String, Map<String, Object?>>();

  final Map<String, Object?> design;
  final Map<String, List<int>> screenshots;
  final Map<String, Map<String, Object?>> images;
  var _patterns = 0;

  String page(String title, Map<String, Map<int, List<int>>> fonts) {
    final faces = StringBuffer();
    for (final MapEntry(key: family, value: weights) in fonts.entries) {
      for (final MapEntry(key: weight, value: bytes) in weights.entries) {
        faces.writeln(
          "@font-face{font-family:'f2f-$family';font-weight:$weight;"
          "src:url(data:font/ttf;base64,${base64Encode(bytes)}) "
          "format('truetype')}",
        );
      }
    }
    final screens = (design['screens'] as List).cast<Map<String, Object?>>();
    final total = _Counts();
    final sections = StringBuffer();
    for (final s in screens) {
      final counts = _Counts()..add(s);
      total.merge(counts);
      sections.write(_section(s, counts));
    }
    final rendered = screens
        .where((s) => screenshots.containsKey(s['name']))
        .length;
    return previewTemplate
        .replaceAll('{{TITLE}}', _esc(title))
        .replaceFirst('/*FACES*/', faces.toString())
        .replaceFirst('<!--SECTIONS-->', sections.toString())
        .replaceFirst(
          '{{FLUTTER}}',
          screenshots.isEmpty
              ? ''
              : 'Each screen as Flutter rendered it, beside the export. ',
        )
        .replaceFirst('{{SCREENS}}', '${screens.length}')
        .replaceFirst('{{RENDERED}}', '$rendered')
        .replaceFirst('{{VECTORS}}', '${total.vectors}')
        .replaceFirst('{{TEXTS}}', '${total.texts}')
        .replaceFirst('{{IMAGES}}', '${total.images}')
        .replaceAll('{{WIPE}}', screenshots.isEmpty ? 'hidden' : '');
  }

  String _section(Map<String, Object?> s, _Counts counts) {
    final name = s['name'] as String;
    final slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9_-]'), '-');
    final shot = screenshots[name];
    final flutter = shot == null
        ? null
        : '<img class="shot" alt="Flutter render of ${_esc(name)}" '
              'src="data:image/png;base64,${base64Encode(shot)}">';
    final export = _node(
      {...s}
        ..remove('x')
        ..remove('y'),
      null,
    );
    final pair = StringBuffer('<div class="pair">');
    if (flutter != null) {
      pair.write(
        '<figure class="phone-col"><figcaption>Flutter</figcaption>'
        '<div class="phone">$flutter</div></figure>',
      );
    }
    pair.write(
      '<figure class="phone-col export-col"><figcaption>Export '
      '<span>design.json</span></figcaption><div class="phone">'
      '<div class="canvas">$export</div></div></figure></div>',
    );
    if (flutter != null) {
      pair.write(
        '<div class="wipe-control"><label for="w-$slug">Flutter</label>'
        '<input class="wipe-range" id="w-$slug" type="range" min="0" '
        'max="100" value="50" aria-label="Wipe between Flutter and export">'
        '<label for="w-$slug">Export</label></div>',
      );
    }
    return '''
<section class="screen" id="$slug">
  <header class="screen-head">
    <h2>${_esc(name)}</h2>
    <ul class="chips">
      <li class="chip chip-v"><b>${counts.vectors}</b> vector</li>
      <li class="chip chip-t"><b>${counts.texts}</b> text</li>
      <li class="chip chip-i"><b>${counts.images}</b> image</li>
      ${screenshots.isNotEmpty && flutter == null ? '<li class="chip chip-s">static</li>' : ''}
    </ul>
  </header>
  $pair
</section>''';
  }

  // --- Nodes ---------------------------------------------------------------

  String _node(Map<String, Object?> n, Map<String, Object?>? parent) {
    final kind = n['type'];
    final style = StringBuffer();
    final flexParent =
        parent != null &&
        (parent['layoutMode'] == 'HORIZONTAL' ||
            parent['layoutMode'] == 'VERTICAL');
    final absolute =
        parent == null || !flexParent || n['layoutPositioning'] == 'ABSOLUTE';
    final w = n['width'] as num?, h = n['height'] as num?;
    final sh = n['layoutSizingHorizontal'], sv = n['layoutSizingVertical'];
    if (parent == null) {
      style.write('position:relative;width:${w}px;height:${h}px;');
    } else if (absolute) {
      final pos = (n['position'] as Map?)?.cast<String, Object?>() ?? const {};
      style.write('position:absolute;');
      for (final (size, start, end, length, prop) in [
        (sh, 'left', 'right', w, 'width'),
        (sv, 'top', 'bottom', h, 'height'),
      ]) {
        if (size == 'FILL' && !flexParent) {
          style.write('$start:${pos[start] ?? 0}px;$end:${pos[end] ?? 0}px;');
          continue;
        }
        if (pos.containsKey(start)) {
          style.write('$start:${pos[start]}px;');
        } else if (pos.containsKey(end)) {
          style.write('$end:${pos[end]}px;');
        }
        if (size == 'FIXED' && length != null) {
          style.write('$prop:${length}px;');
        }
      }
    } else {
      final row = parent['layoutMode'] == 'HORIZONTAL';
      final (main, cross) = row ? (sh, sv) : (sv, sh);
      final (mainLength, crossLength) = row ? (w, h) : (h, w);
      final (mainProp, crossProp) = row
          ? ('width', 'height')
          : ('height', 'width');
      style.write('position:relative;');
      if (main == 'FILL') {
        style.write('flex:1 1 0;min-$mainProp:0;');
      } else {
        style.write('flex:none;');
        if (main == 'FIXED' && mainLength != null) {
          style.write('$mainProp:${mainLength}px;');
        }
      }
      if (cross == 'FILL') {
        style.write('align-self:stretch;');
      } else if (cross == 'FIXED' && crossLength != null) {
        style.write('$crossProp:${crossLength}px;');
      }
    }
    if (n['rotation'] case final num r when r != 0) {
      style.write('transform:rotate(${r}deg);transform-origin:0 0;');
    }
    return switch (kind) {
      'TEXT' => _text(n, style),
      'VECTOR' => _vector(n, style, w, h),
      _ => _frame(n, style, w, h),
    };
  }

  String _text(Map<String, Object?> n, StringBuffer style) {
    final fills = (n['fills'] as List? ?? const []).cast<Map>();
    final fill = fills.isEmpty ? null : fills.first;
    final color = fill?['color'] == null
        ? '#000'
        : _rgba(fill!['color'] as Map, fill['opacity'] as num? ?? 1);
    final font = n['fontName'] as Map;
    final lh = n['lineHeight'] as Map;
    final ls = n['letterSpacing'] as Map;
    final wrap = n['layoutSizingHorizontal'] != 'HUG';
    style.write(
      "font-family:'f2f-${font['family']}',sans-serif;"
      'font-weight:${_weight(font['style'] as String)};'
      'font-size:${n['fontSize']}px;'
      'line-height:${lh['unit'] == 'PIXELS' ? '${lh['value']}px' : 'normal'};'
      'letter-spacing:${ls['value']}px;color:$color;'
      'text-align:${switch (n['textAlignHorizontal']) {
        'CENTER' => 'center',
        'RIGHT' => 'right',
        'JUSTIFIED' => 'justify',
        _ => 'left',
      }};'
      'white-space:${wrap ? 'pre-wrap' : 'pre'};',
    );
    if (n['maxLines'] case final int lines) {
      style.write(
        'display:-webkit-box;-webkit-box-orient:vertical;'
        '-webkit-line-clamp:$lines;overflow:hidden;',
      );
    }
    return '<div class="n nt" style="$style">'
        '${_esc(n['characters'] as String? ?? '')}</div>';
  }

  String _vector(Map<String, Object?> n, StringBuffer style, num? w, num? h) {
    final defs = StringBuffer(), paths = StringBuffer();
    var image = false;
    final fills = (n['fills'] as List? ?? const []).cast<Map>();
    final strokes = (n['strokes'] as List? ?? const []).cast<Map>();
    for (final vp in (n['vectorPaths'] as List).cast<Map>()) {
      final rule = vp['windingRule'] == 'EVENODD' ? 'evenodd' : 'nonzero';
      for (final f in fills) {
        String paint;
        if (f['type'] == 'SOLID') {
          paint = _rgba(f['color'] as Map, f['opacity'] as num? ?? 1);
        } else if (f['type'] == 'IMAGE') {
          image = true;
          final id = 'p${_patterns++}';
          defs.write(
            '<pattern id="$id" patternUnits="userSpaceOnUse" width="$w" '
            'height="$h"><image href="${_imageUrl(f['image'] as String)}" '
            'width="$w" height="$h" preserveAspectRatio="none"/></pattern>',
          );
          paint = 'url(#$id)';
        } else {
          continue;
        }
        paths.write(
          '<path d="${vp['data']}" fill="$paint" fill-rule="$rule"/>',
        );
      }
      for (final s in strokes) {
        final cap = switch (n['strokeCap']) {
          'ROUND' => 'round',
          'SQUARE' => 'square',
          _ => 'butt',
        };
        paths.write(
          '<path d="${vp['data']}" fill="none" '
          'stroke="${_rgba(s['color'] as Map, s['opacity'] as num? ?? 1)}" '
          'stroke-width="${n['strokeWeight'] ?? 1}" stroke-linecap="$cap"/>',
        );
      }
    }
    style.write('overflow:visible;display:block;');
    return '<svg class="n nv${image ? ' ni' : ''}" style="$style" '
        'width="$w" height="$h" viewBox="0 0 $w $h"><defs>$defs</defs>'
        '$paths</svg>';
  }

  String _frame(Map<String, Object?> n, StringBuffer style, num? w, num? h) {
    final mode = n['layoutMode'];
    style.write('box-sizing:border-box;');
    if (mode == 'HORIZONTAL' || mode == 'VERTICAL') {
      style.write(
        'display:flex;flex-direction:${mode == 'HORIZONTAL' ? 'row' : 'column'};'
        'gap:${n['itemSpacing'] ?? 0}px;'
        'padding:${n['paddingTop'] ?? 0}px ${n['paddingRight'] ?? 0}px '
        '${n['paddingBottom'] ?? 0}px ${n['paddingLeft'] ?? 0}px;'
        'justify-content:${switch (n['primaryAxisAlignItems']) {
          'CENTER' => 'center',
          'MAX' => 'flex-end',
          'SPACE_BETWEEN' => 'space-between',
          _ => 'flex-start',
        }};'
        'align-items:${switch (n['counterAxisAlignItems']) {
          'CENTER' => 'center',
          'MAX' => 'flex-end',
          'BASELINE' => 'baseline',
          _ => 'flex-start',
        }};',
      );
      if (n['layoutWrap'] == 'WRAP') {
        style.write(
          'flex-wrap:wrap;row-gap:${n['counterAxisSpacing'] ?? 0}px;',
        );
      }
    }
    final fills = (n['fills'] as List? ?? const []).cast<Map>();
    final (background, layers) = _backgrounds(fills);
    style.write(background);
    if (n['cornerRadius'] case final num r) {
      style.write('border-radius:${r}px;');
    } else if (n['topLeftRadius'] != null) {
      style.write(
        'border-radius:${n['topLeftRadius']}px ${n['topRightRadius']}px '
        '${n['bottomRightRadius']}px ${n['bottomLeftRadius']}px;',
      );
    }
    final shadows = <String>[];
    for (final e in (n['effects'] as List? ?? const []).cast<Map>()) {
      if (e['visible'] == false) continue;
      if (e['type'] == 'DROP_SHADOW') {
        final o = e['offset'] as Map;
        shadows.add(
          '${o['x']}px ${o['y']}px ${e['radius']}px ${e['spread'] ?? 0}px '
          '${_rgba(e['color'] as Map)}',
        );
      } else if (e['type'] == 'BACKGROUND_BLUR') {
        // Figma's radius is twice the CSS blur's standard deviation.
        final blur = _n((e['radius'] as num) / 2);
        style.write(
          'backdrop-filter:blur(${blur}px);-webkit-backdrop-filter:blur(${blur}px);',
        );
      }
    }
    for (final s in (n['strokes'] as List? ?? const []).cast<Map>()) {
      shadows.add(
        'inset 0 0 0 ${n['strokeWeight'] ?? 1}px '
        '${_rgba(s['color'] as Map, s['opacity'] as num? ?? 1)}',
      );
    }
    if (shadows.isNotEmpty) style.write('box-shadow:${shadows.join(',')};');
    if (n['clipsContent'] == true) style.write('overflow:hidden;');
    final image = fills.any((f) => f['type'] == 'IMAGE');
    final svg = n['svg'] as Map?;
    final inner = StringBuffer();
    if (svg != null) {
      inner.write(
        '<img style="position:absolute;inset:0;width:100%;height:100%;'
        'object-fit:${svg['scaleMode'] == 'FILL' ? 'cover' : 'contain'}" '
        'alt="" src="${_imageUrl(svg['image'] as String)}">',
      );
    }
    for (final c
        in (n['children'] as List? ?? const []).cast<Map<String, Object?>>()) {
      inner.write(_node(c, n));
    }
    return '<div class="n nf${image || svg != null ? ' ni' : ''}" '
        'style="$style"${layers == null ? '' : ' data-bg="$layers"'}>'
        '$inner</div>';
  }

  // --- Paint ---------------------------------------------------------------

  String _rgba(Map c, [num opacity = 1]) {
    int ch(Object? v) => ((v as num) * 255).round();
    final a = ((c['a'] as num?) ?? 1) * opacity;
    return 'rgba(${ch(c['r'])},${ch(c['g'])},${ch(c['b'])},${_n(a)})';
  }

  String _imageUrl(String key) {
    final a = images[key];
    if (a == null) return '';
    final format = a['format'] as String;
    final mime = switch (format) {
      'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'svg' => 'image/svg+xml',
      _ => 'image/png',
    };
    final data = format == 'svg'
        ? base64Encode(utf8.encode(a['data'] as String))
        : a['data'] as String;
    return 'data:$mime;base64,$data';
  }

  /// The fills as CSS backgrounds. Gradients depend on the box's size,
  /// which a frame that fills or hugs only gets in the browser: those are
  /// drawn by the page's script (`data-bg`), with the same layers.
  (String, String?) _backgrounds(List<Map> fills) {
    final layers = <Map<String, Object?>>[];
    // Figma paints the last fill on top; CSS the first.
    for (final f in fills.reversed) {
      if (f['visible'] == false) continue;
      switch (f['type']) {
        case 'SOLID':
          final c = _rgba(f['color'] as Map, f['opacity'] as num? ?? 1);
          layers.add({'css': 'linear-gradient($c,$c)', 'size': 'auto'});
        case 'IMAGE':
          layers.add({
            'css': 'url(${_imageUrl(f['image'] as String)})',
            'size': switch (f['scaleMode']) {
              'FILL' => 'cover',
              'FIT' => 'contain',
              'CROP' => '100% 100%',
              _ => 'auto',
            },
          });
        case final String t when t.startsWith('GRADIENT'):
          layers.add({'gradient': f, 'size': 'auto'});
      }
    }
    if (layers.isEmpty) return ('', null);
    if (layers.any((l) => l.containsKey('gradient'))) {
      return ('', _esc(jsonEncode(layers)));
    }
    return (
      'background-image:${layers.map((l) => l['css']).join(',')};'
          'background-size:${layers.map((l) => l['size']).join(',')};'
          'background-position:center;background-repeat:no-repeat;',
      null,
    );
  }
}

/// Layers by what they are in Figma.
class _Counts {
  int vectors = 0, texts = 0, images = 0;

  void add(Map<String, Object?> n) {
    switch (n['type']) {
      case 'TEXT':
        texts++;
      case 'VECTOR':
        vectors++;
      default:
        if ((n['fills'] as List? ?? const []).cast<Map>().any(
          (f) => f['type'] == 'IMAGE',
        )) {
          images++;
        }
    }
    for (final c
        in (n['children'] as List? ?? const []).cast<Map<String, Object?>>()) {
      add(c);
    }
  }

  void merge(_Counts o) {
    vectors += o.vectors;
    texts += o.texts;
    images += o.images;
  }
}
