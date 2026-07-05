# Codex — supported features

Detailed matrix of which CONDUCTOR features Codex supports.

## Feature support

| Feature | Codex support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded project rules** | ✅ Native | `AGENTS.md` | Auto-loaded by Codex on session start. |
| **Shell task execution** | ✅ Strength | Codex's primary capability | One-shot shell scripting is Codex's best use case. |
| **Per-pattern rule scoping** | ❌ | — | All rules always-loaded. |
| **Sub-agent dispatch** | ✅ Native (2026) | Custom named agents in `.codex/agents/*.toml` | See `docs/COMPATIBILITY-MATRIX.md` / ADR-031. |
| **Hooks (Stop etc.)** | ✅ Native (2026) | `.codex/hooks.json` | ADR-031. CONDUCTOR currently emits only the Reflector hook (ADR-032); broader hook-set emission is Phase 2. |
| **Per-task model routing** | ✅ Native (2026) | Per-agent `model` in agent TOML | ADR-031. |
| **Custom slash commands** | ✅ Native (2026) | Skills at `.agents/skills/*/SKILL.md` | ADR-031. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/`. |
| **In-repo doc templates** | ✅ Universal | Plain markdown | Read on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text in `AGENTS.md` reminds | Self-policed. |
| **Two-stage code review enforcement** | ❌ rule reminder only | | |
| **Multi-step orchestration** | ⚠️ Limited | Sequential prompts | For complex multi-step work, prefer Claude/Cursor. |

## Universal-rule → Codex bundle translation

For each `core/universal-rules/<rule>.md`:

1. Strip front-matter (Codex doesn't use it).
2. Concatenate body into `AGENTS.md` as a section with heading `## <rule name>`.
3. Tool-specific callouts:
   - `> **Codex-only mechanism**` (rare): keep.
   - `> **Claude-only mechanism**`: REPLACE with `> **Note (Codex)**: enforced by hook on Claude Code; on Codex, follow self-policed.`
   - Other tool callouts: STRIP.

## Strengths to lean into

- One-shot shell tasks (the orchestrator role isn't really meaningful here).
- The `AGENTS.md` rule bundle gives Codex enough context to follow project conventions for code it generates inline.

## Weaknesses to acknowledge

- Multi-step orchestration is awkward in Codex. Consider Codex a "specialist" tool — use it for shell tasks; use Claude/Cursor for the orchestrator workflow.
- Bundled rules approach the context limit faster on smaller models. If `AGENTS.md` becomes too large, consider trimming the workflow phase definitions (keep universal rules + ABSOLUTE rules).

## transform.sh status

✅ **Implemented.** `adapters/codex/transform.sh` emits a single-file `AGENTS.md` bundle (Codex-flavored
bilingual intro + ABSOLUTE-rules summary + 5 universal rules sans frontmatter + compressed workflow +
opt-in recipes + DIY `.memory/` note) plus universal `docs/` templates. Supports `--recipes=`,
`--dry-run`, `--no-prompt`, and manifest-based `--uninstall`/`--force`. Output target is `AGENTS.md`
at the project root (the established cross-agent convention), not the early-design `.codex/codex.md`.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Codex adapter emits the Reflector loop (ADR-032):

- **Hook**: `.codex/hooks.json` — registers `.conductor/reflect/trajectory-log.sh` on the `Stop` event. Written only if no hook config exists; if one is already present, the adapter emits a manual-merge log entry instead of overwriting.
- **Command**: `.agents/skills/reflect/SKILL.md` — the `/reflect` skill that distills the trajectory log into lesson candidates.
- **Agent**: `.codex/agents/reflector.toml` — named reflector agent for the distillation pass.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification (real-Codex install deferred)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `AGENTS.md` auto-loads | ⏳ deferred | Run Codex in project; verify it cites project conventions. |
