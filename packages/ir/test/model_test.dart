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

  test('v2: tokens, instances and design system round-trip', () {
    final doc = IrDocument(
      project: 'demo',
      screens: [
        IrScreen(
          name: 'S',
          width: 390,
          height: 844,
          root: IrFrame(
            name: 'S',
            width: const IrSizing.fixed(390),
            height: const IrSizing.fixed(844),
            fill: IrColor.fromHex('#FEF7FF', token: 'ColorScheme/surface'),
            shadowToken: 'Elevation/level1',
            instance: IrInstanceRef('Card', {'Variant': '1'}),
            children: [
              IrText(
                name: 't',
                text: 't',
                style: IrTextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  color: IrColor.fromHex(
                    '#1D1B20',
                    token: 'ColorScheme/onSurface',
                  ).withAlpha(0.38),
                  token: 'TextTheme/bodyMedium',
                ),
              ),
            ],
          ),
        ),
      ],
      designSystem: IrDesignSystem(
        modes: ['Light', 'Dark'],
        activeMode: 'Dark',
        colors: [
          IrColorToken('ColorScheme/surface', {
            'Light': IrColor.fromHex('#FEF7FF'),
            'Dark': IrColor.fromHex('#141218'),
          }),
        ],
        textStyles: [
          IrTextStyleToken(
            'TextTheme/bodyMedium',
            const IrTextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              color: IrColor.black,
              lineHeight: 20,
            ),
          ),
        ],
        shadows: [
          IrShadowToken('Elevation/level1', const [
            IrShadow(color: IrColor(0, 0, 0, 0.3), y: 1, blur: 2),
          ]),
        ],
        components: [
          IrComponent(
            name: 'Card',
            source: 'lib/card.dart:3',
            variants: [
              IrComponentVariant({'Variant': '1'}, uses: 2),
            ],
          ),
        ],
      ),
    );
    final json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>;
    expect(json['version'], 2);
    final again = IrDocument.fromJson(json);
    expect(jsonEncode(again.toJson()), jsonEncode(doc.toJson()));
    final text = (again.screens.single.root.children.single as IrText).style;
    expect(text.color.token, 'ColorScheme/onSurface');
    expect(text.color.a, closeTo(0.38, 0.01));
  });

  test('instance keys and variant names', () {
    final ref = IrInstanceRef('Button', {'Type': 'Filled', 'State': 'Enabled'});
    expect(ref.variantName, 'Type=Filled, State=Enabled');
    expect(ref.key, 'Button[Type=Filled, State=Enabled]');
    expect(IrInstanceRef('StatCard').key, 'StatCard');
  });
}
