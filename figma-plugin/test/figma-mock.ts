// A minimal in-memory Figma Plugin API that throws where the real API
// throws (or where Figma would silently do something we treat as a bug),
// so importer bugs surface without opening Figma.

type Sizing = 'FIXED' | 'HUG' | 'FILL';

const STYLES = ['Thin', 'ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black'];

// Like Figma: Roboto and Inter in every weight, upright and italic.
export const AVAILABLE_FONTS: FontName[] = ['Roboto', 'Inter'].flatMap((family) =>
  STYLES.flatMap((s) => [
    { family, style: s },
    { family, style: s === 'Regular' ? 'Italic' : `${s} Italic` },
  ]),
);

const key = (f: FontName) => `${f.family}/${f.style}`;

let nextId = 1;
const newId = (prefix: string) => `${prefix}:${nextId++}`;

const PAINT_KEYS = new Set(['type', 'color', 'opacity', 'visible', 'blendMode', 'boundVariables']);

/** Figma rejects paints with unknown keys or RGBA in a solid paint's color. */
function checkPaints(paints: readonly Paint[]): void {
  for (const p of paints) {
    for (const k of Object.keys(p)) {
      if (!PAINT_KEYS.has(k)) throw new Error(`Unrecognized key "${k}" in paint`);
    }
    if (p.type === 'SOLID' && 'a' in p.color) throw new Error('Solid paint color must be RGB (use opacity)');
  }
}

export class MockNode {
  id = newId('node');
  name = '';
  x = 0;
  y = 0;
  // Stored size. `width`/`height` are computed like Figma's layout engine:
  // FILL takes the leftover space of an auto-layout parent, HUG sums the
  // children, STRETCH constraints follow a NONE parent's size.
  private _w = 100;
  private _h = 100;
  private _constraints: Constraints = { horizontal: 'MIN', vertical: 'MIN' };
  // Margins to the parent's edges, recorded when constraints are set.
  private _anchors: { left: number; right: number; top: number; bottom: number } | null = null;
  parent: MockContainer | null = null;
  private _layoutPositioning: 'AUTO' | 'ABSOLUTE' = 'AUTO';
  private _fills: Paint[] = [];
  pluginData = new Map<string, string>();
  explicitModes = new Map<string, string>();
  private sizing: Record<'Horizontal' | 'Vertical', Sizing> = { Horizontal: 'FIXED', Vertical: 'FIXED' };

  constructor(public type: string) {}

  get fills(): Paint[] {
    return this._fills;
  }
  set fills(v: Paint[]) {
    checkPaints(v);
    this._fills = v;
  }

  get width(): number {
    return this.size('Horizontal');
  }
  get height(): number {
    return this.size('Vertical');
  }

  get constraints(): Constraints {
    return this._constraints;
  }
  set constraints(c: Constraints) {
    this._constraints = c;
    const p = this.parent;
    this._anchors = p
      ? { left: this.x, right: p.width - this.x - this.width, top: this.y, bottom: p.height - this.y - this.height }
      : null;
  }

  sizingOf(axis: 'Horizontal' | 'Vertical'): Sizing {
    return this.sizing[axis];
  }

  private size(axis: 'Horizontal' | 'Vertical'): number {
    const horizontal = axis === 'Horizontal';
    const parent = this.parent;
    if (parent instanceof MockFrame && this.layoutPositioning === 'AUTO') {
      if (parent.isAutoLayout && this.sizing[axis] === 'FILL') return parent.fillSizeFor(axis);
      const stretch = this._constraints[horizontal ? 'horizontal' : 'vertical'] === 'STRETCH';
      if (!parent.isAutoLayout && stretch && this._anchors) {
        const margins = horizontal ? this._anchors.left + this._anchors.right : this._anchors.top + this._anchors.bottom;
        return Math.max(0.01, (horizontal ? parent.width : parent.height) - margins);
      }
    }
    if (this.sizing[axis] === 'HUG' && this instanceof MockFrame && this.isAutoLayout) return this.hugSize(axis);
    return horizontal ? this._w : this._h;
  }

