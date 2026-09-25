// A minimal in-memory Figma Plugin API that throws where the real API
// throws, so importer bugs surface without opening Figma.

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

export class MockNode {
  name = '';
  x = 0;
  y = 0;
  width = 100;
  height = 100;
  parent: MockContainer | null = null;
  private _layoutPositioning: 'AUTO' | 'ABSOLUTE' = 'AUTO';
  constraints: Constraints = { horizontal: 'MIN', vertical: 'MIN' };
  fills: Paint[] = [];
  readonly pluginData = new Map<string, string>();
  private sizing: Record<'Horizontal' | 'Vertical', Sizing> = { Horizontal: 'FIXED', Vertical: 'FIXED' };

  constructor(readonly type: string) {}

  resize(width: number, height: number) {
    if (!(width >= 0.01 && height >= 0.01)) throw new Error(`resize(${width}, ${height}): must be >= 0.01`);
    this.width = width;
    this.height = height;
  }

  setPluginData(k: string, value: string) {
    if (typeof value !== 'string') throw new Error('pluginData must be a string');
    this.pluginData.set(k, value);
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
}

export class MockContainer extends MockNode {
  children: MockNode[] = [];

  appendChild(child: MockNode) {
    child.parent = this;
    this.children.push(child);
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
  strokes: Paint[] = [];
  strokeWeight = 1;
  strokeAlign = 'INSIDE';
  cornerRadius = 0;
  topLeftRadius = 0;
  topRightRadius = 0;
  bottomRightRadius = 0;
  bottomLeftRadius = 0;
  effects: Effect[] = [];
  clipsContent = true;

  constructor() {
    super('FRAME');
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

  constructor(private readonly loaded: Set<string>) {
    super('TEXT');
  }

  get fontName() {
    return this._fontName;
  }
  set fontName(f: FontName) {
    if (!this.loaded.has(key(f))) throw new Error(`Font ${key(f)} not loaded`);
    this._fontName = f;
  }

  get characters() {
    return this._characters;
  }
  set characters(v: string) {
    if (!this.loaded.has(key(this._fontName))) throw new Error(`Font ${key(this._fontName)} not loaded`);
    this._characters = v;
  }
}

export class MockPage extends MockContainer {
  selection: MockNode[] = [];
  constructor() {
    super('PAGE');
  }
}

export function createMockFigma() {
  const loaded = new Set<string>();
  const pages: MockPage[] = [];
  const notifications: string[] = [];
  const api = {
    pages,
    loaded,
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
    createFrame: () => new MockFrame(),
    createText: () => new MockText(loaded),
    async loadFontAsync(font: FontName) {
      if (!AVAILABLE_FONTS.some((f) => key(f) === key(font))) {
        throw new Error(`Font ${key(font)} is not available`);
      }
      loaded.add(key(font));
    },
    async listAvailableFontsAsync() {
      return AVAILABLE_FONTS.map((fontName) => ({ fontName }));
    },
    viewport: { scrollAndZoomIntoView() {} },
    notify(message: string) {
      notifications.push(message);
    },
  };
  return api;
}
