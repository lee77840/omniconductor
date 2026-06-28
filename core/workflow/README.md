# `core/workflow/` — Universal workflow definition

The Plan → Architecture → Tasks → Implementation → Review → Spec workflow that every CONDUCTOR project follows, regardless of which AI coding tool drives it.

## The 6 phases

```
Request
   ↓
1. PLAN              — clarify intent + write .plan.md (medium+ scope only)
   ↓
2. ARCHITECTURE      — system-level shape, ADRs, contracts (large scope only)
   ↓
3. TASKS             — break plan into discrete tasks with file paths + stop conditions
   ↓
4. IMPLEMENTATION    — execute one task at a time, delegated when possible
   ↓
5. REVIEW            — Stage A pre-commit + Stage B pre-merge PR
   ↓
6. SPEC              — update docs/specs/* to reflect what shipped
```

## Phase scaling by scope

Not every change goes through all 6 phases. Scale the workflow to scope:

| Scope | Files | Phases entered | Review checkpoint |
|---|---|---|---|
| Trivial | 1 | 4, 5, 6 | None |
| Simple | 1-2 | 3, 4, 5, 6 | None |
| Medium | 3-10 | 1, 3, 4, 5, 6 | Plan → Implement → Review |
| Large | 10+ | 1, 2, 3, 4, 5, 6 | Architecture → Plan → Implement → Review |

## What lives here

- `PHASES.md` — detailed entry/exit criteria per phase. (P1: filled with full content derived from the reference adopter's workflow.)
- (future) `templates/` — phase output templates (`.plan.md` skeleton, ADR skeleton).

## Tool-agnostic enforcement

The workflow itself is tool-agnostic. Enforcement varies:

- **Claude Code**: Stop hook can verify a `.plan.md` exists for medium+ scope tasks before allowing commits.
- **Cursor / Copilot / Gemini / Codex / Windsurf**: rule text reminds the user; enforcement is self-policed.

Adapter outputs all reference these phase definitions but the *mechanism* of enforcement is per-tool (see `docs/COMPATIBILITY-MATRIX.md`).

## Why 6 phases (not fewer / more)

- Fewer than 6 (collapse Tasks into Implementation) loses the explicit "what files, in what order" artifact that prevents scope creep mid-implementation.
- More than 6 (separate Verification phase, etc.) adds ceremony users will skip.
- The 6 phases match the natural rhythm of a feature, refactor, or bug fix at solo / small-team scale.

## Status (P0 foundation)

`PHASES.md` is a placeholder. P1 fills it with detailed entry/exit criteria, examples, and anti-patterns to avoid per phase.