  resize(width: number, height: number) {
    if (!(width >= 0.01 && height >= 0.01)) throw new Error(`resize(${width}, ${height}): must be >= 0.01`);
    this._w = width;
    this._h = height;
    // Like Figma: resizing turns HUG/FILL into FIXED.
    this.sizing = { Horizontal: 'FIXED', Vertical: 'FIXED' };
  }

  setPluginData(k: string, value: string) {
    if (typeof value !== 'string') throw new Error('pluginData must be a string');
    this.pluginData.set(k, value);
  }

  setExplicitVariableModeForCollection(collection: unknown, modeId: string) {
    if (!(collection instanceof MockCollection)) {
      throw new Error('dynamic-page: pass a VariableCollection, not an id');
    }
    if (!collection.modes.some((m) => m.modeId === modeId)) throw new Error(`Unknown mode ${modeId}`);
    this.explicitModes.set(collection.id, modeId);
  }

  get isAutoLayout(): boolean {
    return false;
  }

  get layoutPositioning() {
    return this._layoutPositioning;
  }
  set layoutPositioning(v: 'AUTO' | 'ABSOLUTE') {
    if (v === 'ABSOLUTE' && !(this.parent && this.parent.isAutoLayout)) {
      throw new Error(`${this.name}: ABSOLUTE positioning needs an auto-layout parent`);
    }
    this._layoutPositioning = v;
  }

  get layoutSizingHorizontal(): Sizing {
    return this.sizing.Horizontal;
  }
  set layoutSizingHorizontal(v: Sizing) {
    this.setSizing('Horizontal', v);
  }
  get layoutSizingVertical(): Sizing {
    return this.sizing.Vertical;
  }
  set layoutSizingVertical(v: Sizing) {
    this.setSizing('Vertical', v);
  }

  private setSizing(axis: 'Horizontal' | 'Vertical', v: Sizing) {
    if (v === 'HUG' && !(this.type === 'TEXT' || this.isAutoLayout)) {
      throw new Error(`${this.name}: HUG is only valid on auto-layout frames and text`);
    }
    if (v === 'FILL') {
      if (!this.parent || !this.parent.isAutoLayout) {
        throw new Error(`${this.name}: FILL is only valid in an auto-layout parent`);
      }
      if (this.layoutPositioning === 'ABSOLUTE') {
        throw new Error(`${this.name}: FILL is not valid on absolute children`);
      }
      const parentAxis = this.parent.sizing[axis];
      if (parentAxis === 'HUG') {
        // Real Figma silently converts the parent to FIXED; treat it as an
        // exporter bug so it is caught.
        throw new Error(`${this.name}: FILL ${axis.toLowerCase()} inside a parent that hugs`);
      }
    }
    this.sizing[axis] = v;
  }

  detach() {
    if (!this.parent) return;
    const siblings = this.parent.children;
    siblings.splice(siblings.indexOf(this), 1);
    this.parent = null;
  }

  /** Copies this node's own state (not its place in the tree) into [target]. */
  cloneAs<T extends MockNode>(target: T): T {
    const type = target.type;
    Object.assign(target, this);
    target.type = type;
    target.id = newId('node');
    target.parent = null;
    target.pluginData = new Map(this.pluginData);
    target.explicitModes = new Map(this.explicitModes);
    (target as MockNode).sizing = { ...this.sizing };
    return target;
  }

  clone(): MockNode {
    return this.cloneAs(new MockNode(this.type));
  }
}

export class MockContainer extends MockNode {
  children: MockNode[] = [];

  appendChild(child: MockNode) {
    child.detach();
    child.parent = this;
    this.children.push(child);
  }

  insertChild(index: number, child: MockNode) {
    child.detach();
    child.parent = this;
    this.children.splice(index, 0, child);
  }

