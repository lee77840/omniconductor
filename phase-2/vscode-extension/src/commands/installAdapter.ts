import * as path from 'path';
import * as vscode from 'vscode';
import { resolveConductorPath } from '../utils/conductorPath';
import { detectBash, runBashScript } from '../utils/shellExec';

export type AdapterId = 'claude' | 'cursor' | 'copilot';

const ADAPTER_LABELS: Record<AdapterId, string> = {
  claude: 'Claude Code',
  cursor: 'Cursor',
  copilot: 'GitHub Copilot',
};

/**
 * Run `<conductor>/adapters/<id>/transform.sh <workspace> [args]` with
 * progress reporting + an output channel + a status-bar success/failure
 * notification. All three command entry points funnel through here.
 */
export async function installAdapter(
  adapterId: AdapterId,
  outputChannel: vscode.OutputChannel,
): Promise<void> {
  // 1. Locate workspace root.
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders || workspaceFolders.length === 0) {
    vscode.window.showErrorMessage(
      'Conductor: open a project folder first — there is no workspace to install into.',
    );
    return;
  }

  let workspaceFolder = workspaceFolders[0];
  if (workspaceFolders.length > 1) {
    const picked = await vscode.window.showWorkspaceFolderPick({
      placeHolder: 'Pick the project to install Conductor rules into',
    });
    if (!picked) {
      return;
    }
    workspaceFolder = picked;
  }
  const workspacePath = workspaceFolder.uri.fsPath;

  // 2. Locate Conductor repo.
  const conductorPath = await resolveConductorPath();
  if (!conductorPath) {
    return;
  }

  // 3. Locate bash.
  const launcher = await detectBash();
  if (!launcher) {
    const action = await vscode.window.showErrorMessage(
      'Conductor needs bash. Install Git for Windows (bundles Git Bash) or enable WSL2.',
      'Open Git for Windows download',
    );
    if (action) {
      vscode.env.openExternal(vscode.Uri.parse('https://gitforwindows.org'));
    }
    return;
  }

  // 4. Build script + args.
  const scriptPath = path.join(conductorPath, 'adapters', adapterId, 'transform.sh');
  const config = vscode.workspace.getConfiguration('conductor');
  const recipes = config.get<string>('recipes', '').trim();
  const dryRun = config.get<boolean>('dryRun', false);

  const args = [workspacePath];
  if (recipes) {
    args.push(`--recipes=${recipes}`);
  }
  if (dryRun) {
    args.push('--dry-run');
  }

  // 5. Run with progress.
  outputChannel.show(true);
  outputChannel.appendLine(
    `\n=== Conductor: installing ${ADAPTER_LABELS[adapterId]} rules into ${workspacePath} ===`,
  );

  const result = await vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      title: `Conductor: installing ${ADAPTER_LABELS[adapterId]} rules`,
      cancellable: true,
    },
    async (progress, token) => {
      progress.report({ message: 'running transform.sh…' });
      try {
        return await runBashScript(scriptPath, args, launcher, {
          cwd: conductorPath,
          outputChannel,
          cancellationToken: token,
        });
      } catch (err) {
        outputChannel.appendLine(
          `[conductor] spawn failed: ${err instanceof Error ? err.message : String(err)}`,
        );
        return { exitCode: -1, stdout: '', stderr: String(err) };
      }
    },
  );

  // 6. Surface outcome.
  if (result.exitCode === 0) {
    vscode.window.setStatusBarMessage(
      `$(check) Conductor: ${ADAPTER_LABELS[adapterId]} rules installed`,
      5000,
    );
    vscode.window.showInformationMessage(
      `Conductor: ${ADAPTER_LABELS[adapterId]} rules installed${
        dryRun ? ' (dry-run preview)' : ''
      }. See output panel for details.`,
    );
  } else {
    vscode.window.setStatusBarMessage(
      `$(error) Conductor: install failed (exit ${result.exitCode})`,
      8000,
    );
    vscode.window.showErrorMessage(
      `Conductor: ${ADAPTER_LABELS[adapterId]} install failed (exit ${result.exitCode}). See output panel.`,
    );
  }
}
