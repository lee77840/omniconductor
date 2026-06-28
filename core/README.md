# `core/` — Layer 1, Universal source-of-truth

Anything in this directory MUST work for every supported tool. No tool-specific syntax, no `.claude/` references, no Cursor `.mdc` directives, no Copilot `applyTo:` annotations.

## What lives here

| Subdirectory | Purpose |
|---|---|
| `workflow/` | The Plan → Architecture → Tasks → Implementation → Review → Spec phase definitions. Tool-agnostic phase boundaries. |
| `universal-rules/` | The 5 universal rules (operations, coding-conventions, token-economy, spec-as-you-go, model-routing). Each is plain markdown. |
| `docs-templates/` | The doc skeletons every project gets (`CURRENT_WORK.md`, `REMAINING_TASKS.md`, `PLANS.md`, `TASKS.md`, `INDEX.md`, `specs/_example.md`). |
| `memory-pattern/` | Documentation of the 4-type memory pattern (user / feedback / project / reference). NOT actual memory data. |

## Authoring conventions

### Plain markdown only

ATX headings, tables for comparisons, fenced code blocks with language hint. No HTML. No tool-specific syntax.

### Front-matter is OPTIONAL and routing-only

If a rule needs adapter routing hints (e.g., "this rule applies only to TypeScript files"), use minimal YAML front-matter that adapters can transform:

```markdown
---
applies_to:
  - "**/*.ts"
  - "**/*.tsx"
tier: T1   # informational; how prominent in always-loaded baseline
---

# Rule body in plain markdown
```

Adapters translate `applies_to:` to:
- Claude: `paths:` in the rule's front-matter
- Cursor: `globs:` in `.mdc`
- Copilot: `applyTo:` in `.instructions.md`
- Gemini / Codex / Windsurf: bundled (no per-pattern routing)

### No tool-specific examples

If you cite an example, make it generic. ❌ "use `Agent` tool to dispatch". ✅ "delegate to a specialized agent persona".

If a rule HAS to reference a Claude-only mechanism, put the example under a clearly-labeled tool-native callout that adapters can show or hide:

```markdown
> **Claude-only mechanism**: enforced via Stop hook (`stop-session-log-check.sh`).
> Other tools: rely on rule reminder + manual discipline.
```

## Status (P0 foundation)

All files in subdirectories are PLACEHOLDERS describing intent. P1 fills them with real content sanitized from the reference adopter.

## Adapter contract (referenced, not implemented here)

Each adapter MUST:
- Read every file under `core/`.
- Translate front-matter to the target tool's format.
- Emit at the conventional path for that tool (see `docs/HOW-IT-WORKS-PER-TOOL.md`).
- Never modify files in `core/`.

See `adapters/README.md` for the full adapter contract.
