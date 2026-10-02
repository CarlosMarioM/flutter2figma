import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';

import { DesignDocument, FrameSpec, parseDesign } from '../src/design';
import { importDesign, PLUGIN_DATA_KEY } from '../src/importer';
import { createMockFigma, MockFrame, MockInstance, MockNode, MockText, MockVector } from './figma-mock';

// The same golden the Dart CLI test checks, so both sides share one contract.
const GOLDEN = path.resolve(process.cwd(), '../test/goldens/basic.design.json');

async function run(doc: DesignDocument, api = createMockFigma()) {
  const result = await importDesign(api as unknown as PluginAPI, doc);
  return { api, result };
}

function find(node: MockNode, name: string): MockNode | undefined {
  if (node.name === name) return node;
  for (const child of (node as MockFrame).children ?? []) {
    const hit = find(child, name);
    if (hit) return hit;
  }
  return undefined;
}

function findAll(node: MockNode, name: string, out: MockNode[] = []): MockNode[] {
  if (node.name === name) out.push(node);
  for (const child of (node as MockFrame).children ?? []) findAll(child, name, out);
  return out;
}

const golden = () => parseDesign(readFileSync(GOLDEN, 'utf8'));

function screenNamed(result: { screens: FrameNode[] }, name: string): MockFrame {
  const screen = result.screens.find((s) => s.name === name);
  assert.ok(screen, `no screen ${name}`);
  return screen as unknown as MockFrame;
}

// Sizes Flutter itself lays out for the same screens, measured by
// example/test/layout_ground_truth_test.dart.
const LAYOUT = path.resolve(process.cwd(), '../test/goldens/basic_layout.json');

/** The variable a paint is bound to, by name. */
function boundTo(api: ReturnType<typeof createMockFigma>, paint: Paint): string | undefined {
  const id = (paint as SolidPaint).boundVariables?.color?.id;
  return api.variableList.find((v) => v.id === id)?.name;
}

test('imports the basic example exported by the CLI', async () => {
  const { api, result } = await run(golden());

  assert.equal(result.screens.length, 6);
  assert.deepEqual(Object.keys(result.fontSubstitutions), []);
  assert.equal(api.pages.length, 1);

  const home = screenNamed(result, 'HomeScreen');
  assert.equal(home.name, 'HomeScreen');
  assert.equal(home.width, 390);
  assert.equal(home.height, 844);
  assert.deepEqual(home.children.map((c) => c.name), ['AppBar', 'Column']);

  const column = home.children[1] as MockFrame;
  assert.equal(column.layoutMode, 'VERTICAL');
  assert.equal(column.itemSpacing, 16);
  assert.equal(column.paddingLeft, 24);
  assert.equal(column.layoutSizingHorizontal, 'FILL');
  assert.equal(column.layoutSizingVertical, 'FILL');
  assert.deepEqual(JSON.parse(column.pluginData.get(PLUGIN_DATA_KEY)!).origin, ['Padding', 'Column', 'SizedBox']);

  const welcome = find(home, 'Welcome') as MockText;
  assert.deepEqual(welcome.fontName, { family: 'Inter', style: 'Bold' }); // from the app's ThemeData
  assert.equal(welcome.fontSize, 32);
  assert.equal(welcome.characters, 'Welcome');
});

