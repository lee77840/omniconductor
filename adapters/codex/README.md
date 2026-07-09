# Adapter — Codex (T2)

OpenAI Codex (the modern shell-driven agent — not the deprecated original Codex API) is a T2 target because:

- It supports a single project rules file at `AGENTS.md` (project root — the established cross-agent convention), auto-loaded on session start.
- It excels at shell-driven scripting and agentic terminal work.

**Tool capability vs CONDUCTOR emission (ADR-031):** as of 2026 Codex ships hooks (default-on), sub-agent dispatch, custom agents, per-task model routing, commands, and built-in managed memory. What is limited today is what CONDUCTOR **emits** for it — rule text + docs + the opt-in Reflector loop; the enforcement guard hooks, role agents, and model-routing config are Phase-2 emission (ADR-034). That is a CONDUCTOR gap, not a Codex limitation. Real tool-side caveat: rules scope by nested-file hierarchy, not glob — the adapter bundles everything into one `AGENTS.md`.

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md`). Live-verified 2026-06-28 (codex-cli loaded the emitted `AGENTS.md` — `docs/ADAPTER-LIVE-VERIFICATION.md`).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


## Installation path

```bash
bash adapters/codex/transform.sh <target>                          # install
bash adapters/codex/transform.sh <target> --recipes=tdd,debugging  # + opt-in recipes
bash adapters/codex/transform.sh <target> --dry-run --no-prompt    # preview, write nothing
bash adapters/codex/transform.sh <target> --uninstall              # revert (manifest-based)
```

## What gets installed

```
<target>/
├── AGENTS.md                                   # Codex-flavored intro + 5 universal rules + compressed workflow + selected recipes + memory note
└── docs/
    ├── CURRENT_WORK.md                         # Universal templates
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

- `--recipes=self-improvement` additionally emits the Reflector loop: session-end trajectory hook config (`.codex/hooks.json`), `/reflect` command, reflector agent, prune script, and the `.conductor/reflect/` weekly runner (ADR-032/033).

## Native features supported (emitted today)

- ✅ Always-loaded baseline (`AGENTS.md`).
- ✅ All universal rule TEXT.
- ✅ All doc templates.
- ✅ Reflector loop (opt-in recipe).
- ✅ Strong shell-task execution (Codex's primary strength).

## Not emitted yet (Phase 2 — Codex supports these natively, ADR-031/034)

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | All rules always-loaded in one `AGENTS.md` (Codex scopes by nested-file hierarchy, not globs). |
| Enforcement guard hooks | Self-police, or pair with project pre-commit git hooks. Only the Reflector session-end hook is emitted today (`--recipes=self-improvement`). |
| The 6 role agents (sub-agent dispatch) | Codex has native sub-agents; CONDUCTOR doesn't emit its role definitions for Codex yet. Human plays orchestrator. |
| Per-call model-routing config | Pick the model per invocation via Codex's own model selection. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); Codex's built-in managed memory is separate. |

## Best fit use cases

- Shell-driven agentic work and scripting.
- One-shot file transformations and quick git operations.
- Headless automation (`codex exec` — the Reflector weekly runner uses it).

## After install — first steps

1. Verify Codex reads `AGENTS.md` (auto-loaded from project root on session start).
2. Customize `AGENTS.md` for your project as needed.
3. Add `.memory/` to `.gitignore`.

## Quirks / known issues

- Output is `AGENTS.md` at the project root (the established cross-agent convention adopted by
  OpenAI Codex / Codex CLI), superseding the early-design `.codex/codex.md` guess.
- Single-file model: everything Cursor splits across `.cursor/rules/*.mdc` is concatenated into
  `AGENTS.md`. All rules are always-on — Codex has no per-pattern scoping.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented — single-file `AGENTS.md` bundle, recipes, dry-run, manifest-based uninstall)
- ✅ Live-verified 2026-06-28 (codex-cli loaded the emitted `AGENTS.md` — see `docs/ADAPTER-LIVE-VERIFICATION.md`)
