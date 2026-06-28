---
name: warn-gh-pr-create-without-pre-merge-review
enabled: true
event: bash
conditions:
  - field: command
    operator: regex_match
    pattern: \bgh\s+pr\s+create\b
---

⚠️ **Pre-merge code review (Q2) required before merge**

A PR is being created. Per `core/universal-rules/quality-gates.md` Q2 (pre-merge code review), the PR must pass a structured review BEFORE merge — distinct from Q1 (pre-commit review on the diff).

### Q2 procedure

1. **CI green check**: `gh pr checks <#>` or wait for the GitHub UI to show all checks passing.
2. **Run the pre-merge reviewer** — typically a multi-reviewer parallel pass with a scoring model that aggregates findings.
3. Findings score ≥ 80 → BLOCK_MERGE; fix and re-run review.
4. Findings score 75-79 → judgment call (escalate to human if ambiguous; build-blocker guard violations bump to 80).
5. Findings score ≤ 74 → optional follow-up comment, do not block merge.
6. Approve → merge.

### Exemptions

- 100% `docs/**` or `*.md`-only PRs.
- Auto-generated lockfile updates.
- Auto-generated codegen-only PRs.

### Auto-reminder integration

If your project uses `core/hooks/stop-r6-review-check.sh.template` (installed by the Claude adapter), it injects a reminder on session-stop when push + open PR is detected, with a cool-down to avoid spam.

### Origin

Production pattern: a PR was merged that had passed Q1 pre-commit review but skipped Q2 pre-merge review. Q2 would have caught a build-blocker (i18n score 75) — the orchestrator was explicitly called out for the skip. Promoted Q2 to ABSOLUTE.

**Warn-only — operation proceeds. The PR exists; the responsibility to run Q2 before merge is now on the orchestrator.**
