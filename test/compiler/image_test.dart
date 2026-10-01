import 'dart:io';
import 'dart:typed_data';

import 'package:flutter2figma/analyzer.dart';
import 'package:flutter2figma/compiler.dart';
import 'package:flutter2figma/ir.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'builders.dart';

/// Just enough of a PNG for its header: signature and IHDR size.
Uint8List png(int width, int height) {
  final d = ByteData(33);
  [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].asMap().forEach(d.setUint8);
  d
    ..setUint32(8, 13)
    ..setUint32(12, 0x49484452) // IHDR
    ..setUint32(16, width)
    ..setUint32(20, height);
  return d.buffer.asUint8List();
}

/// SOI, an APP0 segment, then a baseline frame header.
Uint8List jpeg(int width, int height) => Uint8List.fromList([
  0xFF, 0xD8, //
  0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00,
  0xFF, 0xC0, 0x00, 0x11, 0x08,
  height >> 8, height & 0xFF, width >> 8, width & 0xFF,
  0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);

void main() {
  late Directory dir;
  late ProjectAssets assets;

  void write(String path, List<int> bytes) => (File(
    p.join(dir.path, path),
  )..createSync(recursive: true)).writeAsBytesSync(bytes);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('f2f_assets');
    write('assets/logo.png', png(48, 24));
    write('assets/2.0x/logo.png', png(96, 48));
    write('assets/3.0x/logo.png', png(144, 72));
    write('assets/only3x/3.0x/icon.png', png(30, 30));
    write('assets/photo.jpg', jpeg(640, 480));
    write('assets/huge.png', img.encodePng(img.Image(width: 5000, height: 10)));
    write('assets/old.bmp', img.encodeBmp(img.Image(width: 8, height: 4)));
    write('assets/vector.svg', '<svg width="32" height="16"></svg>'.codeUnits);
    write('assets/box.svg', '<svg viewBox="0 0 10 20"></svg>'.codeUnits);
    write('assets/notes.txt', 'hello'.codeUnits);
    assets = ProjectAssets(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('ProjectAssets', () {
    test('scales images down to Figma\'s limit and converts other formats', () {
      final huge = assets.resolve('assets/huge.png').asset!;
      expect([huge.width, huge.height], [5000, 10]); // logical size kept
      final decoded = img.decodePng(huge.data)!;
      expect([decoded.width, decoded.height], [4096, 8]);

      final bmp = assets.resolve('assets/old.bmp').asset!;
      expect([bmp.format, bmp.width, bmp.height], ['png', 8, 4]);
    });

    test('uses the highest resolution variant at its logical size', () {
      final logo = assets.resolve('assets/logo.png').asset!;
      expect([logo.width, logo.height], [48, 24]);
      expect(logo.data.length, png(144, 72).length);
      final icon = assets.resolve('assets/only3x/icon.png').asset!;
      expect([icon.width, icon.height], [10, 10]);
    });

    test('identifies JPEG and SVG sizes', () {
      final photo = assets.resolve('assets/photo.jpg').asset!;
      expect([photo.format, photo.width, photo.height], ['jpeg', 640, 480]);
      final vector = assets.resolve('assets/vector.svg').asset!;
      expect([vector.format, vector.width, vector.height], ['svg', 32, 16]);
      final box = assets.resolve('assets/box.svg').asset!;
      expect([box.width, box.height], [10, 20]);
    });

    test('explains what it cannot embed', () {
      expect(
        assets.resolve('assets/missing.png').problem,
        contains('not found'),
      );
      expect(
        assets.resolve('assets/notes.txt').problem,
        contains('not an image'),
      );
    });
  });

  group('compiler', () {
    IrFrame image(DartValue widget) {
      final compiler = FlutterCompiler(assets: assets);
      final doc = compiler.compileScreen(
        'Test',
        w(
          'Scaffold',
          named: {
            'body': w('Center', named: {'child': widget}),
          },
        ),
        null,
      );
      var node = doc.root.children.single;
      while (node is IrFrame &&
          node.image == null &&
          node.children.length == 1) {
        node = node.children.single;
      }
      return node as IrFrame;
    }

    ObjectValue asset(String name, {Map<String, DartValue> named = const {}}) =>
        w('Image', ctor: 'asset', positional: [lit(name)], named: named);

    test('Image.asset takes its intrinsic logical size', () {
      final frame = image(asset('assets/logo.png'));
      expect(frame.name, 'Image/logo.png');
      expect(
        [frame.width, frame.height],
        [const IrSizing.fixed(48), const IrSizing.fixed(24)],
      );
      expect(frame.image!.asset, 'assets/logo.png');
      expect(frame.image!.fit, IrBoxFit.scaleDown);
      expect(frame.fill, isNull);
    });

    test('one given side keeps the aspect ratio; fit is read', () {
      final frame = image(
        asset(
          'assets/photo.jpg',
          named: {'width': lit(320), 'fit': ref('BoxFit.cover')},
        ),
      );
      expect(
        [frame.width, frame.height],
        [const IrSizing.fixed(320), const IrSizing.fixed(240)],
      );
      expect(frame.image!.fit, IrBoxFit.cover);
    });

    test('Image(image: AssetImage(...)) and SVGs', () {
      final provided = image(
        w(
          'Image',
          named: {
            'image': v('AssetImage', positional: [lit('assets/logo.png')]),
          },
        ),
      );
      expect(provided.image!.asset, 'assets/logo.png');
      final svg = image(
        w('SvgPicture', ctor: 'asset', positional: [lit('assets/vector.svg')]),
      );
      expect(svg.image!.fit, IrBoxFit.contain);
    });

    test('network images and missing assets are placeholders', () {
      final network = image(
        w('Image', ctor: 'network', positional: [lit('https://x.dev/a.png')]),
      );
      expect(network.name, 'Image/a.png');
      expect(network.image, isNull);
      expect(network.fill, isNotNull);
      expect(image(asset('assets/missing.png')).image, isNull);
    });

    test('DecorationImage paints its box', () {
      final box = image(
        w(
          'Container',
          named: {
            'width': lit(64),
            'height': lit(64),
            'decoration': v(
              'BoxDecoration',
              named: {
                'image': v(
                  'DecorationImage',
                  named: {
                    'image': v(
                      'AssetImage',
                      positional: [lit('assets/photo.jpg')],
                    ),
                    'fit': ref('BoxFit.cover'),
                  },
                ),
              },
            ),
          },
        ),
      );
      expect(box.image!.asset, 'assets/photo.jpg');
      expect(box.image!.fit, IrBoxFit.cover);
    });
  });
}
