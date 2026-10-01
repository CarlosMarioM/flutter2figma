import 'package:flutter2figma/figma.dart';
import 'package:flutter2figma/ir.dart';
import 'package:test/test.dart';

const _style = IrTextStyle(
  fontFamily: 'Roboto',
  fontSize: 14,
  color: IrColor.black,
);

Map<String, Object?> render(IrFrame root) => FigmaRenderer().render(
  IrDocument(
    project: 'demo',
    screens: [IrScreen(name: 'S', width: 390, height: 844, root: root)],
  ),
);

Map<String, Object?> screenOf(Map<String, Object?> design) =>
    (design['screens'] as List).single as Map<String, Object?>;

List<Map<String, Object?>> childrenOf(Map<String, Object?> node) =>
    (node['children'] as List).cast<Map<String, Object?>>();

void main() {
  test('maps frames to auto layout with Figma enums', () {
    final design = render(
      IrFrame(
        name: 'S',
        role: 'screen',
        width: const IrSizing.fixed(390),
        height: const IrSizing.fixed(844),
        children: [
          IrFrame(
            name: 'Row',
            direction: IrLayoutDirection.horizontal,
            width: const IrSizing.fill(),
            mainAlign: IrMainAlign.spaceBetween,
            crossAlign: IrCrossAlign.center,
            gap: 8,
            padding: const IrInsets.symmetric(horizontal: 16),
            fill: IrColor.fromHex('#2196F380'),
            corners: const IrCorners(topLeft: 4),
            stroke: const IrStroke(color: IrColor.black, width: 2),
            shadows: const [
              IrShadow(color: IrColor(0, 0, 0, 0.3), y: 1, blur: 2),
            ],
          ),
        ],
      ),
    );
    expect(design['format'], 'flutter2figma/design');
    final screen = screenOf(design);
    expect(screen['layoutSizingHorizontal'], 'FIXED');
    expect(screen['width'], 390);
    expect((screen['pluginData'] as Map)['role'], 'screen');

    final row = childrenOf(screen).single;
    expect(row['layoutMode'], 'HORIZONTAL');
    expect(row['primaryAxisAlignItems'], 'SPACE_BETWEEN');
    expect(row['counterAxisAlignItems'], 'CENTER');
    expect(row['itemSpacing'], 8);
    expect(row['paddingLeft'], 16);
    expect(row['layoutSizingHorizontal'], 'FILL');
    expect(row['layoutSizingVertical'], 'HUG');
    expect(row['fills'], [
      {
        'type': 'SOLID',
        'color': {'r': 0x21 / 255, 'g': 0x96 / 255, 'b': 0xF3 / 255},
        'opacity': 0x80 / 255,
      },
    ]);
    expect(row['topLeftRadius'], 4);
    expect(row['bottomRightRadius'], 0);
    expect(row['strokeWeight'], 2);
    expect(
      (row['effects'] as List).single,
      containsPair('type', 'DROP_SHADOW'),
    );
  });

  test('text: font style names, line height, auto resize', () {
    final design = render(
      IrFrame(
        name: 'S',
        width: const IrSizing.fixed(390),
        height: const IrSizing.fixed(844),
        children: [
          IrText(
            name: 'Title',
            text: 'Title',
            width: const IrSizing.fill(),
            style: const IrTextStyle(
              fontFamily: 'Roboto',
              fontSize: 22,
              fontWeight: 600,
              italic: true,
              color: IrColor.black,
              lineHeight: 28,
            ),
          ),
          IrText(name: 'Body', text: 'Body', style: _style),
        ],
      ),
    );
    final [title, body] = childrenOf(screenOf(design));
    expect(title['fontName'], {'family': 'Roboto', 'style': 'SemiBold Italic'});
    expect(title['lineHeight'], {'unit': 'PIXELS', 'value': 28});
    expect(title['textAutoResize'], 'HEIGHT');
    expect(body['lineHeight'], {'unit': 'AUTO'});
    expect(body['textAutoResize'], 'WIDTH_AND_HEIGHT');
    expect(design['fonts'], [
      {'family': 'Roboto', 'style': 'SemiBold Italic'},
      {'family': 'Roboto', 'style': 'Regular'},
    ]);
  });

  test('downgrades combinations Figma rejects, with a warning', () {
    final design = render(
      IrFrame(
        name: 'S',
        width: const IrSizing.fixed(390),
        height: const IrSizing.fixed(844),
        children: [
          IrFrame(
            name: 'Hugging',
            children: [
              IrText(
                name: 'Wide',
                text: 'Wide',
                style: _style,
                width: const IrSizing.fill(),
              ),
            ],
          ),
          IrFrame(name: 'Stack', direction: IrLayoutDirection.stack),
        ],
      ),
    );
    final [hugging, stack] = childrenOf(screenOf(design));
    expect(childrenOf(hugging).single['layoutSizingHorizontal'], 'HUG');
    expect(stack['layoutMode'], 'NONE');
    expect(stack['layoutSizingHorizontal'], 'FIXED');
    expect((design['diagnostics'] as List).map((d) => (d as Map)['message']), [
      'Wide: fills a parent that hugs its content; using hug',
      'Stack: absolute-layout frames cannot hug; using fixed',
      'Stack: absolute-layout frames cannot hug; using fixed',
    ]);
  });

  test('absolute children inside auto layout', () {
    final design = render(
      IrFrame(
        name: 'S',
        width: const IrSizing.fixed(390),
        height: const IrSizing.fixed(844),
        children: [
          IrFrame(
            name: 'Fab',
            width: const IrSizing.fixed(56),
            height: const IrSizing.fixed(56),
            position: const IrPosition(right: 16, bottom: 16),
          ),
        ],
      ),
    );
    final fab = childrenOf(screenOf(design)).single;
    expect(fab['layoutPositioning'], 'ABSOLUTE');
    expect(fab['position'], {'right': 16, 'bottom': 16});
  });

  test('screens are laid out left to right', () {
    IrScreen s(String name) => IrScreen(
      name: name,
      width: 390,
      height: 844,
      root: IrFrame(
        name: name,
        width: const IrSizing.fixed(390),
        height: const IrSizing.fixed(844),
      ),
    );
    final design = FigmaRenderer().render(
      IrDocument(project: 'p', screens: [s('A'), s('B')]),
    );
    final xs = (design['screens'] as List).map((n) => (n as Map)['x']);
    expect(xs, [0, 510]);
  });

  test('figmaFontStyle', () {
    expect(figmaFontStyle(400), 'Regular');
    expect(figmaFontStyle(400, italic: true), 'Italic');
    expect(figmaFontStyle(700), 'Bold');
    expect(figmaFontStyle(550), 'SemiBold');
    expect(figmaFontStyle(900, italic: true), 'Black Italic');
  });

  test('design system: variables, styles, components, bindings', () {
    final primary = IrColor.fromHex('#6750A4', token: 'ColorScheme/primary');
    const labelStyle = IrTextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      fontWeight: 500,
      color: IrColor.white,
      lineHeight: 20,
      token: 'TextTheme/labelLarge',
    );
    final button = IrFrame(
      name: 'FilledButton',
      instance: IrInstanceRef('Button', {'Type': 'Filled', 'State': 'Enabled'}),
      fill: primary.withAlpha(0.5),
      shadows: const [IrShadow(color: IrColor(0, 0, 0, 0.3), y: 1, blur: 2)],
      shadowToken: 'Elevation/level1',
      children: [IrText(name: 'Go', text: 'Go', style: labelStyle)],
    );
    final design = FigmaRenderer().render(
      IrDocument(
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
              children: [button],
            ),
          ),
        ],
        designSystem: IrDesignSystem(
          modes: ['Light', 'Dark'],
          activeMode: 'Light',
          colors: [
            IrColorToken('ColorScheme/primary', {
              'Light': IrColor.fromHex('#6750A4'),
              'Dark': IrColor.fromHex('#D0BCFF'),
            }),
          ],
          textStyles: [IrTextStyleToken('TextTheme/labelLarge', labelStyle)],
          shadows: [IrShadowToken('Elevation/level1', button.shadows)],
          components: [
            IrComponent(
              name: 'Button',
              variants: [
                IrComponentVariant({'Type': 'Filled', 'State': 'Enabled'}),
              ],
            ),
          ],
        ),
      ),
    );
    expect(design['version'], designVersion);

    final node = childrenOf(screenOf(design)).single;
    final fill = (node['fills'] as List).single as Map;
    expect(fill['variable'], 'ColorScheme/primary');
    expect(fill['opacity'], 0.5);
    expect(node['effectStyle'], 'Elevation/level1');
    expect(node['instance'], {
      'component': 'Button',
      'variant': 'Button[Type=Filled, State=Enabled]',
      'props': {'Type': 'Filled', 'State': 'Enabled'},
    });
    expect(childrenOf(node).single['textStyle'], 'TextTheme/labelLarge');

    final ds = design['designSystem'] as Map;
    expect(ds['collection'], 'demo theme');
    expect(ds['modes'], ['Light', 'Dark']);
    final variable = (ds['variables'] as List).single as Map;
    expect((variable['values'] as Map).keys, ['Light', 'Dark']);
    expect(((variable['values'] as Map)['Dark'] as Map)['a'], 1);
    final textStyle = (ds['textStyles'] as List).single as Map;
    expect(textStyle['fontName'], {'family': 'Roboto', 'style': 'Medium'});
    expect(textStyle.containsKey('color'), isFalse);
    expect(((ds['components'] as List).single as Map)['variants'], [
      {
        'key': 'Button[Type=Filled, State=Enabled]',
        'name': 'Type=Filled, State=Enabled',
        'uses': 1,
      },
    ]);
  });
}
