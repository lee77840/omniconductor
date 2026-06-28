---
rule_id: quality-gates
rule_name: "Pre-commit + pre-merge review + test sync + verify-after-changes"
severity: ABSOLUTE
applies_to: ["all-tools"]
violation_count: 3+
enforcement:
  - hook: stop-r6-review-check
  - llm-self-discipline
  - external: ci-pipeline
linked_rules:
  - workflow
  - spec-as-you-go
---

# Quality Gates — Two-Stage Review + Test Sync + Verify

> Bundles Q1 (pre-commit code review), Q2 (pre-merge code review), Q3 (test coverage sync), Q4 (verify-after-changes). Every code change passes through this gate before being declared done.

## 1. Pre-Commit Code Review (Q1)

Before a code change is committed, an automated reviewer MUST inspect the diff. Block on HIGH-confidence issues (severity ≥ 75 / 100). Lower-severity issues become PR comments.

### 1.1 Reviewer selection (model routing)

| Diff size / nature | Reviewer model |
|---|---|
| Single file, established pattern | Sonnet-tier |
| Multi-file (3+) or cross-cutting | Opus-tier |
| Type-design heavy | Specialized "type-design" reviewer if available |
| Error-handling heavy | Specialized "silent-failure" reviewer if available |

When in doubt, upgrade one tier. The cost difference between Sonnet and Opus reviewer is modest compared to the cost of merging a HIGH-severity bug.

### 1.2 Exemptions (NOT subject to pre-commit review)

- 100% docs-only changes (`docs/**`, `*.md` only).
- Lockfile auto-generated bumps.
- Generated type files (output of codegen tooling).

Mixed PRs (docs + code) are NOT exempt. Any code in the diff triggers review.

### 1.3 What "block on HIGH-confidence" means

If the reviewer reports any issue with confidence ≥ 75 and severity ≥ HIGH:

- Commit MUST NOT proceed.
- Orchestrator addresses the issue (fix code, justify in commit message, or escalate to user).
- Re-run reviewer on the updated diff.
- Only when no HIGH-confidence issues remain: commit.

LOW / MEDIUM issues become commit-message footer notes or follow-up tasks in CURRENT_WORK.md.

---

## 2. Pre-Merge Code Review (Q2)

After commit + push + open PR, a SECOND review pass runs on the open PR before merge. This is distinct from Q1 — Q1 reviews the local diff before commit; Q2 reviews the merged-state PR (including CI signals + reviewer comments).

### 2.1 Trigger

