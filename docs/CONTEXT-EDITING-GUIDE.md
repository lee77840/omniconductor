# Context Editing Guide (Claude / Anthropic SDK)

> Per ADR-035, CONDUCTOR's Claude adapter recommends **API context editing** as the *lossless-first* way to reduce context tokens without losing the user's instructions. This guide describes the mechanism, the fidelity guarantee, and the safeguards for the lossy fallback (`/compact`). Like prompt caching (`docs/PROMPT-CACHING-GUIDE.md`), context editing is an Anthropic-SDK-side concern — CONDUCTOR provides discipline and ordering, not boilerplate code.
>
> **Scope:** Claude API / Claude Code only. The five non-Claude adapters degrade to the rule text in `meta-discipline.md` §5.7. See the parity note at the end.

## Why this exists — the fidelity axis

Every token in the window depletes a finite **attention budget**, and as the window grows the model's ability to recall any single item decreases ("context rot"). So reducing context is genuinely valuable — but the naive reducer (summarize old turns) compresses the *user's own instructions* along with everything else, silently dropping or distorting the original intent.

The core rule: **cut stale tool output first; touch user instructions last.** Tool results (file reads, command output, search hits) are the bulk of a bloated window and carry near-zero forward value once acted on. Clearing them frees most of the budget while leaving every user turn intact.

## The two reducers, ranked by fidelity

| Reducer | What it removes | Instruction fidelity | When to use |
|---|---|---|---|
| **API context editing** (`clear_tool_uses`) | Stale tool **results** (and optionally tool inputs / thinking blocks) | **Preserved** — user instructions and text messages are never cleared | **Default.** Long tool-heavy sessions. |
| **`/compact`** (Claude Code) | Summarizes **all** older history, user turns included | **At risk** — lossy summarization can drop or distort the original ask | Last resort, with the safeguards below. |
| **`/clear`** (Claude Code) | Wipes the entire context | N/A (intentional full reset) | Between *unrelated* tasks. |

### Verified mechanics (primary sources)

**API context editing** — Anthropic Messages API, public beta (verified 2026-07):
- Beta header: `context-management-2025-06-27`. Strategy id: `clear_tool_uses_20250919`.
- **Clears** stale tool *results*; optionally tool *inputs* (`clear_tool_inputs: true`, default `false`) and thinking blocks (`clear_thinking_20251015`). Cleared results are replaced with placeholder text.
- **Never clears** user instructions or text messages — editing targets tool results / thinking only.
- Defaults: `trigger` = 100,000 input tokens; `keep` = 3 most-recent tool-use/result pairs. `clear_at_least` and `exclude_tools` are optional knobs.
- Applied **server-side** before the prompt reaches the model; the client keeps the full history. ZDR-eligible.
- Measured savings: doc example 70k → 25k tokens (~45k freed); an Anthropic 100-turn web-search eval reported **~84% token reduction**. Paired with the **memory tool** (file-based state that persists *outside* the window, same beta header), Anthropic reported **+39%** on their eval vs baseline (context editing alone **+29%**).
- Source: <https://platform.claude.com/docs/en/build-with-claude/context-editing> · <https://claude.com/blog/context-management>

**`/compact` vs `/clear`** — Claude Code (verified 2026-07):
- Auto-compaction summarizes conversation history when "approaching context limits" (exact % trigger is **not** documented). It preserves architectural decisions / unresolved bugs / implementation details and discards redundant tool output — but it is a *lossy* summary of everything, including your turns.
- Preservation levers: (a) `/compact <instructions>` — e.g. `/compact Focus on code samples and API usage`; (b) a `# Compact instructions` section in the project **CLAUDE.md** telling Claude what to preserve across every compaction.
- `/clear` starts fresh (full wipe); `/compact` compresses and continues.
- Source: <https://code.claude.com/docs/en/costs>

## Recommended discipline (what the orchestrator does)

1. **Default to lossless.** On the Claude API adapter, enable context editing (`clear_tool_uses`) so stale tool results are cleared automatically at the token trigger. This alone removes most window bloat without any risk to instructions.
2. **Protect against tool-input loss where inputs matter.** Leave `clear_tool_inputs` at its default (`false`), or list tools whose call arguments must be retained under `exclude_tools`.
3. **Keep durable instructions out of chat history.** Put anything that must survive the whole session in CLAUDE.md / project rules — it is re-loaded each turn and is unaffected by both compaction and context editing.
4. **If lossy compaction is unavoidable**, pass explicit preservation instructions (`/compact keep the original task statement, acceptance criteria, and open TODOs verbatim`) and/or maintain a `# Compact instructions` block in CLAUDE.md.
5. **Reset, don't bloat.** Between unrelated tasks, `/clear` beats letting the window fill and then lossily compacting.
6. **Re-verify after compaction.** Confirm the compacted note still carries the original instruction before continuing; if unsure, ask the user to restate rather than act on a possibly-distorted summary.

## Interaction with prompt caching

Context editing modifies the message body **below** the cached rule/CLAUDE.md prefix, so it does not touch the stable cache prefix described in `PROMPT-CACHING-GUIDE.md`. The two techniques compose: caching cuts the cost of the stable prefix; context editing cuts the size of the volatile tail. Note that clearing tool results changes the suffix, which is expected — the cache breakpoint sits above it.

## Per-tool parity (honest)

| Tool | Lossless tool-result clearing | Compaction levers |
|---|---|---|
| Claude Code / Claude API | **Yes** — `clear_tool_uses` + memory tool | `/compact <instr>`, `# Compact instructions`, `/clear` |
| Cursor / Copilot / Gemini / Codex / Windsurf | No equivalent API feature — falls back to `meta-discipline.md` §5.7 rule text (drop stale reads, keep instructions in the rules file, reset between tasks) | Tool-native reset only |

The honest summary: the *principle* (cut stale tool output first, never the user's instructions) is universal and lives in `meta-discipline.md` §5.7; the *lossless mechanism* is Claude-API-only today.
