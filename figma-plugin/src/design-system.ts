import type { DesignSystemSpec, PaintSpec } from './design';

/** Figma objects created (or reused) for a design.json design system. */
export interface DesignSystem {
  collection: VariableCollection;
  /** Mode name → mode id. Only modes Figma accepted (plans limit modes). */
  modeIds: Map<string, string>;
  activeModeId: string;
  variables: Map<string, Variable>;
  textStyles: Map<string, TextStyle>;
  effectStyles: Map<string, EffectStyle>;
  /** Problems worth telling the user, e.g. a mode the plan doesn't allow. */
  notes: string[];
}

/**
 * Creates the variable collection, color variables, text styles and effect
 * styles. Re-importing updates existing ones (matched by name) instead of
 * duplicating them.
 */
export async function setupDesignSystem(
  api: PluginAPI,
  spec: DesignSystemSpec,
  fontFor: (font: FontName) => FontName,
): Promise<DesignSystem> {
  const notes: string[] = [];

  const collection =
    (await api.variables.getLocalVariableCollectionsAsync()).find((c) => c.name === spec.collection) ??
    api.variables.createVariableCollection(spec.collection);

  // Modes: reuse by name; a fresh collection's default mode takes the first.
  const modeIds = new Map<string, string>();
  for (const [i, name] of spec.modes.entries()) {
    const existing = collection.modes.find((m) => m.name === name);
    if (existing) {
      modeIds.set(name, existing.modeId);
    } else if (i === 0 && !collection.modes.some((m) => spec.modes.includes(m.name))) {
      collection.renameMode(collection.defaultModeId, name);
      modeIds.set(name, collection.defaultModeId);
    } else {
      try {
        modeIds.set(name, collection.addMode(name));
      } catch (e) {
        notes.push(`Mode "${name}" not created (${(e as Error).message}); your Figma plan may limit modes.`);
      }
    }
  }
  const activeModeId = modeIds.get(spec.activeMode) ?? collection.defaultModeId;

  const existingVariables = new Map(
    (await api.variables.getLocalVariablesAsync('COLOR'))
      .filter((v) => v.variableCollectionId === collection.id)
      .map((v) => [v.name, v] as const),
  );
  const variables = new Map<string, Variable>();
  for (const v of spec.variables) {
    const variable = existingVariables.get(v.name) ?? api.variables.createVariable(v.name, collection, 'COLOR');
    for (const [mode, value] of Object.entries(v.values)) {
      const modeId = modeIds.get(mode);
      if (modeId) variable.setValueForMode(modeId, value);
    }
    variables.set(v.name, variable);
  }

  const existingText = new Map((await api.getLocalTextStylesAsync()).map((s) => [s.name, s] as const));
  const textStyles = new Map<string, TextStyle>();
  for (const t of spec.textStyles) {
    const style = existingText.get(t.name) ?? api.createTextStyle();
    style.name = t.name;
    style.fontName = fontFor(t.fontName);
    style.fontSize = t.fontSize;
    style.lineHeight = t.lineHeight;
    style.letterSpacing = t.letterSpacing;
    textStyles.set(t.name, style);
  }

  const existingEffects = new Map((await api.getLocalEffectStylesAsync()).map((s) => [s.name, s] as const));
  const effectStyles = new Map<string, EffectStyle>();
  for (const e of spec.effectStyles) {
    const style = existingEffects.get(e.name) ?? api.createEffectStyle();
    style.name = e.name;
    style.effects = e.effects;
    effectStyles.set(e.name, style);
  }

  return { collection, modeIds, activeModeId, variables, textStyles, effectStyles, notes };
}

/**
 * Converts paint specs to Figma paints, binding each `variable` to its color
 * variable. The paint keeps its opacity, so `onSurface` at 38% stays bound
 * to `onSurface`.
 */
export function toPaints(api: PluginAPI, specs: PaintSpec[], ds: DesignSystem | null): SolidPaint[] {
  return specs.map(({ variable, ...paint }) => {
    const bound = variable ? ds?.variables.get(variable) : undefined;
    return bound ? api.variables.setBoundVariableForPaint(paint, 'color', bound) : paint;
  });
}
