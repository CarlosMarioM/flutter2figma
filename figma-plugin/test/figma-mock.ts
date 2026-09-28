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
  width = 100;
  height = 100;
  parent: MockContainer | null = null;
  private _layoutPositioning: 'AUTO' | 'ABSOLUTE' = 'AUTO';
  constraints: Constraints = { horizontal: 'MIN', vertical: 'MIN' };
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

  resize(width: number, height: number) {
    if (!(width >= 0.01 && height >= 0.01)) throw new Error(`resize(${width}, ${height}): must be >= 0.01`);
    this.width = width;
    this.height = height;
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
