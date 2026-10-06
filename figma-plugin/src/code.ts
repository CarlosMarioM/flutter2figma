import { parseDesign } from './design';
import { importDesign } from './importer';
import { PLUGIN_VERSION, updateNote } from './version';

type UiMessage = { type: 'import'; json: string } | { type: 'close' };

figma.showUI(__html__, { width: 380, height: 460, themeColors: true });
// Several copies can be installed (Community, development builds): the
// window says which one this is.
figma.ui.postMessage({ type: 'version', version: PLUGIN_VERSION });

figma.ui.onmessage = async (msg: UiMessage) => {
  if (msg.type === 'close') {
    figma.closePlugin();
    return;
  }
  try {
    const doc = parseDesign(msg.json);
    const result = await importDesign(figma, doc);
    const warnings = doc.diagnostics.filter((d) => d.severity !== 'info');
    figma.notify(
      `Imported ${result.screens.length} screens, ${result.components} components (Flutter2Figma ${PLUGIN_VERSION})`,
    );
    const update = updateNote(doc.generator?.version);
    if (update) figma.notify(update, { timeout: 10000 });
    figma.ui.postMessage({
      type: 'done',
      screens: result.screens.length,
      nodes: result.nodeCount,
      variables: result.variables,
      textStyles: result.textStyles,
      effectStyles: result.effectStyles,
      components: result.components,
      instances: result.instances,
      fontSubstitutions: result.fontSubstitutions,
      notes: result.notes,
      warnings,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    figma.notify(message, { error: true });
    figma.ui.postMessage({ type: 'error', message });
  }
};
