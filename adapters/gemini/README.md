# Adapter — Gemini CLI (T2)

Gemini CLI is a T2 target because:

- It supports a single always-loaded rule file (`GEMINI.md`).
- It supports a coding-style guide convention (`.gemini/styleguide.md`).
- It excels at large-context exploration — the always-loaded rule bundle fits its strengths.

**Tool capability vs CONDUCTOR emission (ADR-031):** as of 2026 Gemini CLI ships hooks, sub-agent dispatch, custom agents, per-task model routing, and commands natively. What is limited today is what CONDUCTOR **emits** for it — rule text + docs + the opt-in Reflector loop; the enforcement guard hooks, role agents, and model-routing config are Phase-2 emission (ADR-034). That is a CONDUCTOR gap, not a Gemini limitation. Real tool-side caveats: the adapter's rule bundle is a single always-loaded `GEMINI.md` (nested-file hierarchy, not glob scoping) and Gemini has no native scheduler (use OS cron / an external Action for the weekly Reflector).

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md`).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


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

- `--recipes=self-improvement` additionally emits the Reflector loop: session-end trajectory hook config (`.gemini/settings.json`), `/reflect` command, reflector agent, prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Always-loaded baseline (`GEMINI.md`).
- ✅ Style guide convention (`.gemini/styleguide.md`).
- ✅ All universal rule TEXT (concatenated).
- ✅ All doc templates.
- ✅ Strong large-context capability — the bundled rule file is fine to load every session.

## Not emitted yet (Phase 2 — Gemini supports these natively, ADR-031/034)

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | The adapter bundles all rules into one always-loaded `GEMINI.md` (Gemini scopes by nested-file hierarchy, not globs). Rule TEXT is the same; you just see all of it always. |
| Enforcement guard hooks | Self-police, or pair with project pre-commit git hooks. Only the Reflector session-end hook is emitted today (`--recipes=self-improvement`). |
| The 6 role agents (sub-agent dispatch) | Gemini has native sub-agents; CONDUCTOR doesn't emit its role definitions for Gemini yet. Human plays orchestrator. |
| Per-call model-routing config | Pick the model per task via Gemini's own model selection. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored). |

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
