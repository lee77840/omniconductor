# Adapter — Gemini CLI (T2)

Gemini CLI is a T2 target because:

- It supports a single always-loaded rule file (`GEMINI.md`).
- It supports a coding-style guide convention (`.gemini/styleguide.md`).
- It excels at large-context exploration — the always-loaded rule bundle fits its strengths.

It is **T2** because:

- ❌ No per-pattern rule scoping (single-file bundle).
- ❌ No sub-agent dispatch.
- ❌ No hooks.
- ❌ No per-call model routing.
- ❌ No built-in memory directory.

**Tier**: T2 — Good for large-context use; rule scoping is "all rules always-loaded".

## Installation path

```bash
# From the conductor repo root:
bash adapters/gemini/transform.sh <target-project>

# With opt-in recipes (coding-conventions also emits .gemini/styleguide.md):
bash adapters/gemini/transform.sh <target-project> --recipes=coding-conventions,i18n

# CI-safe (no interactive prompts) / preview / revert:
bash adapters/gemini/transform.sh <target-project> --no-prompt
bash adapters/gemini/transform.sh <target-project> --dry-run
bash adapters/gemini/transform.sh <target-project> --uninstall
```

## What gets installed

```
<target>/
├── GEMINI.md                                   # All universal rules concatenated, sectioned
├── .gemini/
│   └── styleguide.md                           # coding-conventions excerpt (Gemini convention)
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Native features supported

- ✅ Always-loaded baseline (`GEMINI.md`).
- ✅ Style guide convention (`.gemini/styleguide.md`).
- ✅ All universal rule TEXT (concatenated).
- ✅ All doc templates.
- ✅ Strong large-context capability — the bundled rule file is fine to load every session.

## Features NOT supported

| Feature | Workaround |
|---|---|
| Per-pattern rule scoping | All rules always-loaded; no per-file routing. Rule TEXT is the same; you just see all of it always. |
| Sub-agent dispatch | Human plays orchestrator. |
| Hooks | Pair with project pre-commit git hooks. |
| Per-call model routing | Single model per session. |
| Built-in memory directory | DIY at `.memory/`. |

## After install — first steps

1. Verify Gemini CLI reads `GEMINI.md` on session start (it should — that's the convention).
2. Customize the always-loaded section of `GEMINI.md` — replace `{{PROJECT_NAME}}`.
3. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md`.
4. Add `.memory/` to `.gitignore`.
5. Add your first entry to `docs/CURRENT_WORK.md`.

## Best fit use cases

- Large-context exploration ("read this 10K-line file and summarize").
- One-off scripts where the orchestrator pattern is overkill.
- Cheap second-opinion when the primary tool is Claude or Cursor.

## Quirks / known issues (P3 will fill)

- TBD: Gemini CLI's exact file-discovery behavior (does it walk parent directories looking for `GEMINI.md`?).
- TBD: `.gemini/styleguide.md` priority vs `GEMINI.md` when both contain conflicting rules.

## Status (P0 foundation)

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
- ⏳ `notes.md` (P3)