test('creates the design system: variables per mode, text and effect styles', async () => {
  const doc = golden();
  const { api, result } = await run(doc);
  const ds = doc.designSystem!;

  assert.equal(api.collections.length, 1);
  const collection = api.collections[0];
  assert.equal(collection.name, 'flutter2figma_example theme');
  assert.deepEqual(collection.modes.map((m) => m.name), ['Light', 'Dark']);
  assert.equal(result.variables, ds.variables.length);
  assert.equal(result.textStyles, 15);
  assert.equal(result.effectStyles, 5);

  const primary = api.variableList.find((v) => v.name === 'ColorScheme/primary')!;
  assert.equal(Object.keys(primary.valuesByMode).length, 2);

  // Screens are pinned to the exported mode; paints are bound, not raw.
  const home = screenNamed(result, 'HomeScreen');
  const light = collection.modes.find((m) => m.name === 'Light')!.modeId;
  assert.equal(home.explicitModes.get(collection.id), light);
  assert.equal(boundTo(api, home.fills[0]), 'ColorScheme/surface');
  const hello = find(home, 'Hello') as MockText;
  assert.equal(hello.fills[0].type, 'SOLID');
  assert.equal(boundTo(api, hello.fills[0]), undefined, 'Colors.white is a literal, not a token');

  // Theme-styled text is linked to its text style; a one-off style is not.
  const title = find(home, 'Home') as MockText;
  assert.equal(api.textStyleList().find((s) => s.id === title.textStyleId)?.name, 'TextTheme/titleLarge');
  assert.equal((find(home, 'Welcome') as MockText).textStyleId, '');
});

test('turns buttons and repeated widgets into components with instances', async () => {
  const { result } = await run(golden());
  assert.equal(result.components, 5); // 4 Button variants + StatCard
  assert.equal(result.instances, 6); // 4 buttons + 2 stat cards

  const page = result.page as unknown as MockFrame;
  const library = find(page, 'Components') as MockFrame;
  const buttonSet = find(library, 'Button') as MockFrame;
  assert.equal(buttonSet.type, 'COMPONENT_SET');
  // The full-width Settings button (minimum height 52) is its own variant.
  assert.deepEqual(buttonSet.children.map((c) => c.name).sort(), [
    'Type=Elevated, State=Enabled',
    'Type=Filled, State=Enabled, Variant=1',
    'Type=Filled, State=Enabled, Variant=2',
    'Type=Text, State=Enabled',
  ]);

  const home = screenNamed(result, 'HomeScreen');
  const elevated = find(home, 'ElevatedButton') as MockInstance;
  assert.equal(elevated.type, 'INSTANCE');
  assert.equal(elevated.mainComponent!.name, 'Type=Elevated, State=Enabled');
  assert.notEqual(elevated.effectStyleId, '', 'elevation comes from an effect style');

  // Both stat cards are instances of one master; the second overrides text.
  const profile = screenNamed(result, 'ProfileScreen');
  const cards = findAll(profile, 'StatCard') as MockInstance[];
  assert.equal(cards.length, 2);
  assert.ok(cards.every((c) => c.type === 'INSTANCE'));
  assert.equal(cards[0].mainComponent, cards[1].mainComponent);
  const master = cards[0].mainComponent!;
  assert.equal(master.parent, library);
  assert.ok(find(master, '128'), 'master keeps the first occurrence');
  assert.equal((find(cards[1], '128') as MockText).characters, '4.2k');
  assert.equal((find(cards[1], 'Posts') as MockText).characters, 'Followers');
  // FILL only applied inside the row; the master is a standalone size.
  assert.equal(cards[0].layoutSizingHorizontal, 'FILL');
  assert.equal(master.layoutSizingHorizontal, 'FIXED');
});

test('re-importing updates the design system instead of duplicating it', async () => {
  const api = createMockFigma();
  await run(golden(), api);
  await run(golden(), api);
  assert.equal(api.collections.length, 1);
  assert.equal(api.variableList.length, golden().designSystem!.variables.length);
  assert.equal(api.textStyleList().length, 15);
  assert.equal(api.effectStyleList().length, 5);
  assert.equal(api.pages.length, 2, 'each import gets its own page');
});

test('a plan limited to one mode still imports, with a note', async () => {
  const { api, result } = await run(golden(), createMockFigma({ maxModes: 1 }));
  assert.deepEqual(api.collections[0].modes.map((m) => m.name), ['Light']);
  assert.match(result.notes.join(), /Mode "Dark" not created/);
});

