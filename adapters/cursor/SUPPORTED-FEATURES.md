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
| **Sub-agent dispatch** | ❌ | — | Single chat session per task. Human orchestrates manually. |
| **Hooks (PreToolUse, Stop)** | ❌ | — | No commit-blocking. Use project-level pre-commit git hooks instead. |
| **Per-call model routing** | ❌ | — | Model is per-session. Choose in UI. |
| **Custom agent personas** | ⚠️ Workaround | Embed orchestrator/agent prompts in `.cursorrules` | Human pastes the right "agent persona" prompt at session start. |
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

- Sub-agent dispatch (per ADR-004).
- Stop / PreToolUse hooks.
- Per-call model routing.

CONDUCTOR will not spawn Cursor CLI processes to fake sub-agents. The orchestrator role on Cursor is a human practice, not a tool feature.

## Verification (deferred to P2)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `.cursorrules` loads on session start | ⏳ P2 | Open project; new chat; verify rule indicator shows `.cursorrules`. |
| `.mdc` rules load on file-pattern match | ⏳ P2 | Touch a file matching `globs:`; verify rule indicator. |
| Project commands work | ⏳ P2 | Type `/<command>` in chat; verify expansion. |
