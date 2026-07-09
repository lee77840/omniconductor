# Adapter — Windsurf (T3)

Windsurf (the AI-IDE) is a T3 target because:

- It supports an always-loaded baseline at `.windsurfrules`.
- It supports a directory of additional rules at `.devin/rules/*.md` (preferred; legacy `.windsurf/rules/` is still read).
- Its workflow is similar to Cursor's but with less per-pattern scoping.

**Tool capability vs CONDUCTOR emission (ADR-031):** as of 2026 Windsurf / Devin Desktop ships hooks (12 events — but **no session/stop events**, the one real Stop-style-enforcement gap), sub-agent dispatch (Devin Local), custom agents, per-task model routing, commands, and built-in memory. What is limited today is what CONDUCTOR **emits** for it — rule text + docs + the opt-in Reflector loop; the enforcement guard hooks, role agents, and model-routing config are Phase-2 emission (ADR-034). Real tool-side caveats: no glob rule-scoping (all `.devin/rules/*.md` load together) and no desktop scheduler.

**Tier**: T3 (see `docs/COMPATIBILITY-MATRIX.md` — the missing session/stop hook events keep it below T2).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


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
│       ├── workflow.md
│       ├── spec-as-you-go.md
│       ├── quality-gates.md
│       ├── operations.md
│       ├── meta-discipline.md
│       └── <recipe>.md                          # per --recipes=
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

- `--recipes=self-improvement` additionally emits the Reflector loop: trajectory hook config (`.windsurf/hooks.json`, riding `post_cascade_response_with_transcript` — Windsurf has no session/stop event), the `/reflect` workflow (`.windsurf/workflows/reflect.md`), a reflector persona rule (`.devin/rules/reflector.md`, `trigger: manual`), prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Always-loaded baseline (`.windsurfrules`).
- ✅ Directory-based rule loading (`.devin/rules/`; legacy `.windsurf/rules/` still read).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Reflector loop (opt-in recipe).

## Not emitted yet (Phase 2 — Windsurf supports most of these natively, ADR-031/034)

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | All rules in `.devin/rules/` load together. No glob filtering (tool-side). |
| Enforcement guard hooks | Windsurf has hooks but **no session/stop events** (tool-side gap) — Stop-style enforcement isn't possible; self-police or pair with pre-commit git hooks. |
| The 6 role agents (sub-agent dispatch) | Devin Local has native sub-agents; CONDUCTOR doesn't emit its role definitions yet. Human plays orchestrator. |
| Per-call model-routing config | Pick the model per task via the tool's own model selection. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); the tool's built-in memory is separate. |

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
