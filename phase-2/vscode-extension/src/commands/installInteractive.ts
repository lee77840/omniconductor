import * as vscode from 'vscode';
import { detectIde, recommendedAdapter } from '../utils/ideDetect';
import { AdapterId, installAdapter } from './installAdapter';

interface AdapterPick extends vscode.QuickPickItem {
  adapterId: AdapterId;
}

/**
 * Top-level "Conductor: Install" entry. Detects the host IDE, recommends an
 * adapter, but always shows all three so the user can override (e.g. install
 * Copilot rules from Cursor for a teammate using a different IDE).
 */
export async function installInteractive(
  outputChannel: vscode.OutputChannel,
): Promise<void> {
  const ide = detectIde();
  const recommended = recommendedAdapter(ide);

  const picks: AdapterPick[] = [
    {
      adapterId: 'claude',
      label: 'Claude Code',
      description: '.claude/rules + .claude/agents + .claude/hooks + CLAUDE.md',
      detail: 'Full framework — recommended for Claude Code users.',
    },
    {
      adapterId: 'cursor',
      label: 'Cursor',
      description: '.cursor/rules/*.mdc + lazy-load frontmatter',
      detail: 'Recommended when running inside Cursor.',
    },
    {
      adapterId: 'copilot',
      label: 'GitHub Copilot',
      description: '.github/copilot-instructions.md + .github/instructions/',
      detail: 'Single install covers VS Code, Windsurf, JetBrains, Neovim.',
    },
  ];

  if (recommended) {
    const recommendedPick = picks.find((p) => p.adapterId === recommended);
    if (recommendedPick) {
      recommendedPick.label = `$(star-full) ${recommendedPick.label} (recommended for ${ide})`;
    }
  }

  const chosen = await vscode.window.showQuickPick(picks, {
    title: 'Conductor — pick adapter',
    placeHolder: recommended
      ? `Detected IDE: ${ide}. Recommended adapter pre-flagged.`
      : 'Pick an adapter (IDE auto-detection inconclusive).',
    matchOnDescription: true,
    matchOnDetail: true,
  });

  if (!chosen) {
    return;
  }

  await installAdapter(chosen.adapterId, outputChannel);
}
