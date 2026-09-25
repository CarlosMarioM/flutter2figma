// Types for design.json, produced by `flutter2figma export`
// (packages/figma/lib/src/renderer.dart). Property names and enum values
// mirror the Figma Plugin API.

export const DESIGN_FORMAT = 'flutter2figma/design';
export const DESIGN_VERSION = 1;

export interface DesignDocument {
  format: typeof DESIGN_FORMAT;
  version: number;
  name: string;
  fonts: FontName[];
  screens: FrameSpec[];
  diagnostics: Diagnostic[];
}

export interface Diagnostic {
  severity: 'info' | 'warning' | 'error';
  message: string;
  source?: string;
}

export interface Position {
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
}

export interface PluginDataSpec {
  origin?: string[];
  source?: string;
  role?: string;
}

interface BaseSpec {
  name: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  layoutSizingHorizontal: 'FIXED' | 'HUG' | 'FILL';
  layoutSizingVertical: 'FIXED' | 'HUG' | 'FILL';
  layoutPositioning?: 'AUTO' | 'ABSOLUTE';
  position?: Position;
  fills: SolidPaint[];
  pluginData: PluginDataSpec;
}

export interface FrameSpec extends BaseSpec {
  type: 'FRAME';
  layoutMode: 'NONE' | 'HORIZONTAL' | 'VERTICAL';
  primaryAxisAlignItems?: 'MIN' | 'MAX' | 'CENTER' | 'SPACE_BETWEEN';
  counterAxisAlignItems?: 'MIN' | 'MAX' | 'CENTER' | 'BASELINE';
  itemSpacing?: number;
  paddingTop?: number;
  paddingRight?: number;
  paddingBottom?: number;
  paddingLeft?: number;
  minWidth?: number;
  minHeight?: number;
  strokes?: SolidPaint[];
  strokeWeight?: number;
  strokeAlign?: 'CENTER' | 'INSIDE' | 'OUTSIDE';
  cornerRadius?: number;
  topLeftRadius?: number;
  topRightRadius?: number;
  bottomRightRadius?: number;
  bottomLeftRadius?: number;
  effects?: DropShadowEffect[];
  clipsContent: boolean;
  children: NodeSpec[];
}

export interface TextSpec extends BaseSpec {
  type: 'TEXT';
  characters: string;
  fontName: FontName;
  fontSize: number;
  lineHeight: LineHeight;
  letterSpacing: LetterSpacing;
  textAlignHorizontal: 'LEFT' | 'CENTER' | 'RIGHT' | 'JUSTIFIED';
  textAutoResize: 'WIDTH_AND_HEIGHT' | 'HEIGHT';
  maxLines?: number;
}

export type NodeSpec = FrameSpec | TextSpec;

export function parseDesign(text: string): DesignDocument {
  let doc: DesignDocument;
  try {
    doc = JSON.parse(text);
  } catch (e) {
    throw new Error(`Not valid JSON: ${(e as Error).message}`);
  }
  if (!doc || doc.format !== DESIGN_FORMAT) {
    throw new Error('Not a Flutter2Figma design.json (missing "format": "flutter2figma/design").');
  }
  if (doc.version > DESIGN_VERSION) {
    throw new Error(
      `design.json version ${doc.version} is newer than this plugin supports (${DESIGN_VERSION}). Update the plugin.`,
    );
  }
  return doc;
}
