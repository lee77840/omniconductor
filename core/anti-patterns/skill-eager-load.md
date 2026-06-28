---
anti_pattern_id: skill-eager-load
name: "Skill / MCP eager-load — every helper injected at session start"
type: anti-pattern
severity: MEDIUM
hit_rate_impact: "+ context bloat (200-600 tokens per skill, compounds)"
detection_method:
  - count auto-loaded skills / MCP servers at session start
  - measure-tokens cache-write delta when skills are added
applies_to: ["claude-code", "any-tool-with-skill-or-MCP-system"]
linked_rules:
  - meta-discipline (5.2 hidden injection awareness, 5.5 tool description compression)
---

# Anti-Pattern 07 — Skill / MCP eager-load

## 1. What it is

Every available skill or MCP server is registered to load eagerly at session start, regardless of whether the current task triggers it. Skill descriptions, tool schemas, and (worst case) full skill bodies enter the cacheable prefix.

```yaml
# WRONG — 30+ skills auto-loaded with full bodies
skills:
  - frontend-design        # 2K tokens, used in 5% of tasks
  - email-template         # 1.5K tokens, used in 2% of tasks
  - payment-webhook        # 2K tokens, used in 1% of tasks
  - playwright-debugging   # 3K tokens, used in 10% of tasks
  - ... (26 more)
```

In the originating project, certain Read paths trigger automatic skill injection:
- `<web-app>/app/**` Read → `next-cache-components` + `next-forge` + `nextjs` (~600 tokens hidden cost per Read)
- `src/components/**/*.tsx` Write → `react-best-practices` (~200 tokens)

If the orchestrator does 50 Reads under those paths in a session, that is 30K tokens of hidden skill injection — none of which the current task may need.

## 2. Why it kills cache

Two failure modes:

- **Prefix bloat**: lazy-loaded skill *descriptions* are usually small (~50 tokens each), but eager-loaded skill *bodies* are 1-3K each. 30 eager-loaded skills = 30-90K tokens of always-cached prefix.
- **Hidden multiplier on Reads**: path-triggered skill injection happens *per Read*, not once per session. The hidden cost compounds with Anti-Pattern 02 (large-file Read).

Per `meta-discipline.md` §5.2: "Some tools auto-inject skill / library docs when certain file paths are touched. These injections add hidden tokens (often 200-600 per Read)."

Reference numbers (originating workspace's `token-economy.md`):
- `<web-app>/app/**` Read: ~600 tokens auto-inject
- `src/components/**/*.tsx` Write: ~200 tokens auto-inject

In a 50-Read session those modifiers alone account for 10-30K tokens of cache-write churn that has no relationship to the user's task.

## 3. Detection

**Skill registry inspection**: at session start, count active skills with full body loaded vs description-only.

**Session JSONL signal**: search for skill body content appearing repeatedly in tool-call results.

**Symptom**: large uncached input + cache-write on the very first turn (before any user message has been processed) → eager-load weight.

## 4. Fix / Alternative

**Three layers of mitigation**:

1. **Description-only skill loading** (per `meta-discipline.md` §5.5): the registry exposes skill names + 1-line descriptions. The skill body loads only when the skill is invoked. On Claude Code, the `Skill` tool already implements this pattern — abuse comes from explicit eager-load configuration.

2. **Path-scoped auto-injection** (per `meta-discipline.md` §5.6): when a tool offers path-triggered skills, ensure the path glob is *narrow*. The reference project pays for `<web-app>/app/**` triggering 3 skills because that glob is broad. Narrowing to `<web-app>/app/api/**/route.ts` (Next.js route handlers only) reduces trigger frequency by ~80%.

3. **MCP gateway / lazy-load proxy**: when many MCP servers are registered, route them through a lazy-loading proxy so only the tool *names* enter the prefix, with full schemas fetched on first use. Reference: `meta-discipline.md` §5.5.

**Conductor's deferred-tool pattern**: this session uses `ToolSearch` to fetch tool schemas only when needed. That is the canonical example — tool names are visible in system reminders, but invoking a tool requires fetching its schema first. The same principle generalizes to skills.

**Cache-position fix**: even when a skill *must* be loaded, position it inside the cacheable prefix (above the cache_control boundary) so subsequent Reads under that path benefit from cache-read pricing (0.1×) rather than fresh injection cost. See `docs/PROMPT-CACHING-GUIDE.md`.

## 5. Severity rating

**MEDIUM** — magnitude depends entirely on how many skills are eager-loaded and how broad the path triggers are. A project with 5 eager skills and tight path globs is fine. A project with 30 eager skills and a top-level `**/*` trigger is severe.

| Configuration | Cache-write impact | Verdict |
|---|---|---|
| Description-only registry, lazy-fetch | minimal | optimal |
| 5-10 eager skills, narrow path triggers | 5-10K | acceptable |
| 30+ eager skills, broad triggers | 30-90K | refactor |
| MCP server fully loaded, no gateway | varies, often 10K+ | mitigate via gateway |
