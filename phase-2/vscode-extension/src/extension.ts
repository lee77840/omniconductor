import * as vscode from 'vscode';
import { installAdapter } from './commands/installAdapter';
import { installInteractive } from './commands/installInteractive';

/**
 * Conductor — VSCode extension entry.
 *
 * Thin wrapper around `<conductor>/adapters/<tool>/transform.sh`. Per ADR-025
 * the bash adapter remains the source of truth; this extension exposes
 * Command Palette entries, IDE detection, and Windows shell discovery.
 */
export function activate(context: vscode.ExtensionContext): void {
  const outputChannel = vscode.window.createOutputChannel('Conductor');
  context.subscriptions.push(outputChannel);

  context.subscriptions.push(
    vscode.commands.registerCommand('conductor.install', () =>
      installInteractive(outputChannel),
    ),
    vscode.commands.registerCommand('conductor.installClaude', () =>
      installAdapter('claude', outputChannel),
    ),
    vscode.commands.registerCommand('conductor.installCursor', () =>
      installAdapter('cursor', outputChannel),
    ),
    vscode.commands.registerCommand('conductor.installCopilot', () =>
      installAdapter('copilot', outputChannel),
    ),
  );
}

export function deactivate(): void {
  // No persistent resources beyond the output channel, which is disposed
  // automatically by VSCode via the context.subscriptions chain.
}
