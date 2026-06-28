---
anti_pattern_id: dynamic-system-prompt
name: "Dynamic system prompt — per-turn injection of volatile state"
type: anti-pattern
severity: HIGH
hit_rate_impact: "-50% to -90%"
detection_method:
  - measure-tokens (cache hit rate < 30% with stable prefix size)
  - grep for `Date.now()` / timestamp templating in system-prompt builder
applies_to: ["all-tools-with-prompt-caching"]
linked_rules:
  - meta-discipline (5.4 cache-friendly prompt order)
  - reference: docs/PROMPT-CACHING-GUIDE.md
---

# Anti-Pattern 01 — Dynamic System Prompt

## 1. What it is

The orchestrator builds the system prompt fresh on every turn, with volatile content (current timestamp, session ID, last-edit time, transient state) interleaved with the stable rule body.

```python
# WRONG — invalidates cache every single turn
system = f"""
Today is {datetime.now().isoformat()}.
You have {get_unread_messages()} unread messages.
Last edited file: {last_edited_path}.

[universal rules ...]
[CLAUDE.md ...]
"""
```

Anything before the cache_control marker is part of the prefix that Anthropic prefix-matches from byte 0. A single character that changes per turn invalidates everything after it.

## 2. Why it kills cache

Anthropic prompt caching is **prefix-match-only**. The first byte that differs between two turns is the cache miss point. Everything after — even if textually identical — must be re-written.

Cost model (Anthropic prompt caching docs):
- Cache write = 1.25× input cost (5-min) or 2× (1-hr)
- Cache read = 0.1× input cost
- Break-even after 2-3 reads

If a 12K-token prefix is invalidated every turn:
- Per-turn billed input = 12K × 1.25 = 15K cache-write equivalent
- Vs cached: 12K × 0.1 = 1.2K cache-read
- **Cost multiplier: ~12.5× per turn**

For a 100-turn session: 1.5M extra input tokens vs the cached baseline.

## 3. Detection

**Quantitative signal** (`tools/measure-tokens.sh`):
- Cache hit rate < 30% despite a large stable rule body
- Cache-write tokens roughly equal to cache-read tokens (write-heavy session)

**Code-level signal** (grep over orchestrator harness):
```bash
grep -RIE 'Date|now\(\)|timestamp|uuid|random|process\.uptime' \
  --include='*.{ts,js,py}' src/orchestrator/
```

**Reference baseline**: Conductor's measured baseline (P1.5, 2026-05-07) shows 100% hit rate across 8 sessions of an active dev project, because the system prompt is stable. Any drop from that ceiling deserves investigation.

## 4. Fix / Alternative

**Move volatile state below the cache_control boundary.** The cacheable prefix only contains low-frequency content; per-turn state goes into the user message section.

```python
# RIGHT
system = [
    {
        "type": "text",
        "text": load_universal_rules() + load_project_md() + load_recipes(),
        "cache_control": {"type": "ephemeral"}
    }
]
messages = [
    {
        "role": "user",
        "content": (
            f"Current time: {datetime.now().isoformat()}\n"
            f"Last edited: {last_edited_path}\n"
            f"---\n{user_message}"
        )
    }
]
```

Per `core/universal-rules/meta-discipline.md` §5.4, the order is:

```
[1] Universal rules (lowest change rate)
[2] Project rules
[3] Selected recipes
[4] Memory index
══ cache_control: ephemeral ══
[5] Per-turn state, tool results, user message
```

The Conductor reference project keeps `currentDate` as a system-reminder tag injected by the harness AFTER the cache boundary — not inside the rule body — which is the correct pattern.

## 5. Severity rating

**HIGH** — single biggest cache-invalidator. A 5-minute investigation usually reveals one or two volatile fields that, once moved below the boundary, restore hit rate from <30% to >80%.

| Symptom | Hit-rate hit | Detection difficulty |
|---|---|---|
| Timestamp at top of system | -90% | trivial (grep) |
| User-name template variable | -50% | medium |
| Hash of last commit | -90% | medium |
| Memory index regenerated each turn | -40% | medium |
