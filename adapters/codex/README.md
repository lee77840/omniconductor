# Adapter — Codex (T2)

OpenAI Codex (the modern shell-driven agent — not the deprecated original Codex API) is a T2 target because:

- It supports a single project rules file at `AGENTS.md` (project root — the established cross-agent convention), auto-loaded on session start.
- It excels at shell-driven scripting and agentic terminal work.

**Tool capability vs CONDUCTOR emission (ADR-031/045):** Codex supports hooks, sub-agent dispatch,
custom agents, per-task model routing, commands, and managed memory. CONDUCTOR emits eight native
role profiles and the verified commit/session/review hook subset. Its project file has a bounded
input budget, so the adapter keeps a compact non-negotiable kernel in `AGENTS.md` and installs the
complete universal rules and selected recipes as explicitly routed on-demand references.

**Tier**: T2 (see `docs/COMPATIBILITY-MATRIX.md`). Live-verified via the automated headless probe (`tools/live-verify.sh` — current status in `docs/ADAPTER-LIVE-VERIFICATION.md`).

> Enumerable facts about this adapter (output paths / tier / capabilities / live verification / headless CLI) are machine-readable in [`metadata.json`](./metadata.json) and CI-checked against `transform.sh` + the validator (ADR-040).


## Installation path

```bash
bash adapters/codex/transform.sh <target>                          # install
bash adapters/codex/transform.sh <target> --recipes=tdd,debugging  # + opt-in recipes
bash adapters/codex/transform.sh <target> --dry-run --no-prompt    # preview, write nothing
bash adapters/codex/transform.sh <target> --uninstall              # revert (manifest-based)
```

The local `transform.sh` command requires Node.js and delegates to the same CLI,
including the one-time project-saved Tier-model setup. It is not a model-routing
bypass.

## What gets installed

```
<target>/
├── AGENTS.md                                   # Bounded always-loaded runtime kernel
├── .codex/
│   ├── conductor/rules/*.md                    # Complete universal-rule references
│   ├── conductor/recipes/*.md                  # Complete selected recipes
│   ├── agents/*.toml                           # Eight native role profiles
│   ├── hooks/*.sh
│   └── hooks.json
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
- ✅ Compact always-loaded execution contract plus complete on-demand universal rule text.
- ✅ All doc templates.
- ✅ Eight native `.codex/agents/*.toml` role profiles, including Tier 3 utility.
- ✅ Verified Codex-native commit/session/review guards.
- ✅ Reflector loop (opt-in recipe).
- ✅ Strong shell-task execution (Codex's primary strength).

## Capability boundary

| Feature | Interim workaround |
|---|---|
| Per-pattern rule scoping | `AGENTS.md` routes to complete `.codex/conductor/` references; Codex still scopes by hierarchy, not globs. |
| Claude-only Agent/Read hook contracts | Not translated. Codex receives only hooks with verified Codex event/input/output behavior. |
| Unsupported `permissionDecision: "ask"` | Never active; non-blocking warnings use `additionalContext`. |
| Difficulty/model translation | First setup recommends and saves Sol/Terra/Luna; Tier 1/2/3 independently compiles to high/medium/low reasoning. Local catalog availability is validated when available. Every real install reloads this saved mapping and ignores inherited model overrides. |
| 4-type memory pattern | Self-managed at `.memory/` (gitignored); Codex's built-in managed memory is separate. |

## Best fit use cases

- Shell-driven agentic work and scripting.
- One-shot file transformations and quick git operations.
- Headless automation (`codex exec` — the Reflector weekly runner uses it).

## After install — first steps

1. Verify Codex reads the compact `AGENTS.md` kernel (auto-loaded from the project root).
2. Keep `AGENTS.md` below the validator budget; put detailed additions in linked project docs.
3. Run `/hooks`, review and trust the project hook definitions.
4. Add `.memory/` to `.gitignore` if using the project-local memory convention.

## Quirks / known issues

- Output is `AGENTS.md` at the project root (the established cross-agent convention adopted by
  OpenAI Codex / Codex CLI), superseding the early-design `.codex/codex.md` guess.
- Codex truncates oversized project instructions. The validator caps the generated kernel at
  24 KiB, doctor fails files above the default 32 KiB budget, and complete text remains under
  `.codex/conductor/` for explicit loading.

## Status

- ✅ `README.md`
- ✅ `SUPPORTED-FEATURES.md`
- ✅ `transform-spec.md`
- ✅ `transform.sh` (implemented — bounded kernel, complete references, recipes, dry-run, manifest-based uninstall)
- ✅ Live-verified (auto-probe `tools/live-verify.sh` — see `docs/ADAPTER-LIVE-VERIFICATION.md`)
