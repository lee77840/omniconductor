# PHASES — detailed entry/exit criteria per workflow phase

> The phase contract is tool-neutral. Full/strict installs expose all eight roles on
> every supported adapter; the native surface is an agent profile on five tools and
> an invocable workflow on Windsurf.

## How to read this file

For each of the 6 phases (Plan / Architecture / Tasks / Implementation / Review / Spec), the same template:

```
### [Phase name]

**Trigger**: what user request or upstream phase entry produces this phase.
**Owner**: who carries the work (orchestrator / specialized agent persona / human).
**Inputs**: artifacts that MUST exist before entering.
**Outputs**: artifacts produced before exit.
**Entry criteria**: bullet list — all must be true to enter.
**Exit criteria**: bullet list — all must be true to advance.
**Anti-patterns**: things people do wrong; how to recognize and recover.
**Tool-specific notes**: callouts for Claude / Cursor / others where mechanism differs.
```

---

## 1. PLAN

**Trigger**: medium+ scope request.

**Owner**: orchestrator, with human approval where the project requires it.

**Inputs**: user request, prior context (`docs/CURRENT_WORK.md`).

**Outputs**: `.plan.md` describing approach, files affected, risks, stop condition.

**Entry criteria** (P1 fill):
- Request scope assessed (Trivial / Simple / Medium / Large).
- If Trivial / Simple → SKIP this phase, go to Tasks.

**Exit criteria** (P1 fill):
- `.plan.md` exists with ≥ N sections.
- Reviewer-eligible (medium → human ack; large → reviewer agent ack).

**Anti-patterns** (P1 fill).

---

## 2. ARCHITECTURE

**Trigger**: large scope work that affects system-level shape (auth flow, data model, billing).

**Owner**: `planner` role; the orchestrator retains the final decision.

**Inputs**: `.plan.md`.

**Outputs**: ADR(s) under `docs/architecture/`; updated system diagram.

**Entry / exit / anti-patterns**: P1 fill.

---

## 3. TASKS

**Trigger**: plan approved (medium+) OR direct request (simple).

**Owner**: orchestrator.

**Inputs**: `.plan.md` (medium+) or request alone (simple).

**Outputs**: enumerated task list with: objective, file paths, constraints (`must_do`, `must_not_do`), output paths, stop condition.

**Entry / exit / anti-patterns**: P1 fill.

---

## 4. IMPLEMENTATION

**Trigger**: tasks ready.

**Owner**: `builder`, `helper`, `designer`, or `utility` according to the
immutable difficulty and scope rules. Project recipes may add specialist roles.

**Inputs**: task list.

**Outputs**: code + e2e test updates per task.

**Entry / exit / anti-patterns**: one bounded task per role dispatch; no generic
catch-all dispatch; use the project-saved Tier translation without changing the
task's difficulty classification.

---

## 5. REVIEW

**Trigger**: implementation task complete.

**Owner**:
- Stage A: independent `code-reviewer` role on every adapter.
- Stage B: the tool's native review command or PR review surface, with human
  approval where required.

**Inputs**: git diff (Stage A) or open PR (Stage B).

**Outputs**: reviewer report; either pass-through or block-on-issues.

**Entry / exit / anti-patterns**: P1 fill (will include "block on HIGH-confidence ≥75 issues", "specialized reviewer agents per change kind").

---

## 6. SPEC

**Trigger**: implementation merged.

**Owner**: `scribe` role, with the orchestrator verifying code/spec agreement.

**Inputs**: shipped code; existing `docs/specs/<area>.md`.

**Outputs**: updated spec reflecting actual shipped behavior.

**Entry / exit / anti-patterns**: spec-as-you-go is ABSOLUTE. Claude and Codex
install verified Stop reminders; the other adapters enforce the same rule through
their installed instructions and the completion checklist.

---

## Phase scaling reminder

| Scope | Phases entered | Notes |
|---|---|---|
| Trivial | 4, 5, 6 | Skip Plan + Architecture + Tasks. |
| Simple | 3, 4, 5, 6 | Skip Plan + Architecture. |
| Medium | 1, 3, 4, 5, 6 | Skip Architecture. |
| Large | 1, 2, 3, 4, 5, 6 | Full ceremony. |

## Tool-agnostic enforcement reminder

Workflow definition and role topology are universal. Mechanical enforcement varies:

- **Claude Code**: full verified guard-hook set.
- **Codex**: verified `PreToolUse`/`Stop` guard subset.
- **Cursor / Copilot / Gemini / Windsurf**: native role entry points plus installed
  rule text; only lifecycle/recipe hooks with verified contracts are emitted.

See `docs/COMPATIBILITY-MATRIX.md` for the per-tool enforcement column.
