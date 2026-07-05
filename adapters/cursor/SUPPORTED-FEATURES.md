# Cursor — supported features

Detailed matrix of which CONDUCTOR features Cursor supports natively.

## Feature support

| Feature | Cursor support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `.cursorrules` at project root | Auto-loaded in every chat session in the project. |
| **Per-pattern rule scoping** | ✅ Native | `.cursor/rules/*.mdc` with `globs:` front-matter | Closest analog to Claude's `paths:` lazy-loading. |
| **Custom slash commands (project)** | ⚠️ Partial | `.cursor/commands/*.md` (where Cursor version supports) | Not as flexible as Claude slash commands; usable but limited. |
| **MCP servers** | ✅ Native | Cursor settings | Not used by CONDUCTOR; project may add own. |
| **In-IDE chat / completion** | ✅ Native | Cursor's primary feature set | Inline completion + chat — Cursor's strength. |
| **Sub-agent dispatch** | ✅ Native (2026) | Custom named agents in `.cursor/agents/*.md` | See `docs/COMPATIBILITY-MATRIX.md` / ADR-031. |
| **Hooks (stop)** | ✅ Native (2026) | `.cursor/hooks.json` | ADR-031. CONDUCTOR currently emits only the Reflector hook (ADR-032); broader hook-set emission is Phase 2. |
| **Per-task model routing** | ✅ Native (2026) | Per-agent `model` config in agent definitions | ADR-031. |
| **Custom agent personas** | ✅ Native (2026) | `.cursor/agents/*.md` named agents | Previously a `.cursorrules` paste-in workaround; now first-class. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/` (gitignored). |
| **In-repo doc templates** | ✅ Native | Plain markdown; Cursor reads on demand | Universal across all adapters. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text in `.cursorrules` + `.cursor/rules/spec-as-you-go.mdc` | Self-policed. Pair with pre-commit git hook for mechanical enforcement. |
| **Two-stage code review enforcement** | ❌ rule reminder only | Rule text reminds; user runs review prompts manually in Cursor chat | |

## Cursor-specific extensions

CONDUCTOR's Cursor adapter MAY install:

- `.cursor/commands/*.md` — project commands for common workflows (e.g., `/plan`, `/review`, `/sync-spec`). These are partial analogs of Claude slash commands.

## Universal-rule → Cursor `.mdc` translation

For each `core/universal-rules/<rule>.md`:

| `core/` front-matter | Cursor `.mdc` front-matter |
|---|---|
| `applies_to: ["**/*.ts"]` | `globs:\n  - "**/*.ts"` |
| `always_loaded: true` | (merge into `.cursorrules` instead of separate `.mdc`) |
| `priority: 1` | (informational — no Cursor equivalent) |

Cursor `.mdc` accepts:
```
---
description: brief description
globs:
  - "<glob1>"
  - "<glob2>"
alwaysApply: false
---

# Rule body
```

`alwaysApply: true` overrides `globs:` and forces always-on. CONDUCTOR uses this for `spec-as-you-go.mdc` and `token-economy.mdc` (always-on is the safer behavior even though their `applies_to:` in `core/` is `**`).

## Model tier mapping

CONDUCTOR's universal `model-routing.md` rubric describes Opus / Sonnet / Haiku tiers. Cursor users:

- Pick the heaviest model for Plan / Architecture / Large Refactor sessions.
- Pick the standard model for routine implementation.
- Pick the cheap model for trivial reads / variable renames.

Cursor's UI exposes the model picker. CONDUCTOR's rule text serves as the rubric for the human's selection.

## What Cursor DOES NOT support (and CONDUCTOR doesn't fake)

> **2026 reconciliation (first-party verified):** the limitations previously listed here are stale. Cursor now natively supports hooks (`.cursor/hooks.json`), sub-agent dispatch with custom named agents (`.cursor/agents/*.md`), per-task model routing (per-agent `model` config), and project commands/skills — see `docs/COMPATIBILITY-MATRIX.md` / ADR-031.

What remains true on the CONDUCTOR side:

- CONDUCTOR does not yet emit a Claude-parity hook set for Cursor. It currently emits only the self-improvement Reflector hook (ADR-032, opt-in — see below). Broader hook-set emission (commit-blocking, spec enforcement) is Phase 2.
- Until then, commit-blocking enforcement still relies on project-level pre-commit git hooks, and orchestration discipline remains partly a human practice.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Cursor adapter emits the Reflector loop (ADR-032):

- **Hook**: `.cursor/hooks.json` — registers `.conductor/reflect/trajectory-log.sh` on the `stop` event. Written only if no hook config exists; if one is already present, the adapter emits a manual-merge log entry instead of overwriting.
- **Command**: `.cursor/skills/reflect/SKILL.md` — the `/reflect` command that distills the trajectory log into lesson candidates.
- **Agent**: `.cursor/agents/reflector.md` — named reflector agent for the distillation pass.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification (deferred to P2)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `.cursorrules` loads on session start | ⏳ P2 | Open project; new chat; verify rule indicator shows `.cursorrules`. |
| `.mdc` rules load on file-pattern match | ⏳ P2 | Touch a file matching `globs:`; verify rule indicator. |
| Project commands work | ⏳ P2 | Type `/<command>` in chat; verify expansion. |
