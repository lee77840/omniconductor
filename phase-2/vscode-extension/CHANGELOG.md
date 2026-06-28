# Changelog — Conductor VSCode extension

All notable changes to this extension are documented here. The extension version tracks the parent Conductor framework version once Phase 2 ships.

## [0.3.0] — 2026-05-10 (first marketplace release)

### Added

- Command Palette entries:
  - `Conductor: Install (auto-detect IDE)`
  - `Conductor: Install Claude rules`
  - `Conductor: Install Cursor rules`
  - `Conductor: Install Copilot rules`
- IDE auto-detection (`vscode.env.appName`) with adapter recommendation.
- Windows shell discovery — Git Bash standard install paths, then WSL2 fallback.
- Output channel streaming for live `transform.sh` stdout/stderr.
- Settings: `conductor.repoPath`, `conductor.recipes`, `conductor.dryRun`, `conductor.shellPath`.
- Folder picker fallback when `conductor.repoPath` does not exist.
- Cancellation support — VSCode progress notifications can abort the running script.

### Decisions

- Per ADR-025, the extension is a launcher only. The bash adapter (`adapters/<tool>/transform.sh`) remains the single source of truth. No TypeScript port of transform logic.
- Cross-published to the VSCode Marketplace (Microsoft) and Open VSX Registry (Eclipse Foundation, used by Cursor + open-source forks).
