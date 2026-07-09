# Adapter — Cursor (T1)

Cursor is a strong CONDUCTOR target because:

- It supports per-pattern rule scoping via `.cursor/rules/*.mdc` `globs:` front-matter — close to Claude's lazy rule loading.
- Universal rules install as `alwaysApply: true` `.mdc` files (the modern always-loaded mechanism; the legacy `.cursorrules` single file is opt-in via `--legacy-cursorrules`).
- Its Skills surface (`.cursor/skills/` — the 2.4+ successor to project commands) gives a native `/reflect` entry point: CONDUCTOR emits `.cursor/skills/reflect/SKILL.md` with `--recipes=self-improvement`.
- Its rule UI surfaces which rules loaded for the current file, useful for debugging.

**Tool capability vs CONDUCTOR emission (ADR-031):** as of 2026 Cursor ships hooks, sub-agent dispatch, custom named agents, per-task model routing, and commands natively. What is limited today is what CONDUCTOR **emits** for it — rule text + docs + the opt-in Reflector loop; the enforcement guard hooks, role agents, and model-routing config are Phase-2 emission (ADR-034). That is a CONDUCTOR gap, not a Cursor limitation.

**Tier**: T1 (see `docs/COMPATIBILITY-MATRIX.md` — glob rule-scoping + hooks incl. session/stop events + sub-agents + per-task model all present; richest non-Claude target for Phase-2 emission).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


## Installation path

```bash
# Recommended (npm, no clone):
npx omniconductor init --target=cursor <target-dir>

# Or from a local clone:
bash /path/to/conductor/adapters/cursor/transform.sh /path/to/target [--dry-run] [--legacy-cursorrules]
```

## What gets installed

```
<target>/
├── .cursor/
│   └── rules/
│       ├── workflow.mdc                        # alwaysApply: true
│       ├── spec-as-you-go.mdc                  # alwaysApply: true
│       ├── quality-gates.mdc                   # alwaysApply: true
│       ├── operations.mdc                      # alwaysApply: true
│       ├── meta-discipline.mdc                 # alwaysApply: true
│       └── <recipe>.mdc                        # per --recipes=, path-scoped via globs:
└── docs/
    ├── CURRENT_WORK.md                         # (universal templates, identical to other adapters)
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

- `--legacy-cursorrules` additionally bundles everything into a flat `.cursorrules` (Cursor < 0.45).
- `--recipes=self-improvement` additionally emits the Reflector loop: session-end trajectory hook config (`.cursor/hooks.json`), the `/reflect` Skill (`.cursor/skills/reflect/SKILL.md`), a reflector agent (`.cursor/agents/`), prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Always-loaded universal rules (`.mdc`, `alwaysApply: true`).
- ✅ Per-pattern rule scoping (`globs:` on recipe `.mdc`).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Reflector loop (opt-in recipe) — hook config + `/reflect` Skill + agent.

## Not emitted yet (Phase 2 — Cursor supports these natively, ADR-031/034)

| Feature | Interim workaround |
|---|---|
| Enforcement guard hooks (Stop / PreToolUse set) | Self-police, or pair with a project-level pre-commit git hook. Only the Reflector session-end hook is emitted today. |
| The 6 role agents (sub-agent dispatch) | Cursor has native sub-agents; CONDUCTOR doesn't emit its role definitions for Cursor yet. Use the orchestrator-manual rule text as the prompt template. |
| Per-call model-routing config | Pick the model in Cursor's UI per task (Cursor supports per-task model selection). |
| 4-type memory pattern | Self-managed at `<target>/.memory/` (gitignored); Cursor's native Memories feature is separate. |
| Specialized review agents (Stage A / Stage B) | Run review prompts manually in Cursor chat. |

## After install — first steps

1. Open the target project in Cursor.
2. Open the rule indicator (Cursor UI shows which rules loaded for the current file). Verify the universal rules appear.
3. Skim the emitted `.cursor/rules/*.mdc` and adjust recipe `globs:` to your repo layout if needed.
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
