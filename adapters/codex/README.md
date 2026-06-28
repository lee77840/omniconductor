# Adapter — Codex (T3)

OpenAI Codex (the modern shell-driven agent — not the deprecated original Codex API) is a T3 target because:

- It supports a single project rules file at `AGENTS.md` (project root — the established cross-agent convention).
- It excels at shell-driven scripting and one-shot tasks.

It is **T3** because:

- ❌ No per-pattern rule scoping.
- ❌ No sub-agent dispatch.
- ❌ No hooks.
- ❌ No per-call model routing.
- ❌ No built-in memory directory.
- ⚠️ Limited multi-step orchestration capability vs Claude/Cursor.

**Tier**: T3 — Basic. Rule TEXT installs but most CONDUCTOR mechanism doesn't apply.

## Installation path

```bash
bash adapters/codex/transform.sh <target>                          # install
bash adapters/codex/transform.sh <target> --recipes=tdd,debugging  # + opt-in recipes
bash adapters/codex/transform.sh <target> --dry-run --no-prompt    # preview, write nothing
bash adapters/codex/transform.sh <target> --uninstall              # revert (manifest-based)
```

## What gets installed

```
<target>/
├── AGENTS.md                                   # Codex-flavored intro + 5 universal rules + compressed workflow + selected recipes + memory note
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Native features supported

- ✅ Always-loaded baseline (`AGENTS.md`).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Strong shell-task execution (Codex's primary strength).

## Features NOT supported

| Feature | Workaround |
|---|---|
| Per-pattern rule scoping | All rules always-loaded. |
| Sub-agent dispatch | Human plays orchestrator (or breaks task into sequential prompts). |
| Hooks | Pair with project pre-commit git hooks. |
| Per-call model routing | Single model per Codex invocation. |
| Built-in memory directory | DIY at `.memory/`. |
| Multi-step orchestration | Limited — Codex shines at one-shot shell tasks. For multi-step, use Claude/Cursor. |

## Best fit use cases

- Shell scripts.
- One-shot file transformations.
- Quick git operations.
- "Run this command and tell me the output" tasks.

## After install — first steps

1. Verify Codex reads `AGENTS.md` (auto-loaded from project root on session start).
2. Customize `AGENTS.md` for your project as needed.
3. Add `.memory/` to `.gitignore`.
4. Use Codex for shell tasks; rely on Claude/Cursor for multi-step orchestration.

## Quirks / known issues

- Output is `AGENTS.md` at the project root (the established cross-agent convention adopted by
  OpenAI Codex / Codex CLI), superseding the early-design `.codex/codex.md` guess.
- Single-file model: everything Cursor splits across `.cursor/rules/*.mdc` is concatenated into
  `AGENTS.md`. All rules are always-on — Codex has no per-pattern scoping.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented — single-file `AGENTS.md` bundle, recipes, dry-run, manifest-based uninstall)
- ⏳ `notes.md` (real-Codex install verification deferred)
