# `core/universal-rules/` — The 5 universal rules

Tool-agnostic rule text that every CONDUCTOR-installed project inherits, regardless of which AI coding tool drives it.

## The 5 bundles

Per ADR-009 (`docs/DESIGN-DECISIONS.md`), the 17+ ABSOLUTE rules from production use are grouped into 5 bundles. Each file is self-contained and cross-references the others where rules overlap.

| File | Bundles | Severity | Always-loaded? |
|---|---|---|---|
| `workflow.md` | W1 plan-first, W2 docs-first, W4 7-step, W5 process-over-speed, W6 absolute-never-skip | ABSOLUTE | YES |
| `spec-as-you-go.md` | W3 same-turn spec, O1 real-time docs sync | ABSOLUTE | YES |
| `quality-gates.md` | Q1 pre-commit review, Q2 pre-merge review, Q3 test sync, Q4 verify-after-changes | ABSOLUTE | YES |
| `operations.md` | O2 session continuity, O3 completed-task delete, P3 dev/prod sync | ABSOLUTE | YES |
| `meta-discipline.md` | M1 originality, ambiguity (AMB-1..7), M2 token economy, M3 model routing, M5 flat-with-leader | ABSOLUTE | YES |

The 5 bundles together are the universal floor. Project-specific concerns (web↔mobile parity, i18n, monorepo, branch-strategy specifics, auto-mock-data, coding-conventions specifics) live in `core/recipes/` as opt-in.

## Frontmatter convention

```yaml
---
rule_id: workflow
rule_name: "Plan-first, docs-first, process-first"
severity: ABSOLUTE
applies_to: ["all-tools"]
violation_count: 6+
enforcement:
  - hook: stop-session-log-check
  - llm-self-discipline
linked_rules:
  - spec-as-you-go
  - meta-discipline
---
```

The `enforcement` list is informational — the actual hook installation happens in `core/hooks/*.template`, compiled by `adapters/<tool>/transform.sh` only on tools that natively support hooks (Claude Code as of v0.2). On other tools, `llm-self-discipline` is the only enforcement.

## Tool-specific callouts inside rule bodies

When a rule cites a tool-only mechanism, fence it explicitly:

```markdown
> **Claude-only mechanism**: `stop-session-log-check` Stop hook blocks session-end if CURRENT_WORK.md is stale.
> Other tools: this rule's text serves as the reminder. Operator self-checks at session end.
```

Adapters do not strip these callouts. The honest acknowledgment of degraded enforcement is part of the framework promise.

## How adapters consume these files

| Adapter | Output |
|---|---|
| Claude | One file per bundle under `.claude/rules/` with `paths:` frontmatter. Universal bundles also referenced from `CLAUDE.md`. |
| Cursor | One `.mdc` per bundle under `.cursor/rules/` (`alwaysApply: true`; recipes get `globs:`). Optional legacy `.cursorrules` bundle via `--legacy-cursorrules`. |
| Copilot | All bundles merged into `.github/copilot-instructions.md` (default) or one `.instructions.md` per bundle under `.github/instructions/` with `--per-rule`. |
| Gemini | All bundles concatenated into `GEMINI.md`, sectioned. |
| Codex | All bundles concatenated into `AGENTS.md` (project root). |
| Windsurf | One file per bundle under `.devin/rules/` (legacy `.windsurf/rules/` still read). |

See `adapters/<tool>/transform-spec.md` for the exact transformation per adapter.

## Cross-reference map

Each bundle cross-links to others where rules overlap. Quick map:

- `workflow.md` W6 (absolute-never-skip) ↔ `meta-discipline.md` section 4 (restated for visibility).
- `workflow.md` W3 (spec-as-you-go reference) ↔ `spec-as-you-go.md` (full rule).
- `quality-gates.md` Q3 (test coverage sync) ↔ `spec-as-you-go.md` section 5 (sibling rule).
- `operations.md` (branch strategy mention) ↔ `recipes/branch-strategy.md` (opt-in details).
- `meta-discipline.md` (ambiguity AMB triggers) ↔ `workflow.md` W5 (process-over-speed).
