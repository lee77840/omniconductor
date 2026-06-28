---
name: warn-on-gh-pr-merge
enabled: true
event: bash
conditions:
  - field: command
    operator: regex_match
    pattern: \bgh\s+pr\s+merge\b
---

⚠️ **PR merge — 4-spot status flip required (same turn)**

A PR merge command was issued. Per `core/universal-rules/spec-as-you-go.md` §3 and the audit-stale-pattern rule, every merge requires immediate cross-doc status flips in the same turn. Skipping this produces stale documentation that audit dispatches in subsequent sessions waste cycles re-investigating.

### Same-turn 4-spot flip

1. **`docs/REMAINING_TASKS.md`** — flip the corresponding task ID to ✅ (run `grep -n` for stale `⏳` markers tied to the merged work).
2. **`docs/plans/<plan>.plan.md`** — frontmatter `status: APPROVED → SHIPPED`; body's "Out of scope" / "Sprint buffer" / "Deferred" sections updated accordingly.
3. **`docs/runbooks/<runbook>.md`** — close the user-manual checklist items + summary table rows the merge resolves.
4. **`docs/CURRENT_WORK.md`** — append a `+N` entry: PR number, merge sha, one-line summary, follow-up actions.

### Additional checks

- **`docs/audits/<latest>.md`** — close findings the merge resolves (preserve historical dated snapshots).
- **`docs/specs/<area>.md`** — frontmatter `last-updated: YYYY-MM-DD` plus body sections (per `core/universal-rules/spec-as-you-go.md` §1).

### Origin

Production pattern: PR merged, CURRENT_WORK updated, but REMAINING_TASKS / plan frontmatter / runbook checklists left stale for days. Subsequent audit dispatches surfaced the stale items as findings, wasting cycles on already-resolved work.

**Merge is not the end of a task. The 4-spot flip is.**

**Warn-only — operation proceeds. Treat the reminder as a gate before declaring the task done.**
