# Codex — supported features

Detailed matrix of which CONDUCTOR features Codex supports.

## Feature support

| Feature | Codex support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded project rules** | ✅ Native | `AGENTS.md` | Bounded kernel auto-loaded on session start. |
| **Shell task execution** | ✅ Strength | Codex's primary capability | One-shot shell scripting is Codex's best use case. |
| **Per-pattern rule scoping** | ❌ | — | All rules always-loaded. |
| **Sub-agent dispatch** | ✅ Native (2026) | Custom named agents in `.codex/agents/*.toml` | See `docs/COMPATIBILITY-MATRIX.md` / ADR-031. |
| **Hooks (Stop etc.)** | ✅ Emitted subset | `.codex/hooks.json` + `.codex/hooks/*.sh` | Commit/current-work/test, session/spec, pre-merge review, and recipe-gated guards. |
| **Per-task model routing** | ✅ Configured native (2026) | Saved model + `model_reasoning_effort` | Recommended Sol/Terra/Luna; Tier 1/2/3 independently maps to high/medium/low. |
| **Custom slash commands** | ✅ Native (2026) | Skills at `.agents/skills/*/SKILL.md` | ADR-031. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Read on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ✅ Guard + rule | Codex Stop hook | Guardrail, not a complete security boundary. |
| **Two-stage code review enforcement** | ✅ Guard + role | reviewer + code-reviewer + Stop review check | |
| **Multi-step orchestration** | ✅ Native roles | `.codex/agents/*.toml` | Eight profiles use the saved project Tier mapping. |

## Universal-rule → Codex runtime translation

For each `core/universal-rules/<rule>.md`:

1. Compile a compact non-negotiable execution contract into always-loaded `AGENTS.md`.
2. Strip front-matter and preserve each complete rule in `.codex/conductor/rules/*.md`.
3. Route activities from the kernel to the exact detailed rule that must be read.
4. Store selected recipes in `.codex/conductor/recipes/*.md` and add compact pointers.

## Strengths to lean into

- Native role separation for planning, building, and review.
- The bounded `AGENTS.md` kernel plus deterministic hooks gives Codex reliable project context and mechanical reminders.
- First setup recommends Sol/Terra/Luna, validates the local catalog when available, and preserves the independent high/medium/low effort mapping. Every real install reloads the saved project mapping; inherited environment values cannot replace it.

## Weaknesses to acknowledge

- Hook interception is incomplete for equivalent tool paths, so do not treat it as a security boundary.
- Detailed references are not automatically loaded; the kernel requires reading the relevant file before that class of work.

## transform.sh status

✅ **Implemented.** `adapters/codex/transform.sh` emits a bounded `AGENTS.md` runtime kernel,
complete `.codex/conductor/rules/*.md` references, selected recipe references, and universal
`docs/` templates. Supports `--recipes=`,
`--dry-run`, `--no-prompt`, and manifest-based `--uninstall`/`--force`. Output target is `AGENTS.md`
at the project root (the established cross-agent convention), not the early-design `.codex/codex.md`.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Codex adapter emits the Reflector loop (ADR-032):

- **Hook**: `.codex/hooks.json` — full/strict registries include the Reflector Stop hook. Manifest-owned registries update safely; user-owned registries are preserved for manual merge.
- **Command**: `.agents/skills/reflect/SKILL.md` — the `/reflect` skill that distills the trajectory log into lesson candidates.
- **Agent**: `.codex/agents/reflector.toml` — named reflector agent for the distillation pass.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `AGENTS.md` auto-loads | ✅ verified | Live verification is recorded in the generated compatibility table. |
| Kernel end remains model-visible | ✅ native local probe | `codex debug prompt-input` includes `CONDUCTOR_KERNEL_END`; validator and doctor enforce byte budgets. |
| Native agent profiles parse | ✅ regression-verified | Full install validates all eight `.codex/agents/*.toml` profiles. |
| Hook registry and scripts are runnable | ✅ regression-verified | Full install parses `.codex/hooks.json`, checks every referenced executable, runs `bash -n`, and exercises the PreTool output dialect. |
| Unsupported Claude `ask` decision is absent | ✅ negative-tested | The runtime suite rejects an unpinned `permissionDecision: ask` fixture. |
