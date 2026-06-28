---
name: warn-stop-commit-without-current-work
enabled: true
event: stop
conditions:
  - field: transcript
    operator: regex_match
    pattern: git\s+commit\s+-m
  - field: transcript
    operator: not_contains
    pattern: docs/CURRENT_WORK.md
---

⚠️ **Session has commits but `docs/CURRENT_WORK.md` was never touched**

The session transcript contains `git commit -m` evidence but no edits to `docs/CURRENT_WORK.md`. Per `core/universal-rules/spec-as-you-go.md` §3 (same-turn docs sync), every commit producing a behavior or content change requires a corresponding `docs/CURRENT_WORK.md` `+N` entry in the same turn.

### Process before Stop

1. **`docs/CURRENT_WORK.md`** — append `+N` entry:
   - Date.
   - Change summary (1-2 sentences).
   - Commit sha.
   - Affected scope (which area / module).
   - Follow-up actions (if any).
2. **`docs/REMAINING_TASKS.md`** — flip affected task IDs to ✅ or update status.
3. **`docs/specs/<area>.md`** — frontmatter `last-updated` + body sections (per `core/universal-rules/spec-as-you-go.md` §1).
4. **`docs/plans/<plan>.plan.md`** (if applicable) — frontmatter status flip.
5. **`docs/runbooks/<runbook>.md`** (if applicable) — close checklist items.

### Exceptions (rule does not apply cleanly)

- **Pure auto-generated commits** (lockfile-only, codegen-only) — body content has nothing CURRENT_WORK could meaningfully record.
- **Pure config-rotation commits** (e.g., dotfile housekeeping) — narrow exception; usually still merits a brief CURRENT_WORK note.

Most ordinary feature / fix / refactor / docs commits warrant a CURRENT_WORK `+N` entry.

### Anti-evasion

- "I'll update CURRENT_WORK next turn" — next turn is not guaranteed (session may end / model may be replaced). Update in the same turn.
- "Too small to log" — every commit appears in `git log` and gets searched. CURRENT_WORK is the first stop for that search; tiny commits are exactly the ones that benefit from a one-line entry.

### Origin

Repeated production pattern: PR merged, no CURRENT_WORK update, next session starts with stale context, agent re-investigates already-completed work. Promoted to ABSOLUTE same-turn rule.

**Warn-only — operation proceeds. The reminder is the value; bypassing it costs the next session.**
