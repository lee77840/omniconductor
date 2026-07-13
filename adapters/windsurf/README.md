# Adapter — Windsurf (T3)

Windsurf (the AI-IDE) is a T3 target because:

- It supports an always-loaded baseline at `.windsurfrules`.
- It supports a directory of additional rules at `.devin/rules/*.md` (preferred; legacy `.windsurf/rules/` is still read).
- Its workflow is similar to Cursor's but with less per-pattern scoping.

**Tool capability vs CONDUCTOR emission (ADR-031/048/049):** CONDUCTOR emits eight Windsurf workflows as verified role entry points plus the opt-in Reflector workflow/rule. Each workflow carries the portable Tier and an explicit requirement to select Adaptive in Cascade. Because no workflow model field or selector-state API exists, enforcement is honestly recorded as advisory-session. Rule scoping and desktop scheduling remain limited.

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

The local `transform.sh` command requires Node.js and delegates to the same CLI,
including the one-time project-saved Tier-model setup. It is not a model-routing
bypass.

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
- ✅ Eight native invocable role workflows in `.windsurf/workflows/`, including Tier 3 utility.
- ✅ Reflector loop (opt-in recipe).

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | All rules in `.devin/rules/` load together. No glob filtering (tool-side). |
| Enforcement guard hooks | Windsurf has hooks but **no session/stop events** (tool-side gap) — Stop-style enforcement isn't possible; self-police or pair with pre-commit git hooks. |
| Project-local custom-agent profiles | No stable contract is claimed; eight native role workflows provide explicit entry points instead. |
| Difficulty/model translation | Workflow Tier is immutable; first setup saves Adaptive and every workflow displays the required session preflight. Automatic enforcement is unavailable. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); the tool's built-in memory is separate. |

## After install — first steps

1. Open the project in Windsurf.
2. Verify `.windsurfrules` loads on session start.
3. Verify `.devin/rules/*.md` load alongside.
4. Customize `.windsurfrules` — replace `{{PROJECT_NAME}}`.
5. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md`.
6. Add `.memory/` to `.gitignore`.

## Quirks / known issues

- `.devin/rules/` is the emitted current path; legacy `.windsurf/rules/` remains migration input only.
- TBD: priority order when `.windsurfrules` and `.devin/rules/*.md` contain conflicting rules.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
