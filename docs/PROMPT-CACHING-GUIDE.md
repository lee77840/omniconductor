# Prompt Caching Guide (Claude / Anthropic SDK)

> Per ADR-012, CONDUCTOR's Claude adapter actively recommends prompt caching. This guide describes the recommended structure. Caching is an Anthropic-SDK-side concern — CONDUCTOR provides structure and order, not boilerplate code.

## Why prompt caching matters

Anthropic's prompt caching reduces input cost by ~90% and latency by ~85% for
prefixes that repeat across turns. Cache write is 1.25× input cost (5-min cache) or
2× (1-hr cache). Cache read is 0.1× input cost. Break-even after 2-3 reads. See
the current [Anthropic pricing documentation](https://docs.anthropic.com/en/docs/about-claude/pricing)
before using these multipliers for a billing forecast.

Since v1.7, the typical automatic-default install keeps only about 1.7K-2.1K
heuristic tokens always active per adapter in the macOS fixture. The five complete
rules and selected recipes remain byte-identical references and enter context only
when the bounded kernel routes the current activity to them. Project instructions,
memory, history, and tool results remain adopter/provider inputs and are not counted
as CONDUCTOR savings.

Caching still matters for the stable kernel and for complete references repeatedly
read during one workstream, but cache-read tokens are a provider feature. CONDUCTOR
reports cache-read share as a health metric and does not claim the provider's entire
cache saving as its own.

## Recommended prefix order

Order matters: Anthropic prefix-matches from the START of the prompt. Items that change less frequently must come first.

```
[1. Bounded runtime kernel]       ← changes rarely (one CONDUCTOR upgrade)
   - CLAUDE.md

[2. Activity-matched references] ← stable, read only when required
   - .claude/conductor/rules/<matching-rule>.md
   - .claude/conductor/recipes/<matching-recipe>.md

[3. Compact native recipe pointer] ← selected recipe trigger, when its paths match
   - .claude/rules/<recipe>.md

[4. Project memory index]         ← changes weekly, if the adopter uses one

══════ cache_control: {"type": "ephemeral"} ══════

[5. CURRENT_WORK.md content]      ← changes per turn
[6. Recent turn history]          ← changes per turn
[7. Tool results]                 ← per turn
[8. User's new message]           ← per turn
```

The `cache_control` marker is placed at the boundary between sections 4 and 5. Everything above is cacheable; everything below is the per-turn variable content.

## Anthropic SDK example

The exact API call shape depends on the SDK version. Conceptually:

```python
client.messages.create(
    model="claude-opus-4-7-20260101",
    system=[
        # cacheable section
        {
            "type": "text",
            "text": load_kernel() + load_activity_matched_references() + load_memory_index(),
            "cache_control": {"type": "ephemeral"}
        }
    ],
    messages=[
        # per-turn section
        {"role": "user", "content": user_message}
    ]
)
```

The orchestrator's responsibility is to ASSEMBLE the cacheable prefix in stable order. If the order shuffles between turns, the cache misses.

## 5-min vs 1-hr cache

| TTL | Write cost | When to use |
|---|---|---|
| 5 min (default) | 1.25× input | Active dev session — turns within 5 min of each other |
| 1 hr | 2× input | Long-running sessions, tool integrations, agent loops |

For CONDUCTOR's typical use (interactive dev session), 5-min default is correct. The break-even on the 1-hr cache requires 8+ turns within the hour.

## Measuring cache-read token share

Use the bundled tool:

```bash
tools/measure-tokens.sh --latest
```

Sample output:
```
Cache-read tokens            : 9847
Cache-write tokens           : 4512
Input tokens (uncached)      : 127
Cache-read token share       : 67.3%
```

Canonical formula: `cache_read / (cache_read + cache_write + uncached_input)`.
Target: ≥ 95% on a steady-state dev session (ADR-014 as corrected by ADR-076).
Always retain the three raw values; the percentage alone is not attribution to
CONDUCTOR because Claude supplies prompt caching independently. If the share is lower:

- Verify the cache marker is at the right boundary.
- Verify prefix order is stable (no per-turn re-ordering of CONDUCTOR rules).
- Verify the prefix is large enough to clear the model's minimum cache size (1024 tokens for Opus / Sonnet, 2048 for Haiku).

For a multi-session effectiveness audit, use the read-only local JSONL analyzer:

```bash
node tools/audit-token-economy.js \
  --sessions="$HOME/.claude/projects/<encoded-project-directory>" \
  --since=2026-07-28T00:00:00Z
```

It reports tool-result counts, visible CONDUCTOR truncation markers, candidate
threshold reach and estimated elidable tokens, cache-read token share, observed Git
branches, and sub-agent role counts. The threshold estimate is
`ceil(serialized characters / 4)` and excludes marker/schema overhead, so use it to
select a controlled comparison—not as a billing total. A high cache-read share
does not prove the output cap or low-cost role routing fired; inspect those rows
separately and run `omniconductor doctor <project>` on the active branch.

## Common cache misses

| Cause | Fix |
|---|---|
| Prefix too short | Combine universal rules + recipes into a single system block |
| Prefix order changes per turn | Stabilize the build order |
| New recipe installed mid-session | Expected one-time miss; subsequent turns hit |
| Memory index regenerated each turn | Re-generate only when memory dir changes |
| Model switch (Opus ↔ Sonnet ↔ Haiku) | Each model has its own cache; switching invalidates |

## Provider boundary

This guide configures Anthropic API prompt caching; the OMNICONDUCTOR installer does
not configure cache controls for Cursor, Copilot, Gemini, Codex, or Windsurf. A tool
may independently provide or internally manage caching, but that is not treated as a
verified portable OMNICONDUCTOR contract. The `docs/COMPATIBILITY-MATRIX.md` records
the supported boundary.
