import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';

import { DesignDocument, FrameSpec, NodeSpec, parseDesign } from '../src/design';
import { importDesign, PLUGIN_DATA_KEY } from '../src/importer';
import { createMockFigma, MockFrame, MockNode, MockText } from './figma-mock';

// The same golden the Dart CLI test checks, so both sides share one contract.
const GOLDEN = path.resolve(process.cwd(), '../packages/cli/test/goldens/basic.design.json');

async function run(doc: DesignDocument) {
  const api = createMockFigma();
  const result = await importDesign(api as unknown as PluginAPI, doc);
  return { api, result };
}

function countSpecs(nodes: NodeSpec[]): number {
  return nodes.reduce((n, s) => n + 1 + (s.type === 'FRAME' ? countSpecs(s.children) : 0), 0);
}

function find(node: MockNode, name: string): MockNode | undefined {
  if (node.name === name) return node;
  for (const child of (node as MockFrame).children ?? []) {
    const hit = find(child, name);
    if (hit) return hit;
  }
  return undefined;
}

test('imports the basic example exported by the CLI', async () => {
  const doc = parseDesign(readFileSync(GOLDEN, 'utf8'));
  const { api, result } = await run(doc);

  assert.equal(result.screens.length, 2);
  assert.equal(result.nodeCount, countSpecs(doc.screens));
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

  const button = find(home, 'ElevatedButton') as MockFrame;
  assert.equal(button.layoutMode, 'HORIZONTAL');
  assert.equal(button.minHeight, 40);
  assert.equal(button.cornerRadius, 20);
  assert.equal(button.effects.length, 2);
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