  override cloneAs<T extends MockNode>(target: T): T {
    super.cloneAs(target);
    const container = target as unknown as MockContainer;
    container.children = [];
    for (const child of this.children) container.appendChild(child.clone());
    return target;
  }
}

export class MockFrame extends MockContainer {
  private _layoutMode: 'NONE' | 'HORIZONTAL' | 'VERTICAL' = 'NONE';
  private _minWidth: number | null = null;
  private _minHeight: number | null = null;
  primaryAxisAlignItems = 'MIN';
  counterAxisAlignItems = 'MIN';
  itemSpacing = 0;
  paddingTop = 0;
  paddingRight = 0;
  paddingBottom = 0;
  paddingLeft = 0;
  private _strokes: Paint[] = [];
  strokeWeight = 1;
  strokeAlign = 'INSIDE';
  cornerRadius = 0;
  topLeftRadius = 0;
  topRightRadius = 0;
  bottomRightRadius = 0;
  bottomLeftRadius = 0;
  effects: Effect[] = [];
  effectStyleId = '';
  clipsContent = true;

  constructor(
    type = 'FRAME',
    protected readonly registry?: MockRegistry,
  ) {
    super(type);
  }

  get strokes(): Paint[] {
    return this._strokes;
  }
  set strokes(v: Paint[]) {
    checkPaints(v);
    this._strokes = v;
  }

  get layoutMode() {
    return this._layoutMode;
  }
  set layoutMode(v) {
    this._layoutMode = v;
  }

  override get isAutoLayout() {
    return this._layoutMode !== 'NONE';
  }

  get minWidth() {
    return this._minWidth;
  }
  set minWidth(v: number | null) {
    if (!this.isAutoLayout) throw new Error(`${this.name}: minWidth needs auto layout`);
    this._minWidth = v;
  }
  get minHeight() {
    return this._minHeight;
  }
  set minHeight(v: number | null) {
    if (!this.isAutoLayout) throw new Error(`${this.name}: minHeight needs auto layout`);
    this._minHeight = v;
  }

  private isMainAxis(axis: 'Horizontal' | 'Vertical'): boolean {
    return (this.layoutMode === 'HORIZONTAL') === (axis === 'Horizontal');
  }

  private padding(axis: 'Horizontal' | 'Vertical'): number {
    return axis === 'Horizontal' ? this.paddingLeft + this.paddingRight : this.paddingTop + this.paddingBottom;
  }

  /** Size of each FILL child on [axis]: the leftover space, shared. */
  fillSizeFor(axis: 'Horizontal' | 'Vertical'): number {
    const inner = (axis === 'Horizontal' ? this.width : this.height) - this.padding(axis);
    if (!this.isMainAxis(axis)) return Math.max(0.01, inner);
    const flow = this.children.filter((c) => c.layoutPositioning === 'AUTO');
    const fills = flow.filter((c) => c.sizingOf(axis) === 'FILL').length;
    const others = flow
      .filter((c) => c.sizingOf(axis) !== 'FILL')
      .reduce((sum, c) => sum + (axis === 'Horizontal' ? c.width : c.height), 0);
    const gaps = this.itemSpacing * Math.max(0, flow.length - 1);
    return Math.max(0.01, (inner - others - gaps) / Math.max(1, fills));
  }

  /** HUG: children (summed on the main axis, max on the cross axis) + padding. */
  hugSize(axis: 'Horizontal' | 'Vertical'): number {
    const flow = this.children.filter((c) => c.layoutPositioning === 'AUTO');
    const sizes = flow.map((c) => (axis === 'Horizontal' ? c.width : c.height));
    const content = this.isMainAxis(axis)
      ? sizes.reduce((a, b) => a + b, 0) + this.itemSpacing * Math.max(0, flow.length - 1)
      : Math.max(0, ...sizes);
    const min = axis === 'Horizontal' ? this.minWidth : this.minHeight;
    return Math.max(0.01, content + this.padding(axis), min ?? 0);
  }

