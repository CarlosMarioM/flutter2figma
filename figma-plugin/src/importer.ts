import type { DesignDocument, FrameSpec, NodeSpec, TextSpec } from './design';

export const PLUGIN_DATA_KEY = 'flutter2figma';

export interface ImportResult {
  page: PageNode;
  screens: FrameNode[];
  nodeCount: number;
  /** Requested font → substituted font, for fonts that weren't available. */
  fontSubstitutions: Record<string, string>;
}

const FALLBACK_FAMILY = 'Inter';

const WEIGHT_BY_STYLE: Record<string, number> = {
  Thin: 100,
  ExtraLight: 200,
  Light: 300,
  Regular: 400,
  Medium: 500,
  SemiBold: 600,
  Bold: 700,
  ExtraBold: 800,
  Black: 900,
};

function fontKey(f: FontName): string {
  return `${f.family} ${f.style}`;
}

function weightOf(style: string): number {
  const base = style.replace(/\s*Italic$/, '') || 'Regular';
  return WEIGHT_BY_STYLE[base.replace(/\s+/g, '')] ?? 400;
}

/**
 * Loads every font the design uses. Missing fonts are replaced by the
 * nearest weight of the same family, then by Inter.
 */
async function loadFonts(api: PluginAPI, requested: FontName[]): Promise<Map<string, FontName>> {
  const resolved = new Map<string, FontName>();
  let available: Font[] | null = null;

  for (const font of requested) {
    try {
      await api.loadFontAsync(font);
      resolved.set(fontKey(font), font);
      continue;
    } catch {
      // Fall through to substitution.
    }
    available ??= await api.listAvailableFontsAsync();
    const italic = /Italic$/.test(font.style);
    const target = weightOf(font.style);
    const candidates = (family: string) =>
      available!
        .map((f) => f.fontName)
        .filter((f) => f.family === family && /Italic$/.test(f.style) === italic && hasKnownWeight(f.style))
        .sort((a, b) => Math.abs(weightOf(a.style) - target) - Math.abs(weightOf(b.style) - target));
    const substitute =
      candidates(font.family)[0] ?? candidates(FALLBACK_FAMILY)[0] ?? { family: FALLBACK_FAMILY, style: 'Regular' };
    await api.loadFontAsync(substitute);
    resolved.set(fontKey(font), substitute);
  }
  return resolved;
}

/** Only substitute styles we can map to a weight (skips "Condensed" etc.). */
function hasKnownWeight(style: string): boolean {
  const base = style.replace(/\s*Italic$/, '').replace(/\s+/g, '') || 'Regular';
  return base in WEIGHT_BY_STYLE;
}

function isAutoLayout(node: BaseNode & ChildrenMixin): boolean {
  return 'layoutMode' in node && (node as FrameNode).layoutMode !== 'NONE';
}

