# `core/memory-pattern/` — 4-type memory pattern (universal)

CONDUCTOR's memory pattern. Tool-agnostic in *intent*; tool-native in *mechanism*.

## The 4 types

| Type | When to save | Example |
|---|---|---|
| **user** | Learn role, preferences, knowledge level | "Senior Go dev, new to React" |
| **feedback** | User corrects OR validates an approach | "Don't mock the DB in integration tests — burned by mock/prod divergence" |
| **project** | Who's doing what, why, by when (convert relative dates to absolute) | "Merge freeze begins 2026-03-05 for mobile release" |
| **reference** | Where info lives in external systems | "Pipeline bugs tracked in Linear project INGEST" |

## What NOT to save

- Code patterns / conventions / file paths (read the code).
- Git history (use `git log`).
- Debugging fix recipes (the fix is in the commit).
- Anything in CLAUDE.md / `.cursorrules` / equivalent (those rules are universal).
- Ephemeral state (use TaskCreate or `docs/CURRENT_WORK.md` instead).

## Where memory lives — per tool

| Tool | Built-in directory? | Recommended path |
|---|---|---|
| Claude Code | ✅ | `~/.claude/projects/<encoded-project-path>/memory/` |
| Cursor | ⚠️ current native status unverified | `.memory/` at project root (gitignored) as the portable fallback |
| Copilot | ✅ provider-managed preview | Copilot Memory; optional gitignored `.memory/` export for portable files |
| Gemini CLI | ⚠️ hierarchical context + experimental Auto Memory | `.memory/` fallback; do not assume the removed `save_memory` mechanism |
| Codex | ✅ opt-in | `~/.codex/memories/` |
| Windsurf / Devin Desktop | ✅ | `~/.codeium/windsurf/memories/` |

The four semantic types are the same; persistence, expiry, and file ownership vary
by product. When using the portable `.memory/` fallback, add it to `.gitignore` so
personal entries do not leak into the repository.

## File structure

Inside the memory directory:

```
memory/
├── MEMORY.md              # Index (always loaded into context, ≤ 200 lines)
├── user_*.md              # User profile, preferences, role, knowledge
├── feedback_*.md          # Corrections + validated approaches
├── project_*.md           # Ongoing work, goals, deadlines
└── reference_*.md         # Pointers to external systems
```

## How to save

1. Write content to its own file with frontmatter:

```markdown
---
name: short-name
description: one-line for relevance matching
type: user|feedback|project|reference
---

Body. For feedback/project: lead with rule, then **Why:** and **How to apply:** lines.
```

2. Add one-line pointer to `MEMORY.md`: `- [Title](file.md) — one-line hook`

## Lessons (Reflector-produced feedback)

Lessons distilled by the `reflector` role are a specialization of the `feedback`
type. File name: `feedback_lesson-<slug>.md`. They carry the standard three keys
plus reflector bookkeeping keys:

```markdown
---
name: lesson-<slug>
description: one-line for relevance matching
type: feedback
id: lesson-<slug>          # stable id for delta ops
added: <YYYY-MM-DD>
source: <session-id | commit | retro-line>   # provenance (required)
hits: 1                    # times reinforced
last_used: <YYYY-MM-DD>
status: active             # active | stale | merged
confidence: medium         # low | medium | high
---

<the lesson, one paragraph>

**Why:** <why this matters>
**How to apply:** <the concrete change to make next time>
```

Delta operations (applied by a human, or by the orchestrator on explicit GO):
- `ADD` — new `feedback_lesson-*.md`.
- `UPDATE` — bump `hits`, raise `confidence`, or refine wording of an existing lesson.
- `STALE` — set `status: stale`; keep the file, drop its `MEMORY.md` index line.

Proposals are staged (not applied) in `docs/REFLECTION-PROPOSALS.md`. The
deterministic prune script (`.conductor/reflect/prune-lessons.sh`) keeps the
active set bounded: it marks decayed and dead-path lessons `status: stale`
(non-destructive) and removes only exact byte-duplicate files.

## Anti-staleness

Before recommending FROM memory, verify it's still true:
- File path mentioned? Check it exists (`ls`, `Glob`).
- Function/flag mentioned? `Grep` for it.
- Recent activity claim? Prefer `git log` over recalling.

"The memory says X exists" ≠ "X exists now."

## Relationship to in-repo `docs/`

| | `docs/` (in repo) | memory/ (per-user) |
|---|---|---|
| Travels with code | YES | NO |
| Shared with collaborators | YES | NO |
| Persists for the user | (if not deleted) | YES, across sessions/branches/clones |
| Contains personal taste | NO (project conventions only) | YES |
| Contains feedback history | NO | YES |

The two are complementary. `docs/` is the project's brain; memory is YOUR brain on top of the project.

## Tool-specific loading

- **Claude Code** loads its configured project memory index and retrieves relevant
  files.
- **Copilot, Codex, and Windsurf** provide native managed-memory mechanisms, but
  their storage, expiry, and opt-in policies differ; use the product-native control
  and do not represent server-managed memory as a repository file.
- **Cursor and Gemini CLI** retain the gitignored `.memory/` fallback unless the
  project's currently installed version documents and enables a native equivalent.
- On every tool, verify a remembered claim against the repository before acting.

## Examples

See `EXAMPLES.md` for tool-agnostic worked examples of each memory type.

`EXAMPLES.md` contains tool-neutral examples for the four memory types.