  async setEffectStyleIdAsync(id: string) {
    const style = this.registry?.effectStyles.get(id);
    if (!style) throw new Error(`Unknown effect style ${id}`);
    this.effects = style.effects;
    this.effectStyleId = id;
  }

  override clone(): MockNode {
    return this.cloneAs(new MockFrame(this.type, this.registry));
  }
}

export class MockComponent extends MockFrame {
  description = '';

  constructor(registry?: MockRegistry) {
    super('COMPONENT', registry);
  }

  createInstance(): MockInstance {
    const instance = this.cloneAs(new MockInstance(this.registry));
    instance.mainComponent = this;
    return instance;
  }
}

export class MockInstance extends MockFrame {
  mainComponent: MockComponent | null = null;

  constructor(registry?: MockRegistry) {
    super('INSTANCE', registry);
  }

  override clone(): MockNode {
    const copy = this.cloneAs(new MockInstance(this.registry));
    copy.mainComponent = this.mainComponent;
    return copy;
  }
}

export class MockComponentSet extends MockFrame {
  description = '';

  constructor(registry?: MockRegistry) {
    super('COMPONENT_SET', registry);
  }
}

export class MockText extends MockNode {
  private _fontName: FontName = { family: 'Inter', style: 'Regular' };
  private _characters = '';
  fontSize = 12;
  lineHeight: LineHeight = { unit: 'AUTO' };
  letterSpacing: LetterSpacing = { unit: 'PIXELS', value: 0 };
  textAlignHorizontal = 'LEFT';
  textAutoResize = 'NONE';
  textTruncation = 'DISABLED';
  maxLines: number | null = null;
  textStyleId = '';

  constructor(private readonly registry: MockRegistry) {
    super('TEXT');
  }

  get fontName() {
    return this._fontName;
  }
  set fontName(f: FontName) {
    if (!this.registry.loaded.has(key(f))) throw new Error(`Font ${key(f)} not loaded`);
    this._fontName = f;
  }

  get characters() {
    return this._characters;
  }
  set characters(v: string) {
    if (!this.registry.loaded.has(key(this._fontName))) throw new Error(`Font ${key(this._fontName)} not loaded`);
    this._characters = v;
  }

  // Auto-resizing text measures its content: one line of the line height,
  // with glyphs approximated as 0.6em wide (no real font metrics here).
  override get width(): number {
    if (this.textAutoResize !== 'WIDTH_AND_HEIGHT') return super.width;
    return Math.max(0.01, this._characters.length * this.fontSize * 0.6);
  }
  override get height(): number {
    if (this.textAutoResize !== 'WIDTH_AND_HEIGHT' && this.textAutoResize !== 'HEIGHT') return super.height;
    const lh = this.lineHeight;
    if (lh.unit === 'PIXELS') return lh.value;
    if (lh.unit === 'PERCENT') return (this.fontSize * lh.value) / 100;
    return this.fontSize * 1.2;
  }

  async setTextStyleIdAsync(id: string) {
    const style = this.registry.textStyles.get(id);
    if (!style) throw new Error(`Unknown text style ${id}`);
    this.fontName = style.fontName;
    this.fontSize = style.fontSize;
    this.lineHeight = style.lineHeight;
    this.letterSpacing = style.letterSpacing;
    this.textStyleId = id;
  }

  override clone(): MockNode {
    return this.cloneAs(new MockText(this.registry));
  }
}

// Figma's vector path grammar: absolute M/L/Q/C/Z, space-separated numbers.
const PATH_DATA = /^(?:[MLQCZ](?: -?\d+(?:\.\d+)?)*)(?: [MLQCZ](?: -?\d+(?:\.\d+)?)*)*$/;

export class MockVector extends MockNode {
  private _paths: VectorPath[] = [];

  constructor() {
    super('VECTOR');
  }

