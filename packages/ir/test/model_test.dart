import 'dart:convert';

import 'package:flutter2figma_ir/flutter2figma_ir.dart';
import 'package:test/test.dart';

void main() {
  test('document round-trips through JSON', () {
    final doc = IrDocument(
      project: 'demo',
      screens: [
        IrScreen(
          name: 'Home',
          width: 390,
          height: 844,
          source: 'lib/home.dart:3',
          root: IrFrame(
            name: 'Home',
            role: 'screen',
            width: const IrSizing.fixed(390),
            height: const IrSizing.fixed(844),
            fill: IrColor.fromHex('#FEF7FF'),
            padding: const IrInsets.all(24),
            gap: 16,
            children: [
              IrText(
                name: 'Welcome',
                text: 'Welcome',
                origin: ['Text'],
                style: const IrTextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 32,
                  fontWeight: 700,
                  color: IrColor(0.1, 0.1, 0.1),
                  lineHeight: 40,
                ),
              ),
              IrFrame(
                name: 'Box',
                width: const IrSizing.fill(),
                corners: const IrCorners(topLeft: 4, topRight: 4),
                stroke: const IrStroke(color: IrColor.black, width: 2),
                shadows: const [
                  IrShadow(color: IrColor(0, 0, 0, 0.2), y: 1, blur: 3),
                ],
                position: const IrPosition(left: 8, top: 8),
              ),
            ],
          ),
        ),
      ],
      diagnostics: const [
        IrDiagnostic(
          IrSeverity.warning,
          'Unsupported widget: Foo',
          source: 'lib/home.dart:9',
        ),
      ],
    );

    final json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>;
    final again = IrDocument.fromJson(json);
    expect(jsonEncode(again.toJson()), jsonEncode(doc.toJson()));
  });

  test('color hex', () {
    expect(IrColor.fromArgb32(0xFF2196F3).toHex(), '#2196F3');
    expect(IrColor.fromArgb32(0x802196F3).toHex(), '#2196F380');
    expect(IrColor.fromHex('#2196F380'), IrColor.fromArgb32(0x802196F3));
  });

  test('rejects foreign documents', () {
    expect(
      () => IrDocument.fromJson({'format': 'other'}),
      throwsFormatException,
    );
  });
}
