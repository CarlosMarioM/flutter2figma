import { parseDesign } from './design';
import { importDesign } from './importer';

type UiMessage = { type: 'import'; json: string } | { type: 'close' };

figma.showUI(__html__, { width: 380, height: 460, themeColors: true });

figma.ui.onmessage = async (msg: UiMessage) => {
  if (msg.type === 'close') {
    figma.closePlugin();
    return;
  }
  try {
    const doc = parseDesign(msg.json);
    const result = await importDesign(figma, doc);
    const warnings = doc.diagnostics.filter((d) => d.severity !== 'info');
    figma.notify(`Imported ${result.screens.length} screens (${result.nodeCount} layers)`);
    figma.ui.postMessage({
      type: 'done',
      screens: result.screens.length,
      nodes: result.nodeCount,
      fontSubstitutions: result.fontSubstitutions,
      warnings,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    figma.notify(message, { error: true });
    figma.ui.postMessage({ type: 'error', message });
  }
};
