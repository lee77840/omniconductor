---
anti_pattern_id: single-monolithic-rule-file
name: "Monolithic rule file — every rule in one auto-loaded document"
type: anti-pattern
severity: HIGH
hit_rate_impact: "direct cache-write bloat; -20% effective hit benefit"
detection_method:
  - measure CLAUDE.md (or equivalent) line count — > 500 lines is suspect
  - check for `paths:` / `globs:` / `applyTo:` frontmatter usage
applies_to: ["all-tools"]
linked_rules:
  - meta-discipline (5.6 touched-file rule scoping)
---

# Anti-Pattern 03 — Single monolithic rule file

## 1. What it is

The project loads a single oversized rule file at session start — coding conventions, branch strategy, deployment notes, troubleshooting matrix, document map, full feature specs, all bundled in one document — instead of splitting into path-scoped bundles that load only when relevant files are touched.

```markdown
# WRONG — 1,800-line CLAUDE.md auto-loaded every session
# Includes:
#  - Workflow rules (relevant always)
#  - Payment-provider webhook setup (relevant only when touching billing/)
#  - Email templates (relevant only when touching email/)
#  - Database migration log (relevant only when touching db/)
#  - Bank-aggregator integration notes (relevant only when touching that area/)
#  - Post-mortems from 6 months ago
```

Every turn carries the entire payload — including 1,400 lines that have nothing to do with the current task.

## 2. Why it kills cache

The file IS cacheable, so cache hit rate stays high. The damage is on a different axis: **cache-write inflation**.

- Every session start writes the full prefix. Cache-write costs 1.25× input.
- If the prefix is 25K tokens (mostly irrelevant), every new session pays 31K-token cache-write before any work begins.
- The per-turn cache-read cost stays 0.1×, but the absolute number of read tokens scales with prefix size, so total cost still climbs linearly with prefix bloat.

Conductor's P1.5 baseline shows avg cache-write per session = 27.4M tokens. The P2 target is -30% (to ~19M) — most of that reduction comes from splitting the monolithic file.

## 3. Detection

```bash
# Find oversized rule files
wc -l CLAUDE.md AGENT.md GEMINI.md .codex/codex.md 2>/dev/null | \
  awk '$1 > 500 { print }'
```

**Code-level signal**: grep for `paths:` / `globs:` / `applyTo:` frontmatter inside rule files. Zero matches across the rules dir = monolithic anti-pattern.

```bash
grep -lE '^paths:|^globs:|^applyTo:' .claude/rules/*.md .cursor/rules/*.mdc 2>/dev/null | wc -l
```

**Session-level signal**: same uncached input + cache-write delta across a session of unrelated tasks (e.g., billing work and i18n work both pull the whole rule body).

## 4. Fix / Alternative

**Split by domain + scope by path** (per `meta-discipline.md` §5.6).

The reference project keeps a thin top-level pointer file and 5-7 path-scoped rule files:

```
.claude/rules/
├── workflow.md            (always loaded)
├── spec-as-you-go.md      (always loaded)
├── quality-gates.md       (always loaded)
├── operations.md          (always loaded)
├── meta-discipline.md     (always loaded)
├── coding-conventions.md  (paths: apps/**/*.{ts,tsx})
├── branch-strategy.md     (paths: .git*, ci/**)
├── i18n.md                (paths: **/i18n/**, **/translations.ts)
└── billing.md             (paths: **/stripe/**, **/billing/**)
```

Five always-loaded universal bundles ≈ 6K tokens (Conductor v0.2 reference figure). Path-scoped bundles only contribute when the touched-file glob matches.

**Tool-specific frontmatter**:
- Claude Code: `paths:` (matches Read/Edit/Write target)
- Cursor: `globs:` in `.mdc`
- Copilot: `applyTo:` in `.instructions.md`
- Gemini / Codex: no native scoping → keep per-domain files small and link them by reference inside the main rule doc.

**The "5-bundle floor"**: per Conductor `core/universal-rules/README.md`, the minimum auto-load is 5 universal-rule files totaling ~6K tokens. Anything beyond that should be path-scoped or recipe-installed (opt-in).

## 5. Severity rating

**HIGH** — directly multiplies every other cost. A 30K monolithic prefix turns every per-turn cache-read into 3K tokens billed (vs 600 for a 6K floor).

| Rule strategy | Auto-load size | Per-100-turn cache-read |
|---|---|---|
| Monolithic single file | 25-30K | 250-300K tokens |
| 5-bundle floor + path-scoped | 6K | 60K tokens |
| Recipe opt-in only when touched | varies | adds 1-3K per matching turn |

The 5-bundle + scoped recipe strategy delivers ~80% reduction in steady-state cache-read cost.