export async function importDesign(api: PluginAPI, doc: DesignDocument): Promise<ImportResult> {
  const fonts = await loadFonts(api, doc.fonts);

  const page = api.createPage();
  page.name = `Flutter2Figma · ${doc.name}`;
  await api.setCurrentPageAsync(page);

  let nodeCount = 0;

  const build = (spec: NodeSpec, parent: BaseNode & ChildrenMixin): FrameNode | TextNode => {
    nodeCount++;
    const node = spec.type === 'TEXT' ? buildText(spec) : buildFrame(spec);
    node.name = spec.name;
    parent.appendChild(node);

    const parentIsAutoLayout = isAutoLayout(parent);
    if (spec.layoutPositioning === 'ABSOLUTE' && parentIsAutoLayout) {
      node.layoutPositioning = 'ABSOLUTE';
    }

    // Fixed dimensions first, then sizing modes (FILL needs the node attached
    // to an auto-layout parent; HUG needs the node itself to be auto-layout
    // or text).
    if (spec.width !== undefined || spec.height !== undefined) {
      node.resize(Math.max(0.01, spec.width ?? node.width), Math.max(0.01, spec.height ?? node.height));
    }
    if (spec.x !== undefined) node.x = spec.x;
    if (spec.y !== undefined) node.y = spec.y;
    const canFill = parentIsAutoLayout && spec.layoutPositioning !== 'ABSOLUTE';
    for (const axis of ['Horizontal', 'Vertical'] as const) {
      const mode = spec[`layoutSizing${axis}`];
      if (mode === 'FILL' && !canFill) continue; // Handled by the parent (stack stretch).
      node[`layoutSizing${axis}`] = mode;
    }
    if (spec.type === 'TEXT') (node as TextNode).textAutoResize = spec.textAutoResize;

    if (spec.type === 'FRAME') {
      const frame = node as FrameNode;
      if (spec.minWidth !== undefined) frame.minWidth = spec.minWidth;
      if (spec.minHeight !== undefined) frame.minHeight = spec.minHeight;
      const children = spec.children.map((child) => [child, build(child, frame)] as const);
      placeAbsoluteChildren(frame, children);
    }

    node.setPluginData(PLUGIN_DATA_KEY, JSON.stringify(spec.pluginData));
    return node;
  };

  const buildFrame = (spec: FrameSpec): FrameNode => {
    const frame = api.createFrame();
    frame.fills = spec.fills;
    frame.clipsContent = spec.clipsContent;
    frame.layoutMode = spec.layoutMode;
    if (spec.layoutMode !== 'NONE') {
      frame.primaryAxisAlignItems = spec.primaryAxisAlignItems ?? 'MIN';
      frame.counterAxisAlignItems = spec.counterAxisAlignItems ?? 'MIN';
      frame.itemSpacing = spec.itemSpacing ?? 0;
      frame.paddingTop = spec.paddingTop ?? 0;
      frame.paddingRight = spec.paddingRight ?? 0;
      frame.paddingBottom = spec.paddingBottom ?? 0;
      frame.paddingLeft = spec.paddingLeft ?? 0;
    }
    if (spec.strokes) {
      frame.strokes = spec.strokes;
      frame.strokeWeight = spec.strokeWeight ?? 1;
      frame.strokeAlign = spec.strokeAlign ?? 'INSIDE';
    }
    if (spec.cornerRadius !== undefined) {
      frame.cornerRadius = spec.cornerRadius;
    } else if (spec.topLeftRadius !== undefined) {
      frame.topLeftRadius = spec.topLeftRadius;
      frame.topRightRadius = spec.topRightRadius ?? 0;
      frame.bottomRightRadius = spec.bottomRightRadius ?? 0;
      frame.bottomLeftRadius = spec.bottomLeftRadius ?? 0;
    }
    if (spec.effects) frame.effects = spec.effects;
    return frame;
  };

  const buildText = (spec: TextSpec): TextNode => {
    const text = api.createText();
    text.fontName = fonts.get(fontKey(spec.fontName)) ?? { family: FALLBACK_FAMILY, style: 'Regular' };
    text.characters = spec.characters;
    text.fontSize = spec.fontSize;
    text.lineHeight = spec.lineHeight;
    text.letterSpacing = spec.letterSpacing;
    text.fills = spec.fills;
    text.textAlignHorizontal = spec.textAlignHorizontal;
    text.textAutoResize = spec.textAutoResize;
    if (spec.maxLines !== undefined) {
      text.textTruncation = 'ENDING';
      text.maxLines = spec.maxLines;
    }
    return text;
  };

  const screens: FrameNode[] = [];
  for (const screen of doc.screens) {
    screens.push(build(screen, page) as FrameNode);
  }

  page.selection = screens;
  api.viewport.scrollAndZoomIntoView(screens);

  const fontSubstitutions: Record<string, string> = {};
  for (const [requested, actual] of fonts) {
    if (requested !== fontKey(actual)) fontSubstitutions[requested] = fontKey(actual);
  }
  return { page, screens, nodeCount, fontSubstitutions };
}

/**
 * Positions children that carry a `position` (Stack children, or absolute
 * children such as a FAB inside auto layout). Runs after the parent's
 * children exist, so auto-layout sizes are known.
 */
function placeAbsoluteChildren(frame: FrameNode, children: ReadonlyArray<readonly [NodeSpec, FrameNode | TextNode]>): void {
  const absoluteLayout = frame.layoutMode === 'NONE';
  for (const [spec, node] of children) {
    if (!absoluteLayout && spec.layoutPositioning !== 'ABSOLUTE') continue;
    const p = spec.position ?? {};

    if (absoluteLayout) {
      // FILL inside a NONE-layout frame: stretch to the parent.
      let width = node.width;
      let height = node.height;
      if (spec.layoutSizingHorizontal === 'FILL') width = frame.width;
      if (spec.layoutSizingVertical === 'FILL') height = frame.height;
      if (p.left !== undefined && p.right !== undefined) width = frame.width - p.left - p.right;
      if (p.top !== undefined && p.bottom !== undefined) height = frame.height - p.top - p.bottom;
      if (width !== node.width || height !== node.height) node.resize(Math.max(0.01, width), Math.max(0.01, height));
    }

    node.x = p.left ?? (p.right !== undefined ? frame.width - p.right - node.width : 0);
    node.y = p.top ?? (p.bottom !== undefined ? frame.height - p.bottom - node.height : 0);
    if ('constraints' in node) {
      node.constraints = {
        horizontal: p.left !== undefined && p.right !== undefined ? 'STRETCH' : p.right !== undefined && p.left === undefined ? 'MAX' : 'MIN',
        vertical: p.top !== undefined && p.bottom !== undefined ? 'STRETCH' : p.bottom !== undefined && p.top === undefined ? 'MAX' : 'MIN',
      };
    }
  }
}
