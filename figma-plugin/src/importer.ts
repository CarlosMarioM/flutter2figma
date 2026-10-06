import type { ComponentSpec, DesignDocument, FrameSpec, NodeSpec, TextSpec, VectorSpec } from './design';
import { DesignSystem, setupDesignSystem, toPaints } from './design-system';
import { updateNote } from './version';

export const PLUGIN_DATA_KEY = 'flutter2figma';

export interface ImportResult {
  page: PageNode;
  screens: FrameNode[];
  nodeCount: number;
  /** Requested font → substituted font, for fonts that weren't available. */
  fontSubstitutions: Record<string, string>;
  variables: number;
  textStyles: number;
  effectStyles: number;
  /** Component masters created, and instances placed in the screens. */
  components: number;
  instances: number;
  notes: string[];
}

/** Built nodes: plain frames, text and vectors, or component instances. */
type Built = FrameNode | TextNode | VectorNode | InstanceNode;

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

function isFrame(node: BaseNode): node is FrameNode {
  return node.type === 'FRAME' || node.type === 'COMPONENT' || node.type === 'INSTANCE';
}

function isAutoLayout(node: BaseNode): boolean {
  return 'layoutMode' in node && (node as FrameNode).layoutMode !== 'NONE';
}

export async function importDesign(api: PluginAPI, doc: DesignDocument): Promise<ImportResult> {
  const fonts = await loadFonts(api, doc.fonts);
  const fontFor = (f: FontName) => fonts.get(fontKey(f)) ?? { family: FALLBACK_FAMILY, style: 'Regular' };

  const page = api.createPage();
  page.name = `Flutter2Figma · ${doc.name}`;
  await api.setCurrentPageAsync(page);

  const ds: DesignSystem | null = doc.designSystem
    ? await setupDesignSystem(api, doc.designSystem, fontFor)
    : null;

  // Component masters live in their own frame below the screens.
  const componentSpecs = doc.designSystem?.components ?? [];
  const library = componentSpecs.length > 0 ? createLibraryFrame(api, page) : null;
  const masters = new Map<string, ComponentNode>();
  const builtNodes = new Map<NodeSpec, Built>();
  let nodeCount = 0;

  // Each embedded image is uploaded once and shared by every fill using it.
  const imageHashes = new Map<string, string>();
  const imageHash = (key: string): string => {
    let hash = imageHashes.get(key);
    if (hash === undefined) {
      const asset = doc.images?.[key];
      if (!asset || asset.format === 'svg') throw new Error(`Image ${key} is missing from design.json`);
      hash = api.createImage(api.base64Decode(asset.data)).hash;
      imageHashes.set(key, hash);
    }
    return hash;
  };
  let instances = 0;

  /** Builds [spec] under [parent], as an instance when it is a component occurrence. */
  const build = async (spec: NodeSpec, parent: BaseNode & ChildrenMixin): Promise<Built> => {
    const variant = library ? spec.instance?.variant : undefined;
    if (variant === undefined) return buildNode(spec, parent);

    const master = masters.get(variant);
    if (master) {
      const instance = master.createInstance();
      instance.name = spec.name;
      parent.appendChild(instance);
      layout(instance, spec, parent);
      if (isFrame(parent)) placeChild(parent, spec, instance);
      applyTextOverrides(spec, instance);
      builtNodes.set(spec, instance);
      instances++;
      nodeCount++;
      return instance;
    }

    // First occurrence: build it for real so Figma measures it, turn it into
    // the component, put an instance in its place and move the master into
    // the library.
    const node = (await buildNode(spec, parent)) as FrameNode;
    const width = node.width;
    const height = node.height;
    const component = api.createComponentFromNode(node);
    const instance = component.createInstance();
    parent.insertChild(parent.children.indexOf(component), instance);
    instance.name = spec.name;
    layout(instance, spec, parent);
    // FILL only made sense inside the screen: the master keeps the measured
    // size. Fix it before moving into the (hugging) library frame.
    for (const axis of ['Horizontal', 'Vertical'] as const) {
      if (component[`layoutSizing${axis}`] === 'FILL') component[`layoutSizing${axis}`] = 'FIXED';
    }
    component.resize(Math.max(0.01, width), Math.max(0.01, height));
    library!.appendChild(component);
    component.layoutPositioning = 'AUTO';
    component.name = spec.instance!.props ? variantName(spec.instance!.props) : spec.instance!.component;
    masters.set(variant, component);
    builtNodes.set(spec, instance);
    instances++;
    return instance;
  };

  const buildNode = async (spec: NodeSpec, parent: BaseNode & ChildrenMixin): Promise<FrameNode | TextNode | VectorNode> => {
    nodeCount++;
    const node =
      spec.type === 'TEXT' ? await buildText(spec) : spec.type === 'VECTOR' ? buildVector(spec) : await buildFrame(spec);
    node.name = spec.name;
    parent.appendChild(node);
    layout(node, spec, parent);
    if (spec.type === 'TEXT') (node as TextNode).textAutoResize = spec.textAutoResize;
    // Size a child of a Stack before building its subtree, so its own FILL
    // children are laid out against its real size, not Figma's default 100×100.
    if (isFrame(parent)) placeChild(parent, spec, node);
    builtNodes.set(spec, node);

    if (spec.type === 'FRAME') {
      const frame = node as FrameNode;
      if (spec.minWidth !== undefined) frame.minWidth = spec.minWidth;
      if (spec.minHeight !== undefined) frame.minHeight = spec.minHeight;
      const children: (readonly [NodeSpec, Built])[] = [];
      for (const child of spec.children) children.push([child, await build(child, frame)]);
      placeAbsoluteChildren(frame, children);
      if (spec.svg) drawSvg(api, frame, spec.svg, doc);
    }

    node.setPluginData(PLUGIN_DATA_KEY, JSON.stringify(spec.pluginData));
    return node;
  };

  const buildFrame = async (spec: FrameSpec): Promise<FrameNode> => {
    const frame = api.createFrame();
    frame.fills = toPaints(api, spec.fills, ds, imageHash);
    frame.clipsContent = spec.clipsContent;
    frame.layoutMode = spec.layoutMode;
    if (spec.layoutMode !== 'NONE') {
      frame.primaryAxisAlignItems = spec.primaryAxisAlignItems ?? 'MIN';
      frame.counterAxisAlignItems = spec.counterAxisAlignItems ?? 'MIN';
      frame.itemSpacing = spec.itemSpacing ?? 0;
      if (spec.layoutWrap === 'WRAP' && spec.layoutMode === 'HORIZONTAL') {
        frame.layoutWrap = 'WRAP';
        frame.counterAxisSpacing = spec.counterAxisSpacing ?? 0;
      }
      frame.paddingTop = spec.paddingTop ?? 0;
      frame.paddingRight = spec.paddingRight ?? 0;
      frame.paddingBottom = spec.paddingBottom ?? 0;
      frame.paddingLeft = spec.paddingLeft ?? 0;
    }
    if (spec.strokes) {
      frame.strokes = toPaints(api, spec.strokes, ds);
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
    const effectStyle = spec.effectStyle ? ds?.effectStyles.get(spec.effectStyle) : undefined;
    if (effectStyle) {
      await frame.setEffectStyleIdAsync(effectStyle.id);
    } else if (spec.effects) {
      frame.effects = spec.effects;
    }
    return frame;
  };

  const buildVector = (spec: VectorSpec): VectorNode => {
    const vector = api.createVector();
    vector.vectorPaths = spec.vectorPaths;
    vector.fills = toPaints(api, spec.fills, ds, imageHash);
    if (spec.strokes) {
      vector.strokes = toPaints(api, spec.strokes, ds);
      vector.strokeWeight = spec.strokeWeight ?? 1;
      vector.strokeAlign = spec.strokeAlign ?? 'CENTER';
      vector.strokeCap = spec.strokeCap ?? 'NONE';
    }
    return vector;
  };

  const buildText = async (spec: TextSpec): Promise<TextNode> => {
    const text = api.createText();
    text.fontName = fontFor(spec.fontName);
    text.characters = spec.characters;
    const style = spec.textStyle ? ds?.textStyles.get(spec.textStyle) : undefined;
    if (style) {
      await text.setTextStyleIdAsync(style.id);
    } else {
      text.fontSize = spec.fontSize;
      text.lineHeight = spec.lineHeight;
      text.letterSpacing = spec.letterSpacing;
    }
    text.fills = toPaints(api, spec.fills, ds);
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
    const frame = (await build(screen, page)) as FrameNode;
    settle(screen, builtNodes);
    if (ds) frame.setExplicitVariableModeForCollection(ds.collection, ds.activeModeId);
    screens.push(frame);
  }

  if (library) {
    finishLibrary(api, library, componentSpecs, masters, screens);
    if (ds) library.setExplicitVariableModeForCollection(ds.collection, ds.activeModeId);
  }

  page.selection = screens;
  api.viewport.scrollAndZoomIntoView(library ? [...screens, library] : screens);

  const fontSubstitutions: Record<string, string> = {};
  for (const [requested, actual] of fonts) {
    if (requested !== fontKey(actual)) fontSubstitutions[requested] = fontKey(actual);
  }
  const update = updateNote(doc.generator?.version);
  return {
    page,
    screens,
    nodeCount,
    fontSubstitutions,
    variables: ds?.variables.size ?? 0,
    textStyles: ds?.textStyles.size ?? 0,
    effectStyles: ds?.effectStyles.size ?? 0,
    components: masters.size,
    instances,
    notes: [update, ...(ds?.notes ?? [])].filter((n): n is string => n !== undefined),
  };
}

/**
 * Position and size for a node already attached to [parent]: fixed
 * dimensions first, then sizing modes (FILL needs an auto-layout parent;
 * HUG needs the node itself to be auto-layout or text).
 */
function layout(node: Built, spec: NodeSpec, parent: BaseNode): void {
  const parentIsAutoLayout = isAutoLayout(parent);
  if (spec.layoutPositioning === 'ABSOLUTE' && parentIsAutoLayout) {
    node.layoutPositioning = 'ABSOLUTE';
  }
  // A vector is as big as its geometry; resizing would scale the outline.
  if ((spec.width !== undefined || spec.height !== undefined) && spec.type !== 'VECTOR') {
    node.resize(Math.max(0.01, spec.width ?? node.width), Math.max(0.01, spec.height ?? node.height));
  }
  if (spec.x !== undefined) node.x = spec.x;
  if (spec.y !== undefined) node.y = spec.y;
  // Figma only takes layoutSizing* on auto-layout frames and children of
  // auto-layout frames. Anything else keeps the size resize() gave it.
  if (!parentIsAutoLayout && !isAutoLayout(node)) return;
  const canFill = parentIsAutoLayout && spec.layoutPositioning !== 'ABSOLUTE';
  for (const axis of ['Horizontal', 'Vertical'] as const) {
    const mode = spec[`layoutSizing${axis}`];
    if (mode === 'FILL' && !canFill) continue; // Handled by the parent (stack stretch).
    node[`layoutSizing${axis}`] = mode;
  }
}

function variantName(props: Record<string, string>): string {
  return Object.entries(props)
    .map(([k, v]) => `${k}=${v}`)
    .join(', ');
}

/**
 * Instances share their master's structure (the compiler only groups
 * occurrences that differ in text), so walking both trees in parallel
 * finds every text to override.
 */
function applyTextOverrides(spec: NodeSpec, node: SceneNode): void {
  if (spec.type === 'TEXT') {
    if (node.type === 'TEXT' && node.characters !== spec.characters) node.characters = spec.characters;
    return;
  }
  if (spec.type !== 'FRAME' || !('children' in node)) return;
  spec.children.forEach((child, i) => {
    const target = node.children[i];
    if (target) applyTextOverrides(child, target);
  });
}

function createLibraryFrame(api: PluginAPI, page: PageNode): FrameNode {
  const library = api.createFrame();
  library.name = 'Components';
  page.appendChild(library);
  library.layoutMode = 'VERTICAL';
  library.itemSpacing = 48;
  library.paddingTop = library.paddingBottom = library.paddingLeft = library.paddingRight = 48;
  library.layoutSizingHorizontal = 'HUG';
  library.layoutSizingVertical = 'HUG';
  library.fills = [];
  return library;
}

/** Combines variants into component sets and places the library below the screens. */
function finishLibrary(
  api: PluginAPI,
  library: FrameNode,
  specs: ComponentSpec[],
  masters: Map<string, ComponentNode>,
  screens: FrameNode[],
): void {
  for (const spec of specs) {
    const variants = spec.variants.map((v) => masters.get(v.key)).filter((m): m is ComponentNode => !!m);
    if (variants.length === 0) continue;
    const hasProps = spec.variants.some((v) => v.name !== '');
    const description = spec.source ? `Flutter widget: ${spec.source}` : `Flutter ${spec.name}`;
    if (hasProps) {
      const set = api.combineAsVariants(variants, library);
      set.name = spec.name;
      set.description = description;
      set.layoutMode = 'HORIZONTAL';
      set.itemSpacing = 24;
      set.paddingTop = set.paddingBottom = set.paddingLeft = set.paddingRight = 24;
      set.layoutSizingHorizontal = 'HUG';
      set.layoutSizingVertical = 'HUG';
    } else {
      variants[0].name = spec.name;
      variants[0].description = description;
    }
  }
  library.x = 0;
  library.y = Math.max(0, ...screens.map((s) => s.y + s.height)) + 200;
}

/**
 * Positions children that carry a `position` (Stack children, or absolute
 * children such as a FAB inside auto layout). Runs after the parent's
 * children exist, so auto-layout sizes are known.
 */
function placeAbsoluteChildren(frame: FrameNode, children: ReadonlyArray<readonly [NodeSpec, Built]>): void {
  for (const [spec, node] of children) placeChild(frame, spec, node);
}

/**
 * Sizes, positions and constrains one child of [frame] when [frame] lays out
 * absolutely (`NONE`, a Flutter Stack) or the child is absolute in auto
 * layout. Runs as soon as the child is attached, so FILL children have their
 * real size before their own subtree is laid out, and again once siblings and
 * ancestors have their final sizes.
 */
function placeChild(frame: FrameNode, spec: NodeSpec, node: Built): void {
  const absoluteLayout = frame.layoutMode === 'NONE';
  if (!absoluteLayout && spec.layoutPositioning !== 'ABSOLUTE') return;
  const p = spec.position ?? {};
  const fillX = absoluteLayout && spec.layoutSizingHorizontal === 'FILL';
  const fillY = absoluteLayout && spec.layoutSizingVertical === 'FILL';
  const stretchX = fillX || (p.left !== undefined && p.right !== undefined);
  const stretchY = fillY || (p.top !== undefined && p.bottom !== undefined);

  // FILL inside a NONE frame, or pinned on both sides: take the parent's
  // size, minus any insets.
  let width = node.width;
  let height = node.height;
  if (stretchX) width = frame.width - (p.left ?? 0) - (p.right ?? 0);
  if (stretchY) height = frame.height - (p.top ?? 0) - (p.bottom ?? 0);
  if (width !== node.width || height !== node.height) {
    node.resize(Math.max(0.01, width), Math.max(0.01, height));
    // resize() fixes both axes. Give back hugging on any axis that isn't
    // stretched, or a child placed before its own children exist would stay
    // at its empty size.
    if (node.type === 'TEXT') {
      node.textAutoResize = stretchX && stretchY ? 'NONE' : stretchX ? 'HEIGHT' : spec.type === 'TEXT' ? spec.textAutoResize : 'NONE';
    } else if ('layoutMode' in node && node.layoutMode !== 'NONE') {
      if (!stretchX && spec.layoutSizingHorizontal === 'HUG') node.layoutSizingHorizontal = 'HUG';
      if (!stretchY && spec.layoutSizingVertical === 'HUG') node.layoutSizingVertical = 'HUG';
    }
  }

  const x = p.left ?? (p.right !== undefined ? frame.width - p.right - node.width : 0);
  const y = p.top ?? (p.bottom !== undefined ? frame.height - p.bottom - node.height : 0);
  if (spec.rotation) {
    // Turned around its top-left corner, which lands at (x, y).
    const a = (spec.rotation * Math.PI) / 180;
    node.relativeTransform = [
      [Math.cos(a), -Math.sin(a), x],
      [Math.sin(a), Math.cos(a), y],
    ];
  } else {
    node.x = x;
    node.y = y;
  }
  if ('constraints' in node) {
    // STRETCH keeps the child sized with its parent when an ancestor resizes
    // later; otherwise pin it to the side it is positioned from.
    node.constraints = {
      horizontal: stretchX ? 'STRETCH' : p.right !== undefined && p.left === undefined ? 'MAX' : 'MIN',
      vertical: stretchY ? 'STRETCH' : p.bottom !== undefined && p.top === undefined ? 'MAX' : 'MIN',
    };
  }
}

/**
 * Draws an embedded SVG inside [frame], scaled like the image's `BoxFit`
 * and centered. SCALE constraints keep it fitted if the frame resizes later.
 */
function drawSvg(api: PluginAPI, frame: FrameNode, svg: NonNullable<FrameSpec['svg']>, doc: DesignDocument): void {
  const asset = doc.images?.[svg.image];
  if (!asset || asset.format !== 'svg') throw new Error(`SVG ${svg.image} is missing from design.json`);
  const node = api.createNodeFromSvg(asset.data);
  node.name = svg.image.split('/').pop() ?? svg.image;
  frame.appendChild(node);
  const sx = frame.width / node.width;
  const sy = frame.height / node.height;
  const scale = svg.scaleMode === 'FILL' ? Math.max(sx, sy) : Math.min(sx, sy);
  if (Number.isFinite(scale) && scale > 0) node.rescale(scale);
  if (svg.scaleMode === 'FILL') frame.clipsContent = true;
  node.x = (frame.width - node.width) / 2;
  node.y = (frame.height - node.height) / 2;
  node.constraints = { horizontal: 'SCALE', vertical: 'SCALE' };
}

/**
 * Re-places every absolute child top-down once a screen is complete, so
 * each one is sized against its parent's final size. Instance subtrees are
 * skipped: they follow their master.
 */
function settle(spec: NodeSpec, built: Map<NodeSpec, Built>): void {
  if (spec.type !== 'FRAME') return;
  const frame = built.get(spec);
  if (!frame || frame.type !== 'FRAME') return;
  for (const child of spec.children) {
    const node = built.get(child);
    if (!node) continue;
    placeChild(frame, child, node);
    settle(child, built);
  }
}