test('substitutes unavailable fonts', async () => {
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 1,
    name: 'fonts',
    fonts: [{ family: 'Nope Sans', style: 'Bold' }],
    diagnostics: [],
    screens: [
      frame('Screen', 'VERTICAL', {
        children: [
          {
            type: 'TEXT',
            name: 'Hi',
            characters: 'Hi',
            fontName: { family: 'Nope Sans', style: 'Bold' },
            fontSize: 14,
            lineHeight: { unit: 'AUTO' },
            letterSpacing: { unit: 'PIXELS', value: 0 },
            textAlignHorizontal: 'LEFT',
            textAutoResize: 'WIDTH_AND_HEIGHT',
            layoutSizingHorizontal: 'HUG',
            layoutSizingVertical: 'HUG',
            fills: [],
            pluginData: {},
          },
        ],
      }),
    ],
  };
  const { result } = await run(doc);
  assert.deepEqual(result.fontSubstitutions, { 'Nope Sans Bold': 'Inter Bold' });
  const text = find(result.screens[0] as unknown as MockNode, 'Hi') as MockText;
  assert.deepEqual(text.fontName, { family: 'Inter', style: 'Bold' });
});

test('positions stack children and absolute children in auto layout', async () => {
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 1,
    name: 'stack',
    fonts: [],
    diagnostics: [],
    screens: [
      frame('Screen', 'VERTICAL', {
        children: [
          frame('Stack', 'NONE', {
            width: 200,
            height: 100,
            children: [
              frame('Background', 'VERTICAL', { layoutSizingHorizontal: 'FILL', layoutSizingVertical: 'FILL', position: { left: 0, top: 0 } }),
              frame('Badge', 'VERTICAL', { width: 20, height: 10, position: { right: 8, bottom: 4 } }),
            ],
          }),
          frame('Fab', 'HORIZONTAL', { width: 56, height: 56, layoutPositioning: 'ABSOLUTE', position: { right: 16, bottom: 16 } }),
        ],
      }),
    ],
  };
  const { result } = await run(doc);
  const screen = result.screens[0] as unknown as MockFrame;

  const background = find(screen, 'Background')!;
  assert.deepEqual([background.x, background.y, background.width, background.height], [0, 0, 200, 100]);

  const badge = find(screen, 'Badge')!;
  assert.deepEqual([badge.x, badge.y], [200 - 8 - 20, 100 - 4 - 10]);
  assert.deepEqual(badge.constraints, { horizontal: 'MAX', vertical: 'MAX' });

  const fab = find(screen, 'Fab')!;
  assert.equal(fab.layoutPositioning, 'ABSOLUTE');
  assert.deepEqual([fab.x, fab.y], [390 - 16 - 56, 844 - 16 - 56]);
});

test('rejects files that are not design.json', () => {
  assert.throws(() => parseDesign('{"format":"flutter2figma/ir"}'), /Not a Flutter2Figma design.json/);
  assert.throws(() => parseDesign('nope'), /Not valid JSON/);
  assert.throws(() => parseDesign('{"format":"flutter2figma/design","version":99}'), /newer than this plugin/);
});

