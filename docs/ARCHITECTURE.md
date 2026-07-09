# ARCHITECTURE — CONDUCTOR

CONDUCTOR is a 3-layer system. Each layer has a single, sharp responsibility.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 1 — UNIVERSAL  (core/)                                              │
│ Tool-agnostic source-of-truth. Plain markdown. Zero tool references.      │
│                                                                           │
│   core/workflow/                Plan → Architecture → Tasks → Impl →       │
│                                 Review → Spec phase definitions            │
│   core/universal-rules/         operations / coding-conventions /          │
│                                 token-economy / spec-as-you-go /           │
│                                 model-routing                              │
│   core/docs-templates/          CURRENT_WORK / REMAINING_TASKS / PLANS /   │
│                                 TASKS / INDEX / specs/_example.md          │
│   core/memory-pattern/          4-type memory schema + examples            │
└────────────────┬─────────────────────────────────────────────────────────┘
                 │
                 │  (transform)
                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 2 — ADAPTERS  (adapters/<tool>/)                                    │
│ One adapter per supported tool. Reads core/, writes tool-native files.    │
│                                                                           │
│   adapters/claude/transform.sh   → .claude/agents/*  + .claude/rules/*    │
│                                    + .claude/hooks/*  + CLAUDE.md          │
│   adapters/cursor/transform.sh   → .cursor/rules/*.mdc + .cursorrules     │
│   adapters/copilot/transform.sh  → .github/instructions/*.instructions.md │
│   adapters/gemini/transform.sh   → GEMINI.md + .gemini/styleguide.md      │
│   adapters/codex/transform.sh    → AGENTS.md                        │
│   adapters/windsurf/transform.sh → .windsurfrules + .windsurf/rules/*.md  │
└────────────────┬─────────────────────────────────────────────────────────┘
                 │
                 │  (run by user via CLI)
                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 3 — TOOL-NATIVE FEATURES  (per tool, NOT polyfilled)                │
│ Things only one tool can do. Documented honestly; never faked.            │
│                                                                           │
│   Sub-agent dispatch         Claude Code only                              │
│   Hooks (PreToolUse / Stop)  Claude Code only                              │
│   Slash commands             Claude Code (and Cursor partial)              │
│   Native model routing       Claude Code only                              │
│   In-cache memory directory  Claude Code (`~/.claude/projects/.../memory/`)│
│                                                                           │
│   On non-Claude tools, the equivalent rule TEXT is installed (so the user │
│   knows what discipline to follow), but the tool cannot enforce it.       │
└──────────────────────────────────────────────────────────────────────────┘
```

## Why the split

### Why a separate Universal layer (`core/`)

If we wrote rules directly in Claude format, every other adapter would have to *strip* Claude-specific syntax (front-matter, `@agent` references, hook directives) — error-prone and brittle. By writing the canonical text once in tool-agnostic markdown, every adapter performs the SAME job: ADD tool-specific framing, never STRIP it.

### Why per-tool transforms (not one big script)

A central `transform.sh` would have one giant case statement and would force every code change to think about every tool. Per-tool scripts let one developer specialize in one adapter without touching the others. The contract between layers (input = `core/`, output = files at known paths) is documented in `adapters/README.md` and `adapters/<tool>/transform-spec.md`.

### Why Layer 3 is "honest, not polyfilled"

We could try to fake Claude sub-agents on Cursor by spawning a shell with Cursor's CLI. We refuse to do this:

- It would be fragile (Cursor CLI changes break it silently).
- It would be slow (process startup overhead per delegation).
- It would mislead users into thinking the workflow is the same.

Instead, on non-Claude tools, the orchestrator role is documented but executed by the human. The user reads the rule, follows the discipline manually. CONDUCTOR's value on those tools is the *content* of the discipline, not the mechanism.

## File-pattern-driven rule loading per adapter

Different tools have different mechanisms for "load this rule when this kind of file is touched." The Universal layer encodes the INTENT in front-matter; each adapter translates it.

| Universal pattern intent | Claude output | Cursor output | Copilot output | Gemini output | Codex output | Windsurf output |
|---|---|---|---|---|---|---|
| Always loaded | `CLAUDE.md` | `.cursorrules` | `.github/instructions/all.instructions.md` (`applyTo: '**'`) | `GEMINI.md` (top section) | `AGENTS.md` | `.windsurfrules` |
| `<web-app>/**` only | `.claude/rules/web.md` (paths front-matter) | `.cursor/rules/web.mdc` (`globs: <web-app>/**`) | `web.instructions.md` (`applyTo: '<web-app>/**'`) | merged into `GEMINI.md` (no scoping) | merged | `.windsurf/rules/web.md` |
| Manual / agent-only | `.claude/agents/*.md` | (no equivalent — text bundled into `.cursorrules` as orchestrator manual) | (bundled) | (bundled) | (bundled) | (bundled) |

## In-repo docs vs external memory

Two persistence kinds, intentionally separated:

- **In-repo (`docs/`)** — travels with code. Anyone cloning gets the full project context. Spec docs, current work, plans, task tracker.
- **External memory (`~/.claude/projects/<path>/memory/`)** — per-user, accumulated taste and feedback. NOT in git. Survives sessions for the same user on the same machine.

This separation is universal in `core/memory-pattern/` and is honored by every adapter — but only Claude Code has a built-in directory for it. Other tools document the pattern; the user creates the directory wherever they want.

## What the orchestrator is

In Claude Code, "orchestrator" = the main session reading `CLAUDE.md`, dispatching sub-agents via the Agent tool, blocked by hooks. The system enforces it.

In Cursor / Copilot / Gemini / Codex / Windsurf, "orchestrator" = the human + the chat session. The chat reads the equivalent rule text. The human follows the discipline manually. No sub-agents, no hooks.

Both modes are first-class CONDUCTOR users. We document both flows in `docs/HOW-IT-WORKS-PER-TOOL.md`.
