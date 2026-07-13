# Adapter — Gemini CLI (T2)

Gemini CLI is a T2 target because:

- It supports a single always-loaded rule file (`GEMINI.md`).
- It supports a coding-style guide convention (`.gemini/styleguide.md`).
- It excels at large-context exploration — the always-loaded rule bundle fits its strengths.

**Tool capability vs CONDUCTOR emission (ADR-031/048/049):** CONDUCTOR emits eight Gemini agents, including Tier 3 utility, plus the opt-in Reflector agent. Every profile carries the portable Tier and the project-saved model; the recommended semantic aliases are `pro`, `flash`, and `flash-lite`. The rule bundle remains a single always-loaded `GEMINI.md`, and weekly Reflector scheduling remains external.

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md`).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


## Installation path

```bash
# From the conductor repo root:
bash adapters/gemini/transform.sh <target-project>

# With opt-in recipes (coding-conventions also emits .gemini/styleguide.md):
bash adapters/gemini/transform.sh <target-project> --recipes=coding-conventions,i18n

# CI-safe first setup / preview / revert:
bash adapters/gemini/transform.sh <target-project> --no-prompt --accept-model-defaults
bash adapters/gemini/transform.sh <target-project> --dry-run
bash adapters/gemini/transform.sh <target-project> --uninstall
```

The local `transform.sh` command requires Node.js and delegates to the same CLI,
including the one-time project-saved Tier-model setup. It is not a model-routing
bypass.

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
- ✅ Eight native `.gemini/agents/*.md` role profiles, including code-reviewer and Tier 3 utility.
- ✅ Strong large-context capability — the bundled rule file is fine to load every session.

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | The adapter bundles all rules into one always-loaded `GEMINI.md` (Gemini scopes by nested-file hierarchy, not globs). Rule TEXT is the same; you just see all of it always. |
| Enforcement guard hooks | Self-police, or pair with project pre-commit git hooks. Only the Reflector session-end hook is emitted today (`--recipes=self-improvement`). |
| Claude's exact agent schema | Eight equivalent Gemini-native role profiles are emitted. |
| Difficulty/model translation | Role Tier is immutable; first setup recommends and saves `pro` / `flash` / `flash-lite`. |
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

## Quirks / known issues

- Treat the installed project root as the `GEMINI.md` discovery boundary; do not rely on undocumented parent-directory traversal.
- TBD: `.gemini/styleguide.md` priority vs `GEMINI.md` when both contain conflicting rules.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
