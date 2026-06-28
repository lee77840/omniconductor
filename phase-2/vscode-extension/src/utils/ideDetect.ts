import * as vscode from 'vscode';

export type DetectedIde = 'vscode' | 'cursor' | 'windsurf' | 'unknown';

/**
 * Heuristic IDE detection. VSCode-derived editors generally preserve the
 * VSCode extension API surface but expose their identity via:
 *   - `vscode.env.appName` ("Visual Studio Code", "Cursor", "Windsurf").
 *   - `process.env.TERM_PROGRAM` (set by the integrated terminal).
 *
 * We avoid hard failures — the recommendation surfaces in `installInteractive`
 * but the user can always override.
 */
export function detectIde(): DetectedIde {
  const appName = (vscode.env.appName || '').toLowerCase();

  if (appName.includes('cursor')) {
    return 'cursor';
  }
  if (appName.includes('windsurf')) {
    return 'windsurf';
  }
  if (appName.includes('visual studio code') || appName.includes('vscodium')) {
    return 'vscode';
  }
  return 'unknown';
}

/**
 * Map detected IDE → recommended adapter. Cursor maps to its native adapter;
 * VSCode + Windsurf both default to Copilot (the broadest single install per
 * ADR-022). Users always see all three commands in the palette.
 */
export function recommendedAdapter(
  ide: DetectedIde,
): 'claude' | 'cursor' | 'copilot' | undefined {
  switch (ide) {
    case 'cursor':
      return 'cursor';
    case 'vscode':
    case 'windsurf':
      return 'copilot';
    case 'unknown':
    default:
      return undefined;
  }
}