// https://github.com/CarlosMarioM/flutter2figma/issues/1
// Stack > Column(header, Expanded(Stack(fit: expand, DecoratedBox(...)))):
// the body collapsed to 0.01 px because FILL children of NONE frames were
// sized after their subtree, against Figma's default 100×100.
test('imported sizes match what Flutter lays out', async () => {
  const { result } = await run(golden());
  const screen = (name: string) => result.screens.find((s) => s.name === name) as unknown as MockFrame;
  // Flutter measures a button with its tap target, the Figma frame around it.
  const outer = (node: MockNode) => (node.parent?.name === 'Tap target' ? node.parent : node) as MockNode;
  const figma: Record<string, MockNode> = {
    'HomeScreen/ElevatedButton': outer(find(screen('HomeScreen'), 'ElevatedButton')!),
    'StackLayoutScreen/header': find(screen('StackLayoutScreen'), 'Container')!,
    'StackLayoutScreen/body': find(screen('StackLayoutScreen'), 'DecoratedBox')!,
    'StackLayoutScreen/IconButton': outer(find(screen('StackLayoutScreen'), 'IconButton')!),
    'ScoreboardScreen/Switch': find(screen('ScoreboardScreen'), 'Switch')!,
    'ScoreboardScreen/Checkbox': find(screen('ScoreboardScreen'), 'Checkbox')!,
    'ProfileScreen/Image': find(screen('ProfileScreen'), 'Image/logo.png')!,
    'ContactsScreen/ListTile 1': findAll(screen('ContactsScreen'), 'ListTile')[0],
    'ContactsScreen/ListTile 2': findAll(screen('ContactsScreen'), 'ListTile')[1],
    'ContactsScreen/SwitchListTile': find(screen('ContactsScreen'), 'SwitchListTile')!,
    'ContactsScreen/Chip': outer(find(screen('ContactsScreen'), 'Chip')!),
    'ContactsScreen/FilterChip': outer(find(screen('ContactsScreen'), 'FilterChip')!),
    'ContactsScreen/InputChip': outer(find(screen('ContactsScreen'), 'InputChip')!),
    'ContactsScreen/NavigationBar': find(screen('ContactsScreen'), 'NavigationBar')!,
  };
  const flutter = JSON.parse(readFileSync(LAYOUT, 'utf8')) as Record<string, [number, number]>;
  assert.deepEqual(Object.keys(figma).sort(), Object.keys(flutter).sort());
  for (const [key, [width, height]] of Object.entries(flutter)) {
    const node = figma[key];
    // Text metrics differ between Flutter's test font and Figma, so widths
    // that depend on a label are compared loosely.
    const labelled = key === 'HomeScreen/ElevatedButton' || /Chip$/.test(key);
    assert.ok(Math.abs(node.width - width) < 1 || labelled, `${key} width ${node.width} ≠ ${width}`);
    assert.equal(node.height, height, `${key} height`);
  }
});

test('icons import as vectors of their glyph, colored by the theme', async () => {
  const { api, result } = await run(golden());
  const screen = result.screens.find((s) => s.name === 'StackLayoutScreen') as unknown as MockFrame;
  const icon = find(screen, 'Icon/arrow_back_ios') as MockFrame;
  assert.deepEqual([icon.width, icon.height, icon.layoutMode], [32, 32, 'NONE']);
  const glyph = icon.children[0];
  assert.ok(glyph instanceof MockVector);
  assert.equal(icon.children.length, 1);
  // Material's arrow_back_ios: x 0–11.67, y 2.1–21.9 on a 24 grid.
  assert.equal(glyph.x, 0);
  assert.ok(Math.abs(glyph.y - (2.1 * 32) / 24) < 0.05, `y ${glyph.y}`);
  assert.ok(Math.abs(glyph.width - (11.67 * 32) / 24) < 0.05, `width ${glyph.width}`);
  assert.ok(Math.abs(glyph.height - (19.8 * 32) / 24) < 0.05, `height ${glyph.height}`);
  assert.equal(boundTo(api, glyph.fills[0]), 'ColorScheme/onSurfaceVariant');
});

test('asset images become image fills, uploaded once', async () => {
  const { api, result } = await run(golden());
  const profile = result.screens.find((s) => s.name === 'ProfileScreen') as unknown as MockFrame;
  const logo = find(profile, 'Image/logo.png') as MockFrame;
  assert.deepEqual([logo.width, logo.height], [48, 48]); // 96 px at 2.0x
  assert.equal(logo.fills.length, 1);
  const paint = logo.fills[0] as ImagePaint;
  assert.equal(paint.type, 'IMAGE');
  assert.equal(paint.scaleMode, 'FIT');

  // DecorationImage(fit: BoxFit.cover) on a circle.
  const avatar = findAll(profile, 'Container').find((n) =>
    (n as MockFrame).fills.some((f) => f.type === 'IMAGE'),
  ) as MockFrame;
  assert.equal((avatar.fills[0] as ImagePaint).scaleMode, 'FILL');
  assert.equal(avatar.cornerRadius, 9999);
  assert.equal(api.imageCount(), 2);
});

