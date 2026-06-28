# Codex — supported features

Detailed matrix of which CONDUCTOR features Codex supports.

## Feature support

| Feature | Codex support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded project rules** | ✅ Native | `AGENTS.md` | Auto-loaded by Codex on session start. |
| **Shell task execution** | ✅ Strength | Codex's primary capability | One-shot shell scripting is Codex's best use case. |
| **Per-pattern rule scoping** | ❌ | — | All rules always-loaded. |
| **Sub-agent dispatch** | ❌ | — | |
| **Hooks** | ❌ | — | |
| **Per-call model routing** | ❌ | — | |
| **Custom slash commands** | ❌ | — | |
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

## Verification (real-Codex install deferred)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `AGENTS.md` auto-loads | ⏳ deferred | Run Codex in project; verify it cites project conventions. |
