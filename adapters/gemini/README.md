# Adapter — Gemini CLI (T2)

Gemini CLI is a T2 target because:

- It supports a single always-loaded project file (`GEMINI.md`), so CONDUCTOR keeps it bounded.
- It supports a coding-style guide convention (`.gemini/styleguide.md`).
- Complete rules and recipes remain available as explicit on-demand references.

**Tool capability vs CONDUCTOR emission (ADR-031/048/049/076):** CONDUCTOR emits eight Gemini agents, including Tier 3 utility, plus the opt-in Reflector agent. Every profile carries the portable Tier and the project-saved model; the recommended semantic aliases are `pro`, `flash`, and `flash-lite`. A bounded `GEMINI.md` routes to complete `.gemini/conductor/` references, and weekly Reflector scheduling remains external.

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md`).

> Enumerable facts about this adapter (output paths / tier / capabilities / runtime compatibility / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and checked against the shared runtime schema, `transform.sh`, and the validator (ADR-040/054).


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
├── GEMINI.md                                   # bounded always-active kernel
├── .agents/skills/                             # plan-change, verify-change, review-change
├── .gemini/
│   ├── conductor/rules/*.md                    # complete universal rules
│   ├── conductor/recipes/*.md                  # complete selected recipes
│   └── styleguide.md                           # coding-conventions excerpt (Gemini convention)
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    ├── specs/_example.md
    ├── plans/README.md
    ├── architecture/README.md
    └── research/README.md
```

Full, minimal, and strict installs emit the three portable procedures at Gemini
CLI's `.agents/skills` workspace alias. Native activation asks for user consent.
Recipes-only and Reflector-only do not emit them.
Selecting `self-improvement` emits the separate `propose-skill` procedure; its
typed inbox never auto-applies a live skill.

- `--recipes=self-improvement` additionally emits the Reflector loop: session-end trajectory hook config (`.gemini/settings.json`), `/reflect` command, reflector agent, prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Bounded always-loaded kernel (`GEMINI.md`).
- ✅ Style guide convention (`.gemini/styleguide.md`).
- ✅ All universal rule text retained byte-identically as on-demand references.
- ✅ All doc templates.
- ✅ Eight native `.gemini/agents/*.md` role profiles, including code-reviewer and Tier 3 utility.
- ✅ Three portable Agent Skills (`plan-change`, `verify-change`, `review-change`).
- ✅ Strong large-context capability without spending it on unrelated policy every request.

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | No verified glob loader is claimed. The bounded kernel explicitly requires reading the exact complete reference before its activity. |
| Enforcement guard hooks | Self-police, or pair with project pre-commit git hooks. Only the Reflector session-end hook is emitted today (`--recipes=self-improvement`). |
| Claude's exact agent schema | Eight equivalent Gemini-native role profiles are emitted. |
| Difficulty/model translation | Role Tier is immutable; first setup recommends and saves `pro` / `flash` / `flash-lite`. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored). |

## After install — first steps

1. Verify Gemini CLI reads `GEMINI.md` on session start (it should — that's the convention).
2. Verify the kernel routing paths and byte-identical `.gemini/conductor/` references.
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
