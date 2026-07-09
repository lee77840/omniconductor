# `adapters/` — Layer 2, per-tool transformers

One adapter per supported tool. Each reads the tool-agnostic content under `core/` and emits files in the format and at the paths the target tool expects.

## Adapter directory layout

```
adapters/
├── claude/        # Claude Code (T1 — reference implementation, full emission)
├── cursor/        # Cursor (T1)
├── copilot/       # GitHub Copilot (T2)
├── gemini/        # Gemini CLI (T2)
├── codex/         # OpenAI Codex (T2)
└── windsurf/      # Windsurf / Devin Desktop (T3)
```

Each adapter directory contains:

| File | Required | Purpose |
|---|---|---|
| `README.md` | YES | Tier (T1/T2/T3) with reasoning; what installs; what works; what is lost. |
| `SUPPORTED-FEATURES.md` | YES | Detailed feature support breakdown for that tool. |
| `transform-spec.md` | YES | What `transform.sh` MUST do (input, output, edge cases). |
| `transform.sh` | P1+ | The actual transformer (Bash, idempotent, supports `--dry-run`). |
| `notes.md` | optional | Real-install discoveries (quirks, surprises). |

## Adapter contract

Every adapter MUST honor:

### 1. Input

- Read from `core/` directory (relative to the conductor repo root).
- Treat `core/` as read-only. Never modify.

### 2. Output

- Write tool-native files at the conventional path for that tool, into a target directory passed as an argument.
- Conventional paths per tool are documented in `docs/HOW-IT-WORKS-PER-TOOL.md`.
- `docs/` templates from `core/docs-templates/` install at `<target>/docs/` for every adapter (universal across tools).

### 3. Idempotency

- Safe to re-run. Existing files at target paths are NOT overwritten — skip and report.
- Re-running with the same inputs produces the same outputs.

### 4. Dry-run support

- `--dry-run` flag prints what WOULD be written without touching disk.
- Useful for previewing before installing into a real project.

### 5. No telemetry

- Zero network calls. Zero usage metrics. Zero opt-in tracking. (CONDUCTOR ADR-008.)

### 6. Bash 4+ portability

- `set -euo pipefail` at the top.
- POSIX-friendly constructs where possible.
- Quote all variable expansions.
- Tested on macOS Bash and modern Linux Bash.

### 7. Failure mode

- On error: print to stderr, exit non-zero.
- On partial success: report what was installed and what was skipped.

## Front-matter translation

The Layer-1 universal-rules use `applies_to:` front-matter for routing hints. Each adapter translates it:

| `core/` front-matter | Adapter output |
|---|---|
| `applies_to: ["**/*.ts", "**/*.tsx"]` (Claude) | `paths:\n  - "**/*.ts"\n  - "**/*.tsx"` |
| (Cursor) | `globs:\n  - "**/*.ts"\n  - "**/*.tsx"` |
| (Copilot) | `applyTo: '**/*.ts,**/*.tsx'` |
| (Gemini / Codex) | (bundled — no per-pattern routing) |
| (Windsurf) | (bundled into `.devin/rules/`; legacy `.windsurf/rules/` still read) |

| `core/` front-matter | Adapter behavior |
|---|---|
| `always_loaded: true` | Merge content into the always-loaded baseline (`CLAUDE.md`, `.cursor/rules/*.mdc` `alwaysApply: true`, `.github/copilot-instructions.md`, `GEMINI.md`, `AGENTS.md`, `.windsurfrules`) |
| `always_loaded: false` (or absent) | Emit as a separate rule file with appropriate per-pattern scoping |

## Adapter-specific extensions

Each adapter MAY also install tool-native artifacts that have no `core/` source (because they are Layer-3, tool-only). Examples:

- **Claude adapter** also installs `.claude/agents/*.md`, `.claude/hooks/*.sh`, and a generated `.claude/settings.json` (written by `transform.sh`).
- **Cursor adapter** also installs `.cursor/commands/*.md` (project commands, where applicable).
- **Other adapters** typically do NOT have tool-native extensions to install.

These tool-native artifacts live IN THE ADAPTER (not in `core/`) and are documented in the adapter's `transform-spec.md`.

## Running an adapter

The Claude, Cursor, and Copilot adapters ship a runnable `transform.sh`. Gemini, Codex, and Windsurf are manual-install (see `docs/MANUAL-INSTALL.md`); their `transform-spec.md` documents the intended mapping.

Usage (shipping adapters):

```bash
# Current usage (shipping):
bash adapters/<tool>/transform.sh <target> [--dry-run]

# Or by absolute path:
/path/to/conductor/adapters/<tool>/transform.sh /path/to/target [--dry-run]

# Or via the npm CLI (no clone needed):
npx omniconductor init --target=<tool> [target-dir]
```

## Status (P0 foundation)

All 6 adapter directories have:
- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ⏳ `transform.sh` (P1+)
- ⏳ `notes.md` (P1+ when real-install quirks discovered)

See `ROADMAP.md` for which adapter ships in which phase.
