/** The plugin's version: the flutter2figma release it ships with. Kept
 * equal to package.json and the Dart package by test/version_test.dart. */
export const PLUGIN_VERSION = '0.3.0';

/** Where people get a newer plugin. */
export const RELEASES_URL = 'https://github.com/CarlosMarioM/flutter2figma/releases/latest';

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
    `Update the plugin to import everything in it: ${RELEASES_URL}`
  );
}