test('SVG assets are drawn inside their frame, fitted', async () => {
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10"><rect width="20" height="10"/></svg>';
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 3,
    name: 'svg',
    fonts: [],
    diagnostics: [],
    images: { 'assets/wide.svg': { format: 'svg', width: 20, height: 10, data: svg } },
    screens: [
      frame('Screen', 'VERTICAL', {
        children: [frame('Image/wide.svg', 'NONE', { width: 40, height: 40, svg: { image: 'assets/wide.svg', scaleMode: 'FIT' } })],
      }),
    ],
  };
  const { result } = await run(doc);
  const box = find(result.screens[0] as unknown as MockFrame, 'Image/wide.svg') as MockFrame;
  const drawn = box.children[0];
  assert.deepEqual([drawn.width, drawn.height, drawn.x, drawn.y], [40, 20, 0, 10]);
  assert.deepEqual(drawn.constraints, { horizontal: 'SCALE', vertical: 'SCALE' });
});

test('gradient fills pass through as Figma gradients', async () => {
  const gradient: GradientPaint = {
    type: 'GRADIENT_LINEAR',
    gradientTransform: [
      [0, 1, 0],
      [-1, 0, 1],
    ],
    gradientStops: [
      { color: { r: 1, g: 0, b: 0, a: 1 }, position: 0 },
      { color: { r: 0, g: 0, b: 1, a: 1 }, position: 1 },
    ],
  };
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 3,
    name: 'gradient',
    fonts: [],
    diagnostics: [],
    screens: [frame('Screen', 'VERTICAL', { children: [frame('Cover', 'NONE', { width: 100, height: 50, fills: [gradient] })] })],
  };
  const { result } = await run(doc);
  const cover = find(result.screens[0] as unknown as MockFrame, 'Cover') as MockFrame;
  assert.equal(cover.fills[0].type, 'GRADIENT_LINEAR');
});

test('Wrap frames wrap onto new rows', async () => {
  const chip = (name: string) => frame(name, 'HORIZONTAL', { width: 100, height: 32 });
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 3,
    name: 'wrap',
    fonts: [],
    diagnostics: [],
    screens: [
      frame('Screen', 'VERTICAL', {
        children: [
          frame('Wrap', 'HORIZONTAL', {
            width: 250,
            itemSpacing: 8,
            layoutWrap: 'WRAP',
            counterAxisSpacing: 4,
            layoutSizingVertical: 'HUG',
            children: [chip('a'), chip('b'), chip('c')],
          }),
        ],
      }),
    ],
  };
  const { result } = await run(doc);
  const wrap = find(result.screens[0] as unknown as MockFrame, 'Wrap') as MockFrame;
  assert.equal(wrap.layoutWrap, 'WRAP');
  assert.equal(wrap.counterAxisSpacing, 4);
  assert.equal(wrap.height, 32 + 4 + 32); // two rows: a b | c
});

test('FILL children of a Stack are sized before their subtree (#1)', async () => {
  const FILL = 'FILL' as const;
  // As exported by 0.1.0: FILL sizing, positioned from the top-left only.
  const pinned = { left: 0, top: 0 };
  const header = frame('Header', 'VERTICAL', {
    layoutSizingHorizontal: FILL,
    paddingTop: 32,
    paddingBottom: 32,
    paddingLeft: 32,
    paddingRight: 32,
    children: [frame('IconButton', 'VERTICAL', { width: 40, height: 40 })],
  });
  const body = frame('Body', 'VERTICAL', {
    layoutSizingHorizontal: FILL,
    layoutSizingVertical: FILL,
    position: pinned,
    fills: [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 }, opacity: 1 }],
  });
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 3,
    name: 'repro',
    fonts: [],
    diagnostics: [],
    screens: [
      frame('Screen', 'VERTICAL', {
        children: [
          frame('OuterStack', 'NONE', {
            layoutSizingHorizontal: FILL,
            layoutSizingVertical: FILL,
            children: [
              frame('Column', 'VERTICAL', {
                layoutSizingHorizontal: FILL,
                layoutSizingVertical: FILL,
                position: { left: 0, top: 0 },
                children: [
                  header,
                  frame('InnerStack', 'NONE', {
                    layoutSizingHorizontal: FILL,
                    layoutSizingVertical: FILL,
                    children: [body],
                  }),
                ],
              }),
            ],
          }),
        ],
      }),
    ],
  };
  const { result } = await run(doc);
  const screen = result.screens[0] as unknown as MockFrame;
  const column = find(screen, 'Column')!;
  const innerStack = find(screen, 'InnerStack')!;
  const bodyNode = find(screen, 'Body')!;

  assert.deepEqual([column.width, column.height], [390, 844]);
  assert.equal(find(screen, 'Header')!.height, 104); // 32 + 40 + 32
  assert.deepEqual([innerStack.width, innerStack.height], [390, 740]);
  assert.deepEqual([bodyNode.width, bodyNode.height], [390, 740], 'body fills the rest of the screen');
  assert.deepEqual(bodyNode.constraints, { horizontal: 'STRETCH', vertical: 'STRETCH' });
});

