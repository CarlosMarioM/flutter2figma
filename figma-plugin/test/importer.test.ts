import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';

import { DesignDocument, FrameSpec, parseDesign } from '../src/design';
import { importDesign, PLUGIN_DATA_KEY } from '../src/importer';
import { createMockFigma, MockFrame, MockInstance, MockNode, MockText } from './figma-mock';

// The same golden the Dart CLI test checks, so both sides share one contract.
const GOLDEN = path.resolve(process.cwd(), '../packages/cli/test/goldens/basic.design.json');

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

/** The variable a paint is bound to, by name. */
function boundTo(api: ReturnType<typeof createMockFigma>, paint: Paint): string | undefined {
  const id = (paint as SolidPaint).boundVariables?.color?.id;
  return api.variableList.find((v) => v.id === id)?.name;
}

test('imports the basic example exported by the CLI', async () => {
  const { api, result } = await run(golden());

  assert.equal(result.screens.length, 2);
  assert.deepEqual(Object.keys(result.fontSubstitutions), []);
  assert.equal(api.pages.length, 1);

  const home = result.screens[0] as unknown as MockFrame;
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
  assert.equal(collection.name, 'basic theme');
  assert.deepEqual(collection.modes.map((m) => m.name), ['Light', 'Dark']);
  assert.equal(result.variables, ds.variables.length);
  assert.equal(result.textStyles, 15);
  assert.equal(result.effectStyles, 5);

  const primary = api.variableList.find((v) => v.name === 'ColorScheme/primary')!;
  assert.equal(Object.keys(primary.valuesByMode).length, 2);

  // Screens are pinned to the exported mode; paints are bound, not raw.
  const home = result.screens[0] as unknown as MockFrame;
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
  assert.equal(result.components, 4); // 3 Button variants + StatCard
  assert.equal(result.instances, 5); // 3 buttons + 2 stat cards

  const page = result.page as unknown as MockFrame;
  const library = find(page, 'Components') as MockFrame;
  const buttonSet = find(library, 'Button') as MockFrame;
  assert.equal(buttonSet.type, 'COMPONENT_SET');
  assert.deepEqual(buttonSet.children.map((c) => c.name).sort(), [
    'Type=Elevated, State=Enabled',
    'Type=Filled, State=Enabled',
    'Type=Text, State=Enabled',
  ]);

  const home = result.screens[0] as unknown as MockFrame;
  const elevated = find(home, 'ElevatedButton') as MockInstance;
  assert.equal(elevated.type, 'INSTANCE');
  assert.equal(elevated.mainComponent!.name, 'Type=Elevated, State=Enabled');
  assert.notEqual(elevated.effectStyleId, '', 'elevation comes from an effect style');

  // Both stat cards are instances of one master; the second overrides text.
  const profile = result.screens[1] as unknown as MockFrame;
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
