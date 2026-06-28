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
| Cursor | ❌ | `.memory/` at project root (gitignored) — DIY |
| Copilot | ❌ | `.memory/` (DIY) |
| Gemini CLI | ❌ | `.memory/` (DIY) |
| Codex | ❌ | `.memory/` (DIY) |
| Windsurf | ❌ | `.memory/` (DIY) |

The pattern is the same. The directory location varies. On non-Claude tools, add `.memory/` to your `.gitignore` so personal memory entries don't leak into the repo.

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

## Tool-specific enforcement

> **Claude-only mechanism**: Claude Code auto-loads `MEMORY.md` at session start (when configured) and surfaces relevant `*.md` files based on the user's question.

> **Other tools**: paste relevant memory entries into your prompt manually, or use the tool's "include this file" feature (Cursor: @-mention; Copilot: workspace context).

## Examples

See `EXAMPLES.md` for tool-agnostic worked examples of each memory type.

## Status (P0 foundation)

`EXAMPLES.md` is a placeholder. P1 fills with sanitized real examples derived from the reference adopter.