  get vectorPaths(): VectorPath[] {
    return this._paths;
  }
  /** Like Figma, the node takes the size of its geometry. */
  set vectorPaths(paths: VectorPath[]) {
    let maxX = 0.01;
    let maxY = 0.01;
    for (const path of paths) {
      if (!PATH_DATA.test(path.data)) throw new Error(`Invalid vector path data: ${path.data.slice(0, 40)}`);
      if (path.windingRule !== 'NONZERO' && path.windingRule !== 'EVENODD') throw new Error('Bad winding rule');
      // On-curve points (each command's last pair) bound the geometry;
      // control points may stick out.
      for (const command of path.data.match(/[MLQC][^MLQCZ]*/g) ?? []) {
        const numbers = command.slice(1).trim().split(' ').map(Number);
        const [x, y] = numbers.slice(-2);
        if (x < -0.01 || y < -0.01) throw new Error('Exported paths start at 0,0');
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
    this._paths = paths;
    this.resize(maxX, maxY);
  }

  override clone(): MockNode {
    return this.cloneAs(new MockVector());
  }
}

export class MockPage extends MockContainer {
  selection: MockNode[] = [];
  constructor() {
    super('PAGE');
  }
}

// ---------------------------------------------------------------------------
// Variables and styles
// ---------------------------------------------------------------------------

export class MockCollection {
  id = newId('collection');
  modes: { modeId: string; name: string }[];
  defaultModeId: string;

  constructor(
    public name: string,
    private readonly maxModes: number,
  ) {
    this.defaultModeId = newId('mode');
    this.modes = [{ modeId: this.defaultModeId, name: 'Mode 1' }];
  }

  addMode(name: string): string {
    if (this.modes.length >= this.maxModes) throw new Error(`Limited to ${this.maxModes} mode(s) on this plan`);
    const modeId = newId('mode');
    this.modes.push({ modeId, name });
    return modeId;
  }

  renameMode(modeId: string, name: string) {
    const mode = this.modes.find((m) => m.modeId === modeId);
    if (!mode) throw new Error(`Unknown mode ${modeId}`);
    mode.name = name;
  }
}

export class MockVariable {
  id = newId('variable');
  valuesByMode: Record<string, RGBA> = {};

  constructor(
    public name: string,
    public readonly collection: MockCollection,
    public readonly resolvedType: string,
  ) {}

  get variableCollectionId() {
    return this.collection.id;
  }

  setValueForMode(modeId: string, value: RGBA) {
    if (!this.collection.modes.some((m) => m.modeId === modeId)) throw new Error(`Unknown mode ${modeId}`);
    for (const c of ['r', 'g', 'b', 'a'] as const) {
      if (typeof value[c] !== 'number') throw new Error(`COLOR value needs r, g, b, a (missing ${c})`);
    }
    this.valuesByMode[modeId] = value;
  }
}

export class MockTextStyle {
  id = newId('textStyle');
  name = '';
  private _fontName: FontName = { family: 'Inter', style: 'Regular' };
  fontSize = 12;
  lineHeight: LineHeight = { unit: 'AUTO' };
  letterSpacing: LetterSpacing = { unit: 'PIXELS', value: 0 };

  constructor(private readonly loaded: Set<string>) {}

  get fontName() {
    return this._fontName;
  }
  set fontName(f: FontName) {
    if (!this.loaded.has(key(f))) throw new Error(`Font ${key(f)} not loaded`);
    this._fontName = f;
  }
}

export class MockEffectStyle {
  id = newId('effectStyle');
  name = '';
  effects: Effect[] = [];
}

export interface MockRegistry {
  loaded: Set<string>;
  textStyles: Map<string, MockTextStyle>;
  effectStyles: Map<string, MockEffectStyle>;
}

/** [maxModes] simulates a Figma plan's limit on variable modes. */
export function createMockFigma(options: { maxModes?: number } = {}) {
  const registry: MockRegistry = { loaded: new Set(), textStyles: new Map(), effectStyles: new Map() };
  const pages: MockPage[] = [];
  const notifications: string[] = [];
  const collections: MockCollection[] = [];
  const variables: MockVariable[] = [];

  const api = {
    pages,
    collections,
    variableList: variables,
    loaded: registry.loaded,
    textStyleList: () => [...registry.textStyles.values()],
    effectStyleList: () => [...registry.effectStyles.values()],
    notifications,
    currentPage: null as MockPage | null,
    createPage() {
      const page = new MockPage();
      pages.push(page);
      return page;
    },
    async setCurrentPageAsync(page: MockPage) {
      api.currentPage = page;
    },
    createFrame: () => new MockFrame('FRAME', registry),
    createText: () => new MockText(registry),
    createVector: () => new MockVector(),
    createComponentFromNode(node: MockNode) {
      if (!(node instanceof MockFrame) || node.type !== 'FRAME') throw new Error('createComponentFromNode needs a frame');
      const parent = node.parent;
      if (!parent) throw new Error('createComponentFromNode needs an attached node');
      const component = new MockComponent(registry);
      const children = [...node.children];
      node.cloneAs(component);
      component.children = [];
      for (const child of children) component.appendChild(child);
      parent.insertChild(parent.children.indexOf(node), component);
      node.detach();
      return component;
    },
    combineAsVariants(nodes: MockNode[], parent: MockContainer) {
      if (nodes.length === 0) throw new Error('combineAsVariants needs at least one component');
      for (const n of nodes) {
        if (!(n instanceof MockComponent)) throw new Error('combineAsVariants only accepts components');
        if (!/^[^=,]+=[^=,]+(, [^=,]+=[^=,]+)*$/.test(n.name)) {
          throw new Error(`Variant name "${n.name}" is not "Prop=Value, ..."`);
        }
      }
      const set = new MockComponentSet(registry);
      parent.appendChild(set);
      for (const n of nodes) set.appendChild(n);
      return set;
    },
    async loadFontAsync(font: FontName) {
      if (!AVAILABLE_FONTS.some((f) => key(f) === key(font))) {
        throw new Error(`Font ${key(font)} is not available`);
      }
      registry.loaded.add(key(font));
    },
    async listAvailableFontsAsync() {
      return AVAILABLE_FONTS.map((fontName) => ({ fontName }));
    },
    createTextStyle() {
      const style = new MockTextStyle(registry.loaded);
      registry.textStyles.set(style.id, style);
      return style;
    },
    async getLocalTextStylesAsync() {
      return [...registry.textStyles.values()];
    },
    createEffectStyle() {
      const style = new MockEffectStyle();
      registry.effectStyles.set(style.id, style);
      return style;
    },
    async getLocalEffectStylesAsync() {
      return [...registry.effectStyles.values()];
    },
    variables: {
      async getLocalVariableCollectionsAsync() {
        return [...collections];
      },
      async getLocalVariablesAsync(type?: string) {
        return variables.filter((v) => !type || v.resolvedType === type);
      },
      createVariableCollection(name: string) {
        const c = new MockCollection(name, options.maxModes ?? 4);
        collections.push(c);
        return c;
      },
      createVariable(name: string, collection: unknown, type: string) {
        if (!(collection instanceof MockCollection)) {
          throw new Error('dynamic-page: pass a VariableCollection, not an id');
        }
        if (variables.some((v) => v.collection === collection && v.name === name)) {
          throw new Error(`Variable "${name}" already exists`);
        }
        const v = new MockVariable(name, collection, type);
        variables.push(v);
        return v;
      },
      setBoundVariableForPaint(paint: SolidPaint, field: string, variable: MockVariable) {
        checkPaints([paint]);
        if (field !== 'color') throw new Error(`Cannot bind ${field}`);
        return { ...paint, boundVariables: { color: { type: 'VARIABLE_ALIAS', id: variable.id } } };
      },
    },
    viewport: { scrollAndZoomIntoView() {} },
    notify(message: string) {
      notifications.push(message);
    },
  };
  return api;
}
