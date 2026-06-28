# Prompt Caching Guide (Claude / Anthropic SDK)

> Per ADR-012, CONDUCTOR's Claude adapter actively recommends prompt caching. This guide describes the recommended structure. Caching is an Anthropic-SDK-side concern — CONDUCTOR provides structure and order, not boilerplate code.

## Why prompt caching matters

Anthropic's prompt caching reduces input cost by ~90% and latency by ~85% for prefixes that repeat across turns. Cache write is 1.25× input cost (5-min cache) or 2× (1-hr cache). Cache read is 0.1× input cost. Break-even after 2-3 reads.

For a typical CONDUCTOR-driven session:
- 5 universal rule bundles (~6K tokens combined).
- Project CLAUDE.md (~2K tokens).
- Selected recipes (~1-3K tokens).
- Project memory index (~1K tokens).

Total cacheable prefix: ~10-12K tokens. Without caching, 10-12K input tokens are billed every turn. With a 60% hit rate, the effective cost drops to ~1-1.5K tokens per turn.

## Recommended prefix order

Order matters: Anthropic prefix-matches from the START of the prompt. Items that change less frequently must come first.

```
[1. Universal rules]              ← changes rarely (one CONDUCTOR upgrade per quarter)
   - .claude/rules/workflow.md
   - .claude/rules/spec-as-you-go.md
   - .claude/rules/quality-gates.md
   - .claude/rules/operations.md
   - .claude/rules/meta-discipline.md

[2. Project CLAUDE.md]            ← changes occasionally (project rule additions)

[3. Selected recipes]             ← changes when adopter installs / removes recipe
   - .claude/rules/<recipe>.md (per --recipes flag)

[4. Project memory index]         ← changes weekly (new feedback / project entries)

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
            "text": load_universal_rules() + load_claude_md() + load_recipes() + load_memory_index(),
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

## Measuring cache hit rate

Use the bundled tool:

```bash
tools/measure-tokens.sh --latest
```

Sample output:
```
Cache-read tokens            : 9847
Cache hit rate               : 67.3%
```

Target: ≥ 60% on a steady-state dev session. If the rate is lower:

- Verify the cache marker is at the right boundary.
- Verify prefix order is stable (no per-turn re-ordering of CONDUCTOR rules).
- Verify the prefix is large enough to clear the model's minimum cache size (1024 tokens for Opus / Sonnet, 2048 for Haiku).

## Common cache misses

| Cause | Fix |
|---|---|
| Prefix too short | Combine universal rules + recipes into a single system block |
| Prefix order changes per turn | Stabilize the build order |
| New recipe installed mid-session | Expected one-time miss; subsequent turns hit |
| Memory index regenerated each turn | Re-generate only when memory dir changes |
| Model switch (Opus ↔ Sonnet ↔ Haiku) | Each model has its own cache; switching invalidates |

## Non-Claude tools

Prompt caching is an Anthropic-specific feature. Other adapters (Cursor / Copilot / Gemini / Codex / Windsurf) cannot benefit from this guide. The `docs/COMPATIBILITY-MATRIX.md` records this honestly.
