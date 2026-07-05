---
anti_pattern_id: no-sub-agent-dispatch
name: "No sub-agent dispatch — large work runs in main thread"
type: anti-pattern
severity: MEDIUM
hit_rate_impact: "indirect: main-thread context bloat, output-token spike"
detection_method:
  - measure-tokens (sub-agent dispatches per session vs total tool calls)
  - session JSONL size > 100MB on a non-trivial project
applies_to: ["claude-code", "tools-with-native-sub-agent"]
linked_rules:
  - meta-discipline (5.3 sub-agent dispatch discipline, 7 flat-with-leader)
---

# Anti-Pattern 04 — No sub-agent dispatch

## 1. What it is

The orchestrator handles every task — multi-file refactors, large file generations, verbose test runs, repository searches — directly in the main thread, never dispatching to a role agent. All output, intermediate reasoning, and tool results accumulate in the leader's context.

```
# WRONG — 30 Reads + 12 Edits + 8 Bash test runs in main thread
Main thread: "Let me audit all 24 page components for the redesign..."
  Read page-1.tsx (full)
  Read page-2.tsx (full)
  ... (22 more)
  Edit page-1.tsx
  ... (23 more)
  Bash npm test (verbose output)
  Bash npm run build (verbose output)
```

By the end of the task the main-thread context holds the full text of 24 files plus build/test output — easily 100K+ tokens that linger for the rest of the session.

## 2. Why it kills cache

Sub-agent isolation is the cleanest known mechanism for context hygiene on tools that support it:

- The dispatched role gets a fresh context, does the work, and returns a *summary* (typically 0.5-2K tokens).
- The main thread accumulates only the summary, not the verbose intermediate state.
- The cacheable prefix in the main thread stays small.

Without dispatch:
- Verbose test/build output (often 5-15K tokens) lives in main-thread history forever.
- 24-file refactor leaves 24 file bodies in main-thread cache-read on every subsequent turn.
- Cache-write per turn climbs as the conversation continues — cache hit rate stays high but the *absolute size* of cached content compounds.

**Reference data** (Conductor P1.5 baseline): the two largest sessions (219MB + 187MB) both contained heavy in-thread work; smaller sessions with active dispatch use stayed under 70MB. Avg dispatches/session = 104.6. The recommended P2 target is -25% dispatch *frequency* (batch related work) but the *anti-pattern* of zero dispatch is far more costly than over-dispatch.

### 2.1 Honest caveat — dispatch saves the *lead's* context, not the *total* token bill

Dispatch is a **context-isolation** win, not a raw total-token saver. Anthropic's own multi-agent reporting is explicit: single agents use ~4× the tokens of a chat interaction, and multi-agent systems ~15× — because every dispatched agent runs its own context window and reasoning. What dispatch buys is:

- a **lean leader context** (only the 0.5–2K summary returns, so the cacheable main thread stays small), and
- **higher fidelity** (the verbose intermediate state that would dilute the leader's attention budget stays quarantined in the sub-agent).

So dispatch when the *value of isolation* (a clean leader + focused attention) exceeds the *added total token cost* — i.e. verbose, self-contained subtasks. Do NOT dispatch work that needs the leader's full shared context or has tight back-and-forth dependencies: there the coordination overhead and duplicated context make a single thread both cheaper and more faithful. (Anthropic: tasks requiring "all agents to share the same context" or with "many dependencies between agents" are a poor fit; "most coding tasks involve fewer truly parallelizable tasks than research.")

## 3. Detection

**Quantitative**:
- Sub-agent dispatches / session = 0 on multi-feature work → red flag
- Total tool calls / dispatches ratio > 200 → main-thread-heavy

```bash
# Reference command via measure-tokens.sh:
bash tools/measure-tokens.sh --latest | grep -E 'dispatches|tool calls'
```

**Symptom**: session JSONL grows past 100MB; latency per turn climbs noticeably as the session ages.

## 4. Fix / Alternative

**Per `meta-discipline.md` §7 (flat-with-leader topology)**: orchestrator dispatches role agents. Roles never dispatch each other.

Rules of thumb (when to dispatch):
- Multi-file refactor (3+ files cross-cutting) → builder role
- Verbose test/build runs → helper role with `output_format=summary`
- Repository-wide search across an unfamiliar codebase → explorer role
- Long-form documentation generation → scribe role
- Anything expected to take > 2 min wall clock → background dispatch

Dispatch brief budget: ≤ 2K tokens (per `meta-discipline.md` §5.3). Reference files by path, do NOT paste content.

**Single-Agent Mode fallback**: tools that lack native sub-agents (Cursor, Copilot, Gemini, Codex, Windsurf) cannot use this fix. Conductor's `core/universal-rules/meta-discipline.md` §6.6 records this honestly. On those tools, mitigate with:
- Aggressive auto-compact at ~70% context
- Aggressive Grep-before-Read discipline
- Output-redirect to file (run verbose tools with `> /tmp/log` and tail-Read only the last N lines)

## 5. Severity rating

**MEDIUM** — significant but tool-conditional. On Claude Code with native sub-agents, dispatch hygiene is the difference between a 65MB and a 220MB session JSONL. On tools without sub-agents, the rule degrades to compaction discipline.

| Pattern | Main-thread context after 50 turns | Cost |
|---|---|---|
| All work in main thread | 100-200K tokens accumulated | high — every subsequent turn re-reads all of it |
| Dispatch verbose work to roles | 10-20K tokens (summaries only) | low — main thread stays lean |
| Dispatch + structured-summary return | 5-10K tokens | optimal |