PR opened on a non-direct-push branch (typically anything that is not `main` / `release` / `develop` per the project's branch strategy). See `recipes/branch-strategy.md` for branch naming patterns.

### 2.2 Cool-down (Claude adapter only)

The `stop-r6-review-check` hook (when installed by the Claude adapter) reminds the orchestrator to run pre-merge review at most once per 30 minutes per PR. This avoids reminder spam on rapid push cycles.

### 2.3 Exemptions

Same as Q1 (docs-only, lockfile, generated files). Additionally, PRs that have already passed pre-merge review are not re-reviewed unless new commits are pushed.

### 2.4 Cross-tool degradation

| Tool | Q2 mechanism |
|---|---|
| Claude Code | Slash command (`/code-review`) + Stop-hook reminder |
| Cursor | Cursor command palette + manual rule reminder |
| Copilot | GitHub PR comment review (Copilot Code Review native) + manual reminder |
| Gemini / Codex / Windsurf | Manual reminder via rule text |

---

## 3. Test Coverage Sync (Q3)

Every new feature, changed behavior, or new public API MUST have a corresponding test added or updated in the SAME PR.

### 3.1 What test belongs to what change

| Code change | Test type | Test location pattern |
|---|---|---|
| New page / route | E2E functional | `<test-root>/functional/<area>.spec.*` |
| New API endpoint | E2E functional (auth + response shape) | Same as above |
| New UI screen | Visual smoke | `<test-root>/visual/<area>.spec.*` |
| Existing page UX change | Update existing functional spec (selectors, flow) | Same |
| New service function | Unit test (happy + error path) | `<service>/__tests__/<service>.spec.*` |
| New email template / similar render | Snapshot test | `<template-dir>/__tests__/<template>.spec.*` |

### 3.2 Skip / "incomplete" classification

A PR that adds a new feature without an accompanying test is treated as INCOMPLETE. Pre-commit review (Q1) catches this when the diff contains source changes but no test changes. Pre-merge review (Q2) catches it when CI runs.

### 3.3 The "verify before push" command pair

Before push:

1. Run unit tests (project-specific command, e.g. `npx vitest run`).
2. Run functional E2E (project-specific command, e.g. `npm run test:functional`).

If either is red, the work is not done. The orchestrator does not push and does not declare the task complete.

---

## 4. Verify-After-Changes (Q4)

Every code or configuration change MUST be verified by running the application or relevant subset before reporting "done" to the user.

### 4.1 Verification levels by change type

| Change | Verification |
|---|---|
| Code | Run unit tests + relevant functional E2E + manual sanity (when UI). |
| Build config | Run `build` command, verify no errors. |
| Environment variable | Verify in dev environment (or staging) that the var loads and the dependent path works. |
| Database schema | Apply migration on dev DB, run mock-data seeds, run a query. |
| External service config | Trigger the integration end-to-end (test webhook, send test email, etc.). |

### 4.2 Reporting "done" to the user

The orchestrator MUST NOT say "fixed" / "implemented" / "deployed" without prior verification evidence. Acceptable evidence:

- Test runner output (snippet pasted into the response).
- Build command exit code 0 (with command name).
- HTTP request result (status + relevant body field).
- Screenshot or render snapshot (if UI).
- Database query result.

A response that says "this should fix it" is not a completion report — it's a hypothesis. Mark it as such if you cannot verify.

### 4.3 The "evidence before assertions" principle

Borrowed from disciplined debugging practice: evidence ALWAYS precedes the success claim. The orchestrator that claims success without evidence is treated equivalently to silent rule violation (see workflow.md W6).

### 4.4 Sub-agent completion reports are claims, not evidence

When a sub-agent returns a "done" / "implemented" summary, that summary is a **claim**, not evidence. Before relaying completion to the user, the orchestrator MUST:

1. `git diff` the sub-agent's changes and grep for the specific pattern the task required (the new structure / function / renamed symbol — not just "files changed").
2. Where the change is observable at runtime (UI render, endpoint response, query result), observe it.
3. Only then relay completion, citing the diff + observation.

A green build or a passing test is a precondition for this check, never a substitute for it. See §4.5 below.

### 4.5 Anti-pattern — false completion from a green build

The failure mode §4.3–4.4 exist to prevent: a green build, a passing test suite, or a sub-agent's "done" summary is treated as proof that the *intended* change happened. It is not. A build can be green while the requested change never landed — a token-only edit went in instead of the structural change, the file that mattered was never touched, or a sub-agent edited the wrong surface. **build-green ≠ change-applied.**

**Detection:** a "fixed / implemented / done / deployed" claim whose only cited evidence is build/test status or a sub-agent's prose, with no diff inspection or runtime observation of the intended change.

**Fix:** (1) `git diff` and grep for the *concrete pattern the task required* — the new structure, function, or renamed symbol, not "files changed"; if the grep does not find it, the change was not applied regardless of build status. (2) Observe it at runtime where applicable (render the page, hit the endpoint, run the query). (3) Only then claim completion, citing the diff + observation. On the Claude adapter, the Stop guard `block-completion-claim-without-push` is the mechanical backstop.

---

## 5. Pre-commit checklist (operator-facing)

Before any commit:

- [ ] Type checks pass.
- [ ] No hardcoded secrets / API keys in diff.
- [ ] Approved UI library only (project-specific — see recipe).
- [ ] Service-layer pattern preserved.
- [ ] Result-pattern API responses preserved (where applicable).
- [ ] Row-level-security or equivalent access control assumed by design.
- [ ] Folder structure unchanged (no rogue new top-level directories).
- [ ] Spec(s) updated (`spec-as-you-go.md`).
- [ ] E2E test added / updated (Q3).
- [ ] Naming conventions followed.
- [ ] No duplicated business logic across surfaces (web ↔ mobile, etc.).
- [ ] **Q1 — Pre-commit review passed.**

---

## 6. Cross-tool enforcement summary

| Gate | Claude Code | Cursor | Copilot | Gemini | Codex | Windsurf |
|---|---|---|---|---|---|---|
| Q1 pre-commit review (auto) | Manual invoke + Stop-hook reminder | Manual | GitHub Copilot CR | Manual | Manual | Manual |
| Q2 pre-merge review (auto) | Slash command + Stop-hook | Manual | GitHub native | Manual | Manual | Manual |
| Q3 test coverage sync | Rule text + checklist | Same | Same | Same | Same | Same |
| Q4 verify-after-changes | Rule text + LLM self-discipline | Same | Same | Same | Same | Same |

The honest summary: only Claude Code has a pre-existing automated reminder mechanism. On other tools, the rule text + the operator's discipline carry the weight. CONDUCTOR does not pretend otherwise.
