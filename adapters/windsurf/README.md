# Adapter — Windsurf (T3)

Windsurf (the AI-IDE) is a T3 target because:

- It supports an always-loaded baseline at `.windsurfrules`.
- It supports a directory of additional rules at `.devin/rules/*.md` (preferred; legacy `.windsurf/rules/` is still read).
- Its workflow is similar to Cursor's but with less per-pattern scoping.

It is **T3** because:

- ❌ No per-pattern rule scoping (rules in `.devin/rules/` all load together; no glob filtering).
- ❌ No sub-agent dispatch.
- ❌ No hooks.
- ❌ No per-call model routing.
- ❌ No built-in memory directory.

**Tier**: T3 — Basic. Rule TEXT installs and groups well, but enforcement and scoping are minimal.

## Installation path

```bash
# Install (always-loaded baseline + grouped rules + docs):
bash adapters/windsurf/transform.sh <target>

# With opt-in recipes:
bash adapters/windsurf/transform.sh <target> --recipes=i18n,monorepo

# Preview without writing:
bash adapters/windsurf/transform.sh <target> --dry-run

# Revert a previous install (manifest-based):
bash adapters/windsurf/transform.sh <target> --uninstall
```

## What gets installed

```
<target>/
├── .windsurfrules                              # Always-loaded baseline (orchestrator manual + ABSOLUTE rules)
├── .devin/                                     # Preferred rules dir (legacy .windsurf/rules/ still read)
│   └── rules/
│       ├── operations.md
│       ├── coding-conventions.md
│       ├── token-economy.md
│       ├── spec-as-you-go.md
│       └── model-routing.md
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Native features supported

- ✅ Always-loaded baseline (`.windsurfrules`).
- ✅ Directory-based rule loading (`.devin/rules/`; legacy `.windsurf/rules/` still read).
- ✅ All universal rule TEXT.
- ✅ All doc templates.

## Features NOT supported

| Feature | Workaround |
|---|---|
| Per-pattern rule scoping | All rules in `.devin/rules/` load together. No glob filtering. |
| Sub-agent dispatch | Human plays orchestrator. |
| Hooks | Pair with project pre-commit git hooks. |
| Per-call model routing | Single model per session. |
| Built-in memory directory | DIY at `.memory/`. |

## After install — first steps

1. Open the project in Windsurf.
2. Verify `.windsurfrules` loads on session start.
3. Verify `.devin/rules/*.md` load alongside.
4. Customize `.windsurfrules` — replace `{{PROJECT_NAME}}`.
5. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md`.
6. Add `.memory/` to `.gitignore`.

## Quirks / known issues (P3.5 will fill)

- TBD: confirm Windsurf reads ALL files under `.devin/rules/` (vs requiring a manifest); legacy `.windsurf/rules/` is still read.
- TBD: priority order when `.windsurfrules` and `.devin/rules/*.md` contain conflicting rules.

## Status (P0 foundation)

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
- ⏳ `notes.md` (P3.5)
