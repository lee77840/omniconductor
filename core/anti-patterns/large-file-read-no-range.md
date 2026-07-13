---
anti_pattern_id: large-file-read-no-range
name: "Whole-file Read on large files — no offset / limit"
type: anti-pattern
severity: HIGH
hit_rate_impact: "indirect: cache-write inflation, output-token spike"
detection_method:
  - measure-tokens (cache-write tokens / session > 30M)
  - session JSONL inspection (Read tool calls without offset/limit on files > 200 lines)
applies_to: ["all-tools-with-file-Read"]
linked_rules:
  - meta-discipline (5.1 read discipline)
  - reference: token-economy Read rule
---

# Anti-Pattern 02 — Large-file Read without range

## 1. What it is

The orchestrator (or a role agent) calls `Read` on a multi-hundred-line file without `offset` / `limit` parameters, pulling the entire file into context when only a small section is relevant.

```
# WRONG — pulls 2K+ lines into context to find one constant
Read(file_path="<web-app>/lib/i18n/translations.ts")  # 2,400 lines

# WRONG — re-Read the same large file in a later turn for a different key
Read(file_path="<web-app>/lib/i18n/translations.ts")  # again

# WRONG — scanning a long config to confirm a single value exists
Read(file_path=".env.example")  # 180 lines, then again, then again
```

A single 2K-line Read can dump 20K-40K tokens into the context. Across a session of 50 such Reads, that is 1-2M tokens of cache-write churn.

## 2. Why it kills cache

The file content itself enters the conversation history. Once it is in the history, it sits inside the cache prefix for subsequent turns until the conversation rolls over. This means:

- **Cache-write inflation**: every Read multiplies the size of the per-turn cacheable suffix.
- **Hidden-skill amplifier**: certain paths auto-inject companion skills (next-cache-components, react-best-practices, framework docs) — 200-600 tokens hidden cost per Read. See `meta-discipline.md` §5.2.
- **Output-token spike**: when the model summarizes or quotes the file, output cost rises proportionally to file size.

Cost estimate (Anthropic pricing reference):
- 50 full-file Reads × 30K tokens = 1.5M tokens of context bloat
- The repeated response tokens about that file can dominate session cost and context, regardless of provider pricing.

**Reference-adopter P1.5 measurement**: average tool calls per turn = 0.61. The two largest sessions had 7K-8K tool calls. If even 10% were full-file Reads on files > 500 lines, that is the root cause of multi-MB session JSONLs.

## 3. Detection

**Session-level**:
```bash
# Find Read tool calls without offset/limit on files known to be > 200 lines
grep -E '"name":"Read".*"file_path":"[^"]+\.(ts|tsx|md|sql|json)"' \
  ~/.claude/projects/<project>/<session>.jsonl | \
  grep -v '"offset"' | wc -l
```

**Symptom**: cache-write tokens / session climb over 30M (Conductor baseline avg = 27.4M; sessions over that ceiling often have a Read-discipline gap).

**Self-check (LLM)**: before any Read, ask "do I need 50+ contiguous lines, or am I after one symbol?" If the latter, Grep wins.

## 4. Fix / Alternative

**Two-step pattern: Grep first, then range-Read** (per `meta-discipline.md` §5.1):

```
# RIGHT
Grep(pattern="MAX_RETRIES", path="<web-app>/lib/", output_mode="content", -n=true, -C=3)

# Then, only if Grep showed the symbol exists and you need surrounding context:
Read(file_path="<web-app>/lib/config.ts", offset=120, limit=50)
```

**Range-read defaults**:
- For files > 200 lines: `offset` + `limit: 100` is mandatory.
- Read more only if the first range proved insufficient.

**Reference project pattern**: the originating workspace's `token-economy.md` rule explicitly forbids `cat` on a whole spec/CLAUDE.md/translations file. The framework version of that rule lives in `core/universal-rules/meta-discipline.md` §5.1.

## 5. Severity rating

**HIGH** — the largest single contributor to context bloat in production sessions. Combined with auto-injected skills (Anti-Pattern 07), a single careless Read can cost 1K+ tokens.

| Pattern | Per-Read token cost | Per-session impact |
|---|---|---|
| Grep first, no Read needed | ~50 (Grep result) | minimal |
| Range Read (limit=100) | ~1.5K | acceptable |
| Full file Read on 500-line file | ~6K + auto-inject 600 | bloat |
| Full file Read on 2K-line file | ~25K + auto-inject 600 | severe |
