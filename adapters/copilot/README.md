# Adapter — GitHub Copilot (T2)

GitHub Copilot is a T2 target because:

- It supports per-pattern rule scoping via `.github/instructions/*.instructions.md` `applyTo:` front-matter.
- Instructions live IN the repo, so all collaborators automatically share them.
- Copilot's PR review feature provides a partial Stage B code-review analog tied to GitHub.

**Tool capability vs CONDUCTOR emission (ADR-031):** as of 2026 Copilot ships hooks (CLI + cloud + VS Code), sub-agent dispatch, custom agents, per-task model routing, commands, and built-in managed memory. What is limited today is what CONDUCTOR **emits** for it — rule text + docs + the opt-in Reflector loop; the enforcement guard hooks, role agents, and model-routing config are Phase-2 emission (ADR-034). That is a CONDUCTOR gap, not a Copilot limitation.

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md` — hooks + sub-agents + per-task model + commands all present; caveats: `applyTo:` glob scoping works, but the coding agent has no transcript API).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


## Installation path

```bash
# Recommended (npm, no clone):
npx omniconductor init --target=copilot <target-dir>

# Or from a local clone:
bash /path/to/conductor/adapters/copilot/transform.sh /path/to/target [--dry-run] [--per-rule]
```

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
- ✅ Reflector loop (opt-in recipe).
- ⚠️ Copilot PR review feature for Stage B (partial).

## Not emitted yet (Phase 2 — Copilot supports these natively, ADR-031/034)

| Feature | Interim workaround |
|---|---|
| Enforcement guard hooks | Self-police, or pair with project-level pre-commit git hooks. Only the Reflector session-end hook is emitted today. |
| The 6 role agents (sub-agent dispatch) | Copilot has native agents; CONDUCTOR doesn't emit its role definitions for Copilot yet. Human plays orchestrator. |
| Per-call model-routing config | Pick the model in Copilot Chat UI per task (Copilot supports per-task model selection). |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); Copilot's built-in managed memory is separate. |
| Specialized review agents (Stage A) | Run review prompts manually in Copilot Chat. Use Copilot PR review for Stage B (best-effort). |

## After install — first steps

1. Commit `.github/copilot-instructions.md` (and `.github/instructions/` if you used recipes or `--per-rule`) to your repo. All collaborators automatically pick up the rules.
2. Configure Copilot PR review for Stage B (in repo settings).
3. Skim `.github/copilot-instructions.md` and adjust recipe `applyTo:` globs to your repo layout if needed.
4. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md`.
5. Add `.memory/` to `.gitignore`. Create your first memory entry.

## Quirks / known issues (P3 will fill)

- TBD: Copilot's `applyTo:` glob syntax differs slightly from Cursor's `globs:`. P3 verifies the exact dialect.
- TBD: Copilot Chat's instruction-loading order when multiple files match.

## Status (P0 foundation)

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented)
- ⏳ `notes.md` (P3)
