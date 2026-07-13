# Adapter — GitHub Copilot (T2)

GitHub Copilot is a T2 target because:

- It supports per-pattern rule scoping via `.github/instructions/*.instructions.md` `applyTo:` front-matter.
- Instructions live IN the repo, so all collaborators automatically share them.
- Copilot's PR review feature provides a partial Stage B code-review analog tied to GitHub.

**Tool capability vs CONDUCTOR emission (ADR-031/048/049):** CONDUCTOR emits eight repository agents, including Tier 3 utility, plus the opt-in Reflector agent. Every profile carries the portable Tier and the project-saved exact model. Account, client, plan, and organization policy remain authoritative. Guard-hook emission remains limited to verified contracts.

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md` — hooks + sub-agents + per-task model + commands all present; caveats: `applyTo:` glob scoping works, but the coding agent has no transcript API).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


## Installation path

```bash
# Recommended (npm, no clone):
npx omniconductor init --target=copilot <target-dir>

# Or from a local clone:
bash /path/to/conductor/adapters/copilot/transform.sh /path/to/target [--dry-run] [--per-rule]
```

The local `transform.sh` command requires Node.js and delegates to the same CLI,
including the one-time project-saved Tier-model setup. It is not a model-routing
bypass.

## What gets installed

```
<target>/
├── .github/
│   ├── copilot-instructions.md                 # 5 universal rules merged (repo-wide, default mode)
│   └── instructions/
│       └── <recipe>.instructions.md            # per --recipes=, applyTo: from source paths
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

- `--per-rule` splits the 5 universal rules into per-file `.github/instructions/<rule>.instructions.md` (`applyTo: '**'`) instead of the single merged file.
- `--recipes=self-improvement` additionally emits the Reflector loop: session-end trajectory hook config, `/reflect` command, reflector agent, prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Always-loaded baseline (`.github/copilot-instructions.md`).
- ✅ Per-pattern rule scoping (`applyTo:` front-matter on recipe files).
- ✅ Instructions IN the repo (collaborator-shared) — one install covers VS Code, Cursor (Copilot ext), Windsurf (Copilot adapter), JetBrains, Neovim.
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Eight repository custom agents in `.github/agents/`, including code-reviewer and Tier 3 utility.
- ✅ Reflector loop (opt-in recipe).
- ⚠️ Copilot PR review feature for Stage B (partial).

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Enforcement guard hooks | Self-police, or pair with project-level pre-commit git hooks. Only the Reflector session-end hook is emitted today. |
| Claude's exact agent schema | Eight equivalent Copilot repository agents are emitted. |
| Difficulty/model translation | Role Tier is immutable; first setup writes the saved Tier model into every repository agent. Provider policy can still reject or replace it. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); Copilot's built-in managed memory is separate. |
| Full mechanical guard set | Use emitted reviewer/code-reviewer agents and Copilot PR review; only verified lifecycle hooks are installed. |

## After install — first steps

1. Commit `.github/copilot-instructions.md` (and `.github/instructions/` if you used recipes or `--per-rule`) to your repo. All collaborators automatically pick up the rules.
2. Configure Copilot PR review for Stage B (in repo settings).
3. Skim `.github/copilot-instructions.md` and adjust recipe `applyTo:` globs to your repo layout if needed.
4. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md`.
5. Add `.memory/` to `.gitignore`. Create your first memory entry.

## Quirks / known issues

- Copilot's `applyTo:` glob syntax differs from Cursor's `globs:`; keep adapter-specific fixtures when changing rule scoping.
- TBD: Copilot Chat's instruction-loading order when multiple files match.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
