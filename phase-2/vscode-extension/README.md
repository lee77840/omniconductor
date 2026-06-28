# Conductor — VSCode extension

Thin wrapper around the [Conductor](https://github.com/lee77840/omniconductor) bash adapters. Install Claude Code, Cursor, or GitHub Copilot rules into the current workspace from the Command Palette.

## Status

v0.3.0 — first marketplace release. Phase 2 of the Conductor roadmap (ADR-025). The bash adapter remains the source of truth; this extension exposes Command Palette entries, IDE auto-detection, and Windows shell discovery.

## Prerequisites

1. **Clone the Conductor repo** (the extension calls into it; it does not bundle the rules):

   ```bash
   git clone https://github.com/lee77840/omniconductor ~/.conductor
   ```

   Custom path? Set `conductor.repoPath` in settings.

2. **bash on PATH**:
   - macOS / Linux: built-in.
   - Windows: install [Git for Windows](https://gitforwindows.org) (bundles Git Bash) or enable WSL2. The extension auto-detects both.

## Usage

Command Palette (`Ctrl/Cmd+Shift+P`):

- **Conductor: Install (auto-detect IDE)** — recommended entry. Detects host IDE, suggests an adapter, lets you override.
- **Conductor: Install Claude rules** — `.claude/agents`, `.claude/rules`, `.claude/hooks`, `CLAUDE.md`.
- **Conductor: Install Cursor rules** — `.cursor/rules/*.mdc` with lazy-load frontmatter.
- **Conductor: Install Copilot rules** — `.github/copilot-instructions.md` + `.github/instructions/`. One install covers VS Code, Cursor (Copilot extension), Windsurf, JetBrains, Neovim.

## Settings

| Setting | Default | Notes |
|---|---|---|
| `conductor.repoPath` | `~/.conductor` | Tilde expanded. Falls back to a folder picker if invalid. |
| `conductor.recipes` | `""` | Comma-separated, e.g. `monorepo,coding-conventions,tdd`. |
| `conductor.dryRun` | `false` | Pass `--dry-run` to preview changes. |
| `conductor.shellPath` | `""` | Override bash binary. Auto-detected on Windows (Git Bash → WSL2). |

## Why a thin wrapper?

Per [ADR-023](https://github.com/lee77840/omniconductor/blob/main/docs/DESIGN-DECISIONS.md): the bash adapter is the validated source of truth across multiple production syncs. Re-implementing in TypeScript would double the test surface. This extension launches `transform.sh` and streams the output — no logic divergence.

## License

Apache License 2.0 — © LFamily Labs LLC. Free and open (commercial use included); the CONDUCTOR name is a trademark. See [LICENSE](./LICENSE).
