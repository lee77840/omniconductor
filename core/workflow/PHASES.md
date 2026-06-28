# PHASES — detailed entry/exit criteria per workflow phase

> **Status (P0 foundation): PLACEHOLDER.** This file describes intent and structure. P1 fills each phase section with concrete content sanitized from the reference adopter.

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

**Owner**: orchestrator (Claude main session) or human (other tools).

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

**Owner**: strategist agent (Claude) or human (other tools).

**Inputs**: `.plan.md`.

**Outputs**: ADR(s) under `docs/architecture/`; updated system diagram.

**Entry / exit / anti-patterns**: P1 fill.

---

## 3. TASKS

**Trigger**: plan approved (medium+) OR direct request (simple).

**Owner**: orchestrator (Claude) or human.

**Inputs**: `.plan.md` (medium+) or request alone (simple).

**Outputs**: enumerated task list with: objective, file paths, constraints (`must_do`, `must_not_do`), output paths, stop condition.

**Entry / exit / anti-patterns**: P1 fill.

---

## 4. IMPLEMENTATION

**Trigger**: tasks ready.

**Owner**: builder / helper / designer / mailer / translator / scribe agent (Claude) or human.

**Inputs**: task list.

**Outputs**: code + e2e test updates per task.

**Entry / exit / anti-patterns**: P1 fill (will include "one task per agent", "no general-purpose agent", "model override per R2").

---

## 5. REVIEW

**Trigger**: implementation task complete.

**Owner**:
- Stage A: code-reviewer agent (Claude) or human (other tools).
- Stage B: `/code-review` slash command (Claude + Cursor partial) or human (other tools).

**Inputs**: git diff (Stage A) or open PR (Stage B).

**Outputs**: reviewer report; either pass-through or block-on-issues.

**Entry / exit / anti-patterns**: P1 fill (will include "block on HIGH-confidence ≥75 issues", "specialized reviewer agents per change kind").

---

## 6. SPEC

**Trigger**: implementation merged.

**Owner**: scribe agent (Claude) or human.

**Inputs**: shipped code; existing `docs/specs/<area>.md`.

**Outputs**: updated spec reflecting actual shipped behavior.

**Entry / exit / anti-patterns**: P1 fill (will include "spec-as-you-go ABSOLUTE", "Stop hook enforcement on Claude", "rule reminder on others").

---

## Phase scaling reminder

| Scope | Phases entered | Notes |
|---|---|---|
| Trivial | 4, 5, 6 | Skip Plan + Architecture + Tasks. |
| Simple | 3, 4, 5, 6 | Skip Plan + Architecture. |
| Medium | 1, 3, 4, 5, 6 | Skip Architecture. |
| Large | 1, 2, 3, 4, 5, 6 | Full ceremony. |

## Tool-agnostic enforcement reminder

Workflow definition is universal. Enforcement degrades:

- **Claude Code**: Stop hooks can block phase-skipping at commit time (e.g., no `.plan.md` for medium+ → blocked).
- **Cursor / Copilot / Gemini / Codex / Windsurf**: rule text reminds. Self-policed.

See `docs/COMPATIBILITY-MATRIX.md` for the per-tool enforcement column.
