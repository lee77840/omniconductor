# Adapter — Cursor (T1)

Cursor is a strong CONDUCTOR target because:

- It supports per-pattern rule scoping via `.cursor/rules/*.mdc` `globs:` front-matter — close to Claude's lazy rule loading.
- One bounded kernel installs as `alwaysApply: true`; complete universal rules stay
  byte-identical under `.cursor/conductor/rules/` and load through the kernel routing table.
- Its Skills surface (`.cursor/skills/` — the 2.4+ successor to project commands) gives a native `/reflect` entry point: CONDUCTOR emits `.cursor/skills/reflect/SKILL.md` with `--recipes=self-improvement`.
- Its rule UI surfaces which rules loaded for the current file, useful for debugging.

**Tool capability vs CONDUCTOR emission (ADR-031/048/049):** CONDUCTOR emits eight project agents, including Tier 3 utility, plus the opt-in Reflector agent. Every profile carries the portable Tier and the project-saved Cursor model. Cursor account, plan, and administrator fallback remains explicitly disclosed. Guard-hook emission remains narrower than Claude/Codex.

**Tier**: T1 (see `docs/COMPATIBILITY-MATRIX.md` — glob rule-scoping + hooks incl. session/stop events + sub-agents + per-task model all present; richest non-Claude target for Phase-2 emission).

> Enumerable facts about this adapter (output paths / tier / capabilities / runtime compatibility / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and checked against the shared runtime schema, `transform.sh`, and the validator (ADR-040/054).


## Installation path

```bash
# Recommended (npm, no clone):
npx omniconductor init --target=cursor <target-dir>

# Or from a local clone:
bash /path/to/conductor/adapters/cursor/transform.sh /path/to/target [--dry-run] [--legacy-cursorrules]
```

The local `transform.sh` command requires Node.js and delegates to the same CLI,
including the one-time project-saved Tier-model setup. It is not a model-routing
bypass.

## What gets installed

```
<target>/
├── .agents/skills/                            # plan-change, verify-change, review-change
├── .cursor/
│   └── rules/
│       ├── conductor-kernel.mdc                # bounded, alwaysApply: true
│       └── <recipe>.mdc                        # compact path-scoped pointer
│   └── conductor/
│       ├── rules/*.md                          # complete byte-identical rules
│       └── recipes/*.md                        # complete selected recipes
└── docs/
    ├── CURRENT_WORK.md                         # (universal templates, identical to other adapters)
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    ├── specs/_example.md
    ├── plans/README.md
    ├── architecture/README.md
    └── research/README.md
```

Full, minimal, and strict installs emit the three portable procedures at Cursor's
documented `.agents/skills` alias. Recipes-only and Reflector-only do not.
Selecting `self-improvement` emits the separate `propose-skill` procedure; its
typed inbox never auto-applies a live skill.

- `--legacy-cursorrules` additionally emits the bounded kernel into `.cursorrules`; it does not recreate the old eager full-policy bundle.
- `--recipes=self-improvement` additionally emits the Reflector loop: session-end trajectory hook config (`.cursor/hooks.json`), the `/reflect` Skill (`.cursor/skills/reflect/SKILL.md`), a reflector agent (`.cursor/agents/`), prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Bounded always-loaded kernel (`conductor-kernel.mdc`, `alwaysApply: true`).
- ✅ Per-pattern rule scoping (`globs:` on recipe `.mdc`).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Eight native `.cursor/agents/*.md` role profiles, including code-reviewer and Tier 3 utility.
- ✅ Three portable Agent Skills (`plan-change`, `verify-change`, `review-change`).
- ✅ Reflector loop (opt-in recipe) — hook config + `/reflect` Skill + agent.

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Enforcement guard hooks (Stop / PreToolUse set) | Self-police, or pair with a project-level pre-commit git hook. Only the Reflector session-end hook is emitted today. |
| Claude's exact agent schema | Eight equivalent Cursor-native role profiles are emitted. |
| Difficulty/model translation | Role Tier is immutable; first setup saves exact Tier models and regenerates every profile. Cursor provider fallback remains possible. |
| 4-type memory pattern | Self-managed at `<target>/.memory/` (gitignored); Cursor's native Memories feature is separate. |
| Full mechanical guard set | Use the emitted reviewer/code-reviewer roles; only verified Cursor lifecycle hooks are installed. |

## After install — first steps

1. Open the target project in Cursor.
2. Open the rule indicator and verify `conductor-kernel.mdc` appears.
3. Skim compact recipe pointers and their complete `.cursor/conductor/recipes/` references.
4. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md` and start a real spec.
5. Add `.memory/` to `.gitignore`. Create your first memory entry.
6. Add your first entry to `docs/CURRENT_WORK.md`.

## Quirks / known issues

Current capability and live-verification caveats are tracked in
`SUPPORTED-FEATURES.md`, `metadata.json`, and `docs/ADAPTER-LIVE-VERIFICATION.md`.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