// Positioned(left: 20, right: 30, child: Column(...)): stretched across,
// hugging its content down. Placing it before its children exist must not
// freeze the empty height.
test('a stretched child of a Stack keeps hugging on the other axis', async () => {
  const doc: DesignDocument = {
    format: 'flutter2figma/design',
    version: 3,
    name: 'hug',
    fonts: [],
    diagnostics: [],
    screens: [
      frame('Screen', 'VERTICAL', {
        children: [
          frame('Header', 'NONE', {
            layoutSizingHorizontal: 'FILL',
            height: 200,
            children: [
              frame('Titles', 'VERTICAL', {
                position: { left: 20, right: 30 },
                children: [frame('Title', 'VERTICAL', { width: 200, height: 77 })],
              }),
            ],
          }),
        ],
      }),
    ],
  };
  const { result } = await run(doc);
  const titles = find(result.screens[0] as unknown as MockNode, 'Titles')!;
  assert.deepEqual([titles.width, titles.height], [390 - 20 - 30, 77]);
  assert.equal(titles.layoutSizingVertical, 'HUG');
});

function frame(name: string, layoutMode: FrameSpec['layoutMode'], overrides: Partial<FrameSpec> = {}): FrameSpec {
  return {
    type: 'FRAME',
    name,
    layoutMode,
    width: name === 'Screen' ? 390 : undefined,
    height: name === 'Screen' ? 844 : undefined,
    layoutSizingHorizontal: name === 'Screen' || overrides.width !== undefined ? 'FIXED' : layoutMode === 'NONE' ? 'FIXED' : 'HUG',
    layoutSizingVertical: name === 'Screen' || overrides.height !== undefined ? 'FIXED' : layoutMode === 'NONE' ? 'FIXED' : 'HUG',
    fills: [],
    clipsContent: false,
    children: [],
    pluginData: {},
    ...overrides,
  };
}

// Opt-in: import real exports through the strict mock, e.g.
//   F2F_DESIGNS=/path/a/design.json:/path/b/design.json npm test
for (const file of (process.env.F2F_DESIGNS ?? '').split(':').filter(Boolean)) {
  test(`imports ${file}`, async () => {
    const doc = parseDesign(readFileSync(file, 'utf8'));
    const { result } = await run(doc);
    assert.equal(result.screens.length, doc.screens.length);

    // Content must not collapse (the symptom of #1): no frame with children
    // may end up ~0 px on either axis.
    // Boxes the code itself sizes to 0 (e.g. an invisible audio renderer in
    // a `SizedBox(width: 0, height: 0)`) are intentional; skip them.
    const collapsed: string[] = [];
    const zero = (node: MockNode) => node.width <= 0.011 || node.height <= 0.011;
    const walk = (node: MockNode, path: string) => {
      const here = `${path}/${node.name}`;
      const children = (node as MockFrame).children ?? [];
      const intended = node.layoutSizingHorizontal === 'FIXED' && node.layoutSizingVertical === 'FIXED';
      if (zero(node) && intended) return;
      if (children.length > 0 && zero(node)) collapsed.push(`${here} (${node.width}×${node.height})`);
      children.forEach((c) => walk(c, here));
    };
    for (const screen of result.screens) walk(screen as unknown as MockNode, '');
    assert.deepEqual(collapsed, [], 'collapsed frames with content');
  });
}
