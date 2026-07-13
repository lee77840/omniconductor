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
│   adapters/cursor/transform.sh   → .cursor/rules/* + .cursor/agents/*    │
│                                    (+ opt-in legacy .cursorrules)          │
│   adapters/copilot/transform.sh  → .github/instructions/* + agents/*      │
│   adapters/gemini/transform.sh   → GEMINI.md + .gemini/agents/*           │
│   adapters/codex/transform.sh    → AGENTS.md + .codex/{agents,hooks}/*    │
│   adapters/windsurf/transform.sh → rules + .windsurf/workflows/*           │
└────────────────┬─────────────────────────────────────────────────────────┘
                 │
                 │  (run by user via CLI)
                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ LAYER 3 — TOOL-NATIVE FEATURES  (per tool, NOT polyfilled)                │
│ Things only one tool can do. Documented honestly; never faked.            │
│                                                                           │
│   Role profiles              Claude / Cursor / Copilot / Gemini / Codex     │
│   Role workflows             Windsurf (verified project-local fallback)    │
│   Guard hooks                Full on Claude; verified subset on Codex       │
│   Reflector lifecycle hook   All six, recipe-gated                         │
│   Model routing              Saved Tier models; Windsurf advisory session  │
│                                                                           │
│   Unsupported tool contracts are documented, never copied by name.        │
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

Instead, every adapter compiles to the strongest verified project-local mechanism. Most tools receive native role profiles; Windsurf receives native invocable workflows. Guard hooks are emitted only where the event, input, output, and trust contracts are verified.

## File-pattern-driven rule loading per adapter

Different tools have different mechanisms for "load this rule when this kind of file is touched." The Universal layer encodes the INTENT in front-matter; each adapter translates it.

| Universal pattern intent | Claude output | Cursor output | Copilot output | Gemini output | Codex output | Windsurf output |
|---|---|---|---|---|---|---|
| Always loaded | `CLAUDE.md` | `.cursor/rules/*.mdc` (`alwaysApply: true`) | `.github/copilot-instructions.md` | `GEMINI.md` (top section) | bounded `AGENTS.md` kernel | `.windsurfrules` |
| `<web-app>/**` only | `.claude/rules/web.md` (paths front-matter) | `.cursor/rules/web.mdc` (`globs: <web-app>/**`) | `web.instructions.md` (`applyTo: '<web-app>/**`) | merged into `GEMINI.md` (no scoping) | kernel-routed `.codex/conductor/` reference | `.devin/rules/web.md` |
| Manual / agent-only | `.claude/agents/*.md` | `.cursor/agents/*.md` | `.github/agents/*.agent.md` | `.gemini/agents/*.md` | `.codex/agents/*.toml` | `.windsurf/workflows/*.md` |

## In-repo docs vs external memory

Two persistence kinds, intentionally separated:

- **In-repo (`docs/`)** — travels with code. Anyone cloning gets the full project context. Spec docs, current work, plans, task tracker.
- **Tool-managed or external memory** — per-user, accumulated taste and feedback. NOT in git. Survives sessions for the same user on the same machine.

This separation is universal in `core/memory-pattern/` and is honored by every adapter. Claude, Copilot preview, Codex opt-in, and Windsurf expose verified managed-memory locations; Cursor and Gemini use the documented project-local fallback until a stable native contract is verified. The exact current paths and caveats live in `core/memory-pattern/README.md`.

## What the orchestrator is

In Claude Code, "orchestrator" = the main session reading `CLAUDE.md`, dispatching sub-agents via the Agent tool, blocked by hooks. The system enforces it.

In Cursor, Copilot, Gemini, and Codex, the main session can select the emitted project role profiles. Windsurf uses emitted role workflows. Mechanical enforcement remains platform-specific: Claude has the full hook set, Codex has the verified guard subset, and the remaining products retain explicit workflow obligations plus their verified Reflector lifecycle hook.

Both modes are first-class CONDUCTOR users. We document both flows in `docs/HOW-IT-WORKS-PER-TOOL.md`.
