# Adapter — Cursor (T1, partial support)

Cursor is a strong CONDUCTOR target because:

- It supports per-pattern rule scoping via `.cursor/rules/*.mdc` `globs:` front-matter — close to Claude's lazy rule loading.
- It supports an always-loaded baseline via `.cursorrules`.
- Its `.cursor/commands/*.md` provide a partial slash-command analog.
- Its rule UI surfaces which rules loaded for the current file, useful for debugging.

It is **partial T1** because:

- ❌ No sub-agent dispatch — single chat session per task.
- ❌ No hooks — cannot ABSOLUTE-enforce spec-as-you-go or two-stage code review.
- ❌ No per-call model routing — model is per-session.
- ❌ No built-in memory directory — DIY at `.memory/`.

**Tier**: T1 — Full support for what Cursor itself supports; partial vs Claude's reference implementation due to missing sub-agents/hooks.

## Installation path

```bash
# Install (the cursor adapter is implemented):
bash /path/to/conductor/adapters/cursor/transform.sh /path/to/target [--dry-run]

# (planned / roadmap — not yet available):
# npx omniconductor init --target=cursor [target-dir]
```

## What gets installed

```
<target>/
├── .cursorrules                                # Always-loaded baseline
├── .cursor/
│   └── rules/
│       ├── operations.mdc                      # globs: **
│       ├── coding-conventions.mdc              # globs: **/*.{ts,tsx,...}
│       ├── token-economy.mdc                   # globs: **
│       ├── spec-as-you-go.mdc                  # globs: docs/specs/**, **/*.md
│       └── model-routing.mdc                   # globs: ** (informational)
└── docs/
    ├── CURRENT_WORK.md                         # (universal templates, identical to other adapters)
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Native features supported

- ✅ Always-loaded baseline (`.cursorrules`).
- ✅ Per-pattern rule scoping (`globs:` on `.mdc`).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ⚠️ Project commands (partial slash-command analog).

## Features NOT supported (Cursor limitations)

| Feature | Workaround |
|---|---|
| Sub-agent dispatch | Human plays orchestrator role manually. The orchestrator manual section in `.cursorrules` serves as the prompt template when starting a complex task. |
| Hooks (Stop / PreToolUse) | Not available. Pair with a project-level pre-commit git hook for enforcement. |
| Per-call model routing | Cursor uses one model per session. Switch sessions to switch model. Pick the right model in Cursor UI before starting a complex task. |
| Built-in memory directory | DIY at `<target>/.memory/`. Add to `.gitignore`. |
| Specialized review agents (Stage A / Stage B) | Run review prompts manually in Cursor chat. |

## After install — first steps

1. Open the target project in Cursor.
2. Open the rule indicator (Cursor UI shows which rules loaded for the current file). Verify the universal rules appear.
3. Customize `.cursorrules` — replace `{{PROJECT_NAME}}` placeholder.
4. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md` and start a real spec.
5. Add `.memory/` to `.gitignore`. Create your first memory entry.
6. Add your first entry to `docs/CURRENT_WORK.md`.

## Quirks / known issues (P2 will fill)

To be filled in `notes.md` after P2 real-install verification on Cursor.

## Status (P0 foundation)

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
- ⏳ `notes.md` (P2)
