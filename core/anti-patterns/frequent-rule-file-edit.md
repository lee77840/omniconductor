---
anti_pattern_id: frequent-rule-file-edit
name: "Frequent rule-file edits — invalidating the cache prefix every session"
type: anti-pattern
severity: MEDIUM
hit_rate_impact: "-20% to -40% over a working week"
detection_method:
  - git log on rule files (commits per week to CLAUDE.md / universal rules)
  - measure-tokens cache-write delta across consecutive sessions
applies_to: ["all-tools-with-prompt-caching"]
linked_rules:
  - workflow (W2 docs-first)
  - meta-discipline (5.4 cache-friendly prompt order)
---

# Anti-Pattern 05 — Frequent rule-file edits

## 1. What it is

The project's main rule file (CLAUDE.md / AGENT.md / GEMINI.md / equivalent) — i.e. the file at the **top of the cache prefix** — is edited multiple times per week. Every edit, no matter how small, invalidates the cache for the next session that reloads it.

```
# WRONG — every other day:
git log --oneline -- CLAUDE.md
ab12cd3 docs(claude): tweak workflow phrasing
de45f67 docs(claude): add new helper agent description
89ab012 docs(claude): fix typo in section 4
3456cde docs(claude): inline new troubleshooting tip
```

Each commit produces a different prefix bytes-wise, so the next session that loads the rule file pays the full cache-write again.

## 2. Why it kills cache

Anthropic prompt caching is **prefix-match**. The cache key is the byte sequence of the prefix. A single typo fix changes the byte sequence and the cache must be re-written.

Cost model:
- 5-min cache TTL → applies within a single session, robust to rule edits inside that session
- Cross-session cache reuse depends on prefix byte-identity from the previous session

Edit frequency vs hit rate (estimated, derived from Anthropic prompt caching docs cost model):

| Edits/week to top-of-prefix file | Cross-session prefix reuse | Estimated hit-rate hit |
|---|---|---|
| 0 (stable) | full | 0% |
| 1 | mostly, occasional miss | -10% |
| 3 | partial, frequent miss | -25% |
| 5+ | nearly always missed | -40% |

If the rule file is edited daily, every session starts with a fresh cache write — a 30K-token write for the prefix alone, costing 1.25× input baseline.

## 3. Detection

```bash
# Edits per week to top-of-prefix files
git log --since='1 week ago' --pretty=format:'%h %s' -- \
  CLAUDE.md AGENT.md GEMINI.md .codex/codex.md \
  .claude/rules/*.md .cursor/rules/*.mdc 2>/dev/null | wc -l

# Anything > 3 in a week is suspect
```

**Symptom in measure-tokens output**: cache-write tokens / session stays high across multiple sessions even when conversation length is short. A stable rule file shows declining cache-write/turn as the session ages; an edited rule file resets that decline every session.

## 4. Fix / Alternative

**Three disciplines** (compounding):

1. **Batch edits.** Accumulate rule changes over a few days, then commit one consolidated update. Reference project policy: docs-only changes wait until the next code-bearing push (per `feedback_push_timing` in the originating project's memory).

2. **Move volatile content downward.** New ad-hoc reminders, post-mortems, "watch out for X" notes belong in `CURRENT_WORK.md` (per-turn area, BELOW the cache boundary), not in the rule file.

3. **Split paths-scoped from always-loaded.** When new content is path-relevant (e.g. "billing pitfalls"), put it in a path-scoped rule file (Anti-Pattern 03 fix), not the always-loaded floor.

**Conductor's own policy** (per `core/universal-rules/README.md`): the 5 universal-rule bundles change "rarely (one CONDUCTOR upgrade per quarter)". Project-specific rules go in `core/recipes/` (opt-in). The recipe layer is intentionally below the universal-rule layer in the cache prefix order, so recipe edits invalidate less.

**Reference**: `docs/PROMPT-CACHING-GUIDE.md` "Common cache misses" table lists "Prefix order changes per turn" — same root cause as frequent edits.

## 5. Severity rating

**MEDIUM** — the harm is gradual rather than per-turn catastrophic. A team that edits the rule file once a week loses ~10% hit rate; a team that edits it daily loses 30-40%. The cumulative cost over a quarter is significant but rarely visible in any single session.

The fix is cheap: discipline + batch.
