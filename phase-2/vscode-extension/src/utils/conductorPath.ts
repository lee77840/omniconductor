import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';

/**
 * Resolve the absolute path to the Conductor repo on the local filesystem.
 *
 * Resolution order:
 *   1. Workspace/user setting `conductor.repoPath` (with `~` expansion).
 *   2. Default `~/.conductor`.
 *   3. If neither exists on disk, prompt the user to select a folder.
 *
 * Verifies that the resolved path actually contains an `adapters/` directory
 * so a misconfigured value surfaces a clear error rather than a cryptic
 * `transform.sh: No such file or directory` later.
 */
export async function resolveConductorPath(): Promise<string | undefined> {
  const config = vscode.workspace.getConfiguration('conductor');
  const configured = config.get<string>('repoPath', '~/.conductor');
  const expanded = expandTilde(configured);

  if (await isValidConductorRepo(expanded)) {
    return expanded;
  }

  // Setting points to an invalid location — ask the user to pick.
  const picked = await vscode.window.showOpenDialog({
    canSelectFiles: false,
    canSelectFolders: true,
    canSelectMany: false,
    openLabel: 'Select Conductor repo folder',
    title: `Conductor not found at ${expanded}. Pick the cloned repo.`,
  });

  if (!picked || picked.length === 0) {
    return undefined;
  }

  const selected = picked[0].fsPath;
  if (!(await isValidConductorRepo(selected))) {
    vscode.window.showErrorMessage(
      `Selected folder does not look like a Conductor repo (missing 'adapters/' directory): ${selected}`,
    );
    return undefined;
  }

  // Persist for next time at user scope.
  await config.update('repoPath', selected, vscode.ConfigurationTarget.Global);
  return selected;
}

/**
 * Expand a leading `~` or `~/` to the user's home directory. Other paths
 * (absolute or relative to workspace) are passed through. Relative paths are
 * left to the caller — the extension always normalizes to absolute below.
 */
export function expandTilde(input: string): string {
  if (!input) {
    return input;
  }
  if (input === '~') {
    return os.homedir();
  }
  if (input.startsWith('~/') || input.startsWith('~\\')) {
    return path.join(os.homedir(), input.slice(2));
  }
  return path.resolve(input);
}

async function isValidConductorRepo(candidate: string): Promise<boolean> {
  try {
    const adaptersDir = path.join(candidate, 'adapters');
    const stat = await fs.promises.stat(adaptersDir);
    return stat.isDirectory();
  } catch {
    return false;
  }
}
