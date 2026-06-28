---
anti_pattern_id: tool-call-spam
name: "Tool-call spam — Read repetition where Grep / batched ops would do"
type: anti-pattern
severity: MEDIUM
hit_rate_impact: "indirect: tool-call inflation, output-token spike, latency"
detection_method:
  - measure-tokens (tool calls / turn > 1.5)
  - session JSONL inspection for repeated Reads of the same file
applies_to: ["all-tools-with-Read-Grep"]
linked_rules:
  - meta-discipline (5.1 read discipline)
  - quality-gates (verify-after-changes)
---

# Anti-Pattern 06 — Tool-call spam

## 1. What it is

The orchestrator (or a role) calls many small tools in serial — repeated Reads on the same file, separate Reads instead of one Grep, sequential Bash calls instead of one chained command — when a smaller number of higher-leverage calls would suffice.

```
# WRONG — 5 Reads to find one config value
Read("config/a.ts")  ; not here
Read("config/b.ts")  ; not here
Read("config/c.ts")  ; found!
Read("config/c.ts")  ; re-read for context
Read("config/c.ts")  ; re-read after edit

# WRONG — 4 Bash calls instead of 1 chained
Bash("git status")
Bash("git diff")
Bash("git log -5")
Bash("git branch --show-current")

# RIGHT
Grep("MAX_RETRIES", path="config/", -n=true, -A=3, -B=1)
Bash("git status; git diff; git log -5; git branch --show-current")
```

## 2. Why it kills cache

Two failure modes compound:

- **Per-call overhead**: every tool call adds the call's request + response to the conversation (cache-write next turn) plus invocation latency. Small tool calls have a high *fixed* cost relative to the information returned.
- **Output-token spike**: high tool-call density usually correlates with the model narrating each step ("Now I'll read X…", "That didn't have it, let me check Y…"). Conductor's P1.5 baseline shows output tokens dominate cost (avg 667/turn, top turns 12K-19.7K), and tool-call spam is a primary cause.

Reference numbers (Conductor P1.5):
- Avg tool calls / turn = **0.61** (project baseline; well-disciplined)
- P2 target = **0.43** (-30% reduction)
- Anti-pattern threshold = **> 1.5/turn** sustained

Per the baseline notes: "On average, 61% of turns contain at least one tool call. Total 22,917 tool calls across 37,763 turns." A session at 1.5/turn would have 56K tool calls, doubling tool-overhead cost.

## 3. Detection

```bash
# Tool calls per turn (uses bundled measure-tokens.sh)
bash tools/measure-tokens.sh --latest | grep -E 'tool calls'
```

**Code-level signal** in session JSONL:
```bash
# Count repeated Reads on the same file
grep '"name":"Read"' <session>.jsonl | \
  grep -oE '"file_path":"[^"]+"' | sort | uniq -c | sort -rn | head
# Any file Read > 3 times = candidate for batching / Grep substitution
```

**Self-check (LLM)**: at any point in a turn where the third sequential Read on the same file is about to happen, stop and ask: "would Grep with -A/-B context have found this in one call?"

## 4. Fix / Alternative

**Three principles** (per `meta-discipline.md` §5.1):

1. **Grep before Read** for symbol / value lookup. Use `-A` / `-B` / `-C` for surrounding context.
2. **Range Read** when 50+ contiguous lines are genuinely needed (Anti-Pattern 02 fix).
3. **Batch independent Bash calls** with `;` or `&&` chaining when they don't depend on each other.

**Parallel-tool-calls rule**: when independent calls can run in parallel (e.g., `git status`, `git diff`, `git log` — none depends on the other's output), issue them in a single response with multiple tool invocations rather than serially across N turns.

**Reference**: the originating workspace's `coding-conventions.md` codifies a Pre-Commit Checklist that runs typecheck + tests + build + review *in parallel where possible*. The same parallelism principle applies inside any single turn's tool calls.

## 5. Severity rating

**MEDIUM** — degrades efficiency without breaking correctness. A 2× tool-call density doubles latency and increases output-token cost ~40-60% (the model narrates more). Hit rate is unaffected directly, but session JSONL size grows faster.

| Pattern | Tool calls / turn | Output tokens / turn | Verdict |
|---|---|---|---|
| Disciplined (Conductor baseline) | 0.6 | 670 | optimal |
| Acceptable | 0.8 - 1.2 | 700 - 900 | tolerable |
| Spam threshold | > 1.5 | > 1000 | refactor |
| Severe | > 2.5 | > 1500 | active intervention |
