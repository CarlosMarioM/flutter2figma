// Types for design.json, produced by `flutter2figma export`
// (lib/src/figma/renderer.dart in the Dart package). Property names and enum values
// mirror the Figma Plugin API.

import { PLUGIN_VERSION, UPDATE_HELP } from './version';

export const DESIGN_FORMAT = 'flutter2figma/design';
export const DESIGN_VERSION = 4;

export interface DesignDocument {
  format: typeof DESIGN_FORMAT;
  version: number;
  /** The flutter2figma that wrote the file. */
  generator?: { name: string; version: string };
  name: string;
  fonts: FontName[];
  designSystem?: DesignSystemSpec;
  screens: FrameSpec[];
  /** Embedded image files, by asset name. */
  images?: Record<string, ImageAssetSpec>;
  diagnostics: Diagnostic[];
}

export interface ImageAssetSpec {
  format: 'png' | 'jpeg' | 'gif' | 'svg';
  /** Logical size in the app. */
  width: number;
  height: number;
  /** Base64 for raster formats, SVG markup for `svg`. */
  data: string;
}

export type ScaleMode = 'FILL' | 'FIT' | 'CROP';

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

/** A solid paint; `variable` names the color variable to bind. */
export interface SolidPaintSpec extends SolidPaint {
  variable?: string;
}

/** An embedded image (a key of `images`); `CROP` means stretched. */
export interface ImagePaintSpec {
  type: 'IMAGE';
  image: string;
  scaleMode: ScaleMode;
}

/** A gradient, already in Figma's shape (transform and RGBA stops). */
export type GradientPaintSpec = GradientPaint;

export type PaintSpec = SolidPaintSpec | ImagePaintSpec | GradientPaintSpec;

export interface DesignSystemSpec {
  /** Variable collection name. */
  collection: string;
  modes: string[];
  activeMode: string;
  variables: { name: string; type: 'COLOR'; values: Record<string, RGBA> }[];
  textStyles: {
    name: string;
    fontName: FontName;
    fontSize: number;
    lineHeight: LineHeight;
    letterSpacing: LetterSpacing;
  }[];
  effectStyles: { name: string; effects: DropShadowEffect[] }[];
  components: ComponentSpec[];
}

export interface ComponentSpec {
  name: string;
  source?: string;
  variants: { key: string; name: string; uses: number }[];
}

export interface InstanceSpec {
  component: string;
  /** Variant key, shared by every occurrence of that variant. */
  variant: string;
  props?: Record<string, string>;
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
  /** Degrees, clockwise, around the top-left corner that `position` places. */
  rotation?: number;
  fills: PaintSpec[];
  instance?: InstanceSpec;
  pluginData: PluginDataSpec;
}

export interface FrameSpec extends BaseSpec {
  type: 'FRAME';
  layoutMode: 'NONE' | 'HORIZONTAL' | 'VERTICAL';
  primaryAxisAlignItems?: 'MIN' | 'MAX' | 'CENTER' | 'SPACE_BETWEEN';
  counterAxisAlignItems?: 'MIN' | 'MAX' | 'CENTER' | 'BASELINE';
  itemSpacing?: number;
  /** Horizontal frames that wrap onto new rows, `counterAxisSpacing` apart. */
  layoutWrap?: 'WRAP';
  counterAxisSpacing?: number;
  paddingTop?: number;
  paddingRight?: number;
  paddingBottom?: number;
  paddingLeft?: number;
  minWidth?: number;
  minHeight?: number;
  strokes?: PaintSpec[];
  strokeWeight?: number;
  strokeAlign?: 'CENTER' | 'INSIDE' | 'OUTSIDE';
  cornerRadius?: number;
  topLeftRadius?: number;
  topRightRadius?: number;
  bottomRightRadius?: number;
  bottomLeftRadius?: number;
  effects?: (DropShadowEffect | BlurEffect)[];
  /** Effect style name the effects came from. */
  effectStyle?: string;
  clipsContent: boolean;
  /** An embedded SVG drawn inside the frame. */
  svg?: { image: string; scaleMode: ScaleMode };
  children: NodeSpec[];
}

export interface TextSpec extends BaseSpec {
  type: 'TEXT';
  characters: string;
  fontName: FontName;
  fontSize: number;
  lineHeight: LineHeight;
  letterSpacing: LetterSpacing;
  /** Text style name whose typography this matches. */
  textStyle?: string;
  textAlignHorizontal: 'LEFT' | 'CENTER' | 'RIGHT' | 'JUSTIFIED';
  textAutoResize: 'WIDTH_AND_HEIGHT' | 'HEIGHT';
  maxLines?: number;
}

/** A filled outline, such as an icon glyph; sized by its geometry. */
export interface VectorSpec extends BaseSpec {
  type: 'VECTOR';
  vectorPaths: VectorPath[];
  strokes?: PaintSpec[];
  strokeWeight?: number;
  strokeAlign?: 'CENTER' | 'INSIDE' | 'OUTSIDE';
  strokeCap?: 'NONE' | 'ROUND' | 'SQUARE';
}

export type NodeSpec = FrameSpec | TextSpec | VectorSpec;

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
      `This design.json needs a newer Flutter2Figma plugin (file format ${doc.version}; ` +
        `this plugin, ${PLUGIN_VERSION}, reads up to ${DESIGN_VERSION}). ${UPDATE_HELP}.`,
    );
  }
  return doc;
}
