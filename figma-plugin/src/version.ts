/** The plugin's version: the flutter2figma release it ships with. Kept
 * equal to package.json and the Dart package by test/version_test.dart. */
export const PLUGIN_VERSION = '0.4.0';

/** Where people get a newer plugin: Figma Community, or a release's zip. */
export const COMMUNITY_URL = 'https://www.figma.com/community/plugin/1687559887675755742';
export const RELEASES_URL = 'https://github.com/CarlosMarioM/flutter2figma/releases/latest';
export const UPDATE_HELP = `Update it from Figma Community (${COMMUNITY_URL}) or, if the new version isn't there yet, from ${RELEASES_URL}`;

/**
 * A note naming the screens exported from the code alone (not rendered by
 * Flutter): they may show placeholders where the app decides things at
 * runtime. Rendered screens carry the origin `runtime`.
 */
export function staticNote(screens: { name: string; pluginData?: { origin?: string[] } }[]): string | undefined {
  const fromCode = screens.filter((s) => !(s.pluginData?.origin ?? []).includes('runtime')).map((s) => s.name);
  if (fromCode.length === 0) return undefined;
  const which = fromCode.length === screens.length ? 'All screens were' : `${fromCode.join(', ')}:`;
  return (
    `${which} exported from the code alone, so they may show placeholders where the app decides things at runtime. ` +
    'Export with `flutter2figma` (it runs the app) for exact screens; see its summary for why a screen fell back.'
  );
}

/** Compares `X.Y.Z` versions (a `-pre` suffix sorts before its release). */
export function compareVersions(a: string, b: string): number {
  const parse = (v: string) => {
    const [core, pre] = v.split('-', 2);
    return { parts: core.split('.').map((p) => Number.parseInt(p, 10) || 0), pre };
  };
  const x = parse(a);
  const y = parse(b);
  for (let i = 0; i < 3; i++) {
    const d = (x.parts[i] ?? 0) - (y.parts[i] ?? 0);
    if (d !== 0) return Math.sign(d);
  }
  if (x.pre === y.pre) return 0;
  if (x.pre === undefined) return 1;
  if (y.pre === undefined) return -1;
  return x.pre < y.pre ? -1 : 1;
}

/**
 * A note when [generatorVersion] (the flutter2figma that wrote the file) is
 * newer than this plugin: the file may use things this plugin draws
 * differently or not at all. The plugin has no network access, so the
 * export itself is how it learns a new version exists.
 */
export function updateNote(generatorVersion: string | undefined): string | undefined {
  if (!generatorVersion || compareVersions(generatorVersion, PLUGIN_VERSION) <= 0) return undefined;
  return (
    `This file was exported by flutter2figma ${generatorVersion}; this plugin is ${PLUGIN_VERSION}. ` +
    `To import everything in it, update the plugin. ${UPDATE_HELP}.`
  );
}
