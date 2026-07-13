# CURRENT WORK — `<your-project>`

> **What this is**: session continuity log. Updated EVERY session. Read FIRST every session start.
> Lean (~150 lines). When it grows past, archive older sessions to `docs/sessions/<date>.md`.

> **Status (P0 placeholder)**: replace this entire file with your project's first entry on first install. P1 will provide a more developed starter template.

---

## Session log

### 2026-MM-DD — Session N

**In progress**:
- (current task with file paths)

**Just completed**:
- (last task shipped)

**Issues / blockers**:
- (anything stuck)

**Next session should start with**:
- (concrete first action)

---

### Template for new entries

Copy and paste at the top of the section above:

```
### YYYY-MM-DD — Session NN

**In progress**:
- ...

**Just completed**:
- ...

**Issues / blockers**:
- ...

**Next session should start with**:
- ...
```

---

## Project-level state (persistent across sessions)

> Things that don't change every session but that any session needs to know.

- **task_id**: `<stable task/issue id>`
- **active_branch**: `<git branch name>`
- **base_sha**: `<task starting commit; must remain an ancestor of HEAD>`
- **last_verified_head**: `<HEAD verified at the latest session checkpoint>`
- **Current phase**: (e.g., "P3 — Implementation")
- **Active feature flags**: (e.g., `IAP_ENABLED=false`, `AI_GATEWAY_ENABLED=true`)
- **Known blockers**: (e.g., "payment-provider live activation pending business registration approval")
- **Reference docs**: (links to `docs/PLANS.md`, `docs/REMAINING_TASKS.md`, `docs/specs/`)

---

## Session continuity rule

CRITICAL: maintain CURRENT_WORK.md with in-progress tasks, issues, next steps for instant session resume. Never end a session without updating this file.

When the repository is under Git, keep `active_branch`, `base_sha`, and
`last_verified_head` synchronized with the real worktree. `omniconductor doctor`
checks populated values and reports drift; placeholder values are allowed only
until the first real task is recorded.
