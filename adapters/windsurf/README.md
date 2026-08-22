# Adapter — Windsurf (T3)

Windsurf (the AI-IDE) is a T3 target because:

- It supports an always-loaded baseline at `.windsurfrules`.
- Complete rules live outside the eager surface under `.devin/conductor/rules/`;
  `.devin/rules/` carries compact pointers only in à-la-carte modes.
- Its workflow is similar to Cursor's but with less per-pattern scoping.

**Tool capability vs CONDUCTOR emission (ADR-031/048/049):** CONDUCTOR emits eight Windsurf workflows as verified role entry points plus the opt-in Reflector workflow/rule. Each workflow carries the portable Tier and an explicit requirement to select Adaptive in Cascade. Because no workflow model field or selector-state API exists, enforcement is honestly recorded as advisory-session. Rule scoping and desktop scheduling remain limited.

**Tier**: T3 (see `docs/COMPATIBILITY-MATRIX.md` — the missing session/stop hook events keep it below T2).

> Enumerable facts about this adapter (output paths / tier / capabilities / runtime compatibility / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and checked against the shared runtime schema, `transform.sh`, and the validator (ADR-040/054).


## Installation path

```bash
# Install (bounded kernel + complete references + docs):
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
├── .windsurfrules                              # bounded always-loaded kernel
├── .agents/skills/                             # plan-change, verify-change, review-change
├── .devin/conductor/
│   ├── rules/*.md                              # complete universal rules
│   └── recipes/*.md                            # complete selected recipes
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

Full, minimal, and strict installs emit the three portable procedures at Devin's
recommended `.agents/skills` path. Devin may select them automatically or by
`@skills:<name>` and activates one skill at a time. Recipes-only and Reflector-only
do not emit them.
Selecting `self-improvement` emits the separate `propose-skill` procedure; its
typed inbox never auto-applies a live skill.

- `--recipes=self-improvement` additionally emits the Reflector loop: trajectory hook config (`.windsurf/hooks.json`, riding `post_cascade_response_with_transcript` — Windsurf has no session/stop event), the `/reflect` workflow (`.windsurf/workflows/reflect.md`), a reflector persona rule (`.devin/rules/reflector.md`, `trigger: manual`), prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Bounded always-loaded kernel (`.windsurfrules`).
- ✅ Complete byte-identical references under `.devin/conductor/`.
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Eight native invocable role workflows in `.windsurf/workflows/`, including Tier 3 utility.
- ✅ Three portable Agent Skills (`plan-change`, `verify-change`, `review-change`).
- ✅ Reflector loop (opt-in recipe).

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | No verified glob filtering is claimed; the kernel routes to exact complete references. |
| Enforcement guard hooks | Windsurf has hooks but **no session/stop events** (tool-side gap) — Stop-style enforcement isn't possible; self-police or pair with pre-commit git hooks. |
| Project-local custom-agent profiles | No stable contract is claimed; eight native role workflows provide explicit entry points instead. |
| Difficulty/model translation | Workflow Tier is immutable; first setup saves Adaptive and every workflow displays the required session preflight. Automatic enforcement is unavailable. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); the tool's built-in memory is separate. |

## After install — first steps

1. Open the project in Windsurf.
2. Verify `.windsurfrules` loads on session start.
3. Verify the `.devin/conductor/` reference paths exist and are readable on demand.
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
