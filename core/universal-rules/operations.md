---
rule_id: operations
rule_name: "Session continuity, completed-task delete, dev/prod sync"
severity: ABSOLUTE
applies_to: ["all-tools"]
violation_count: 4+
enforcement:
  - hook: stop-session-log-check
  - llm-self-discipline
linked_rules:
  - workflow
  - spec-as-you-go
---

# Operations — Session Continuity + Sync Hygiene

> Bundles O2 (session continuity / CURRENT_WORK first-read), O3 (completed-task delete), P3 (dev/prod sync). These rules govern how the project state is communicated across sessions and across environments.

## 1. Session Continuity (O2)

### 1.1 First-read on every session start

The first file the orchestrator reads on every new session is `docs/CURRENT_WORK.md`. No exceptions. Even if the user's request is unrelated to active work, CURRENT_WORK.md is read first to establish context.

### 1.2 Why

CURRENT_WORK.md is the project's single source of "what is happening right now". Without it:
- Orchestrator duplicates work that another session already finished.
- Orchestrator pushes code that conflicts with in-progress work elsewhere.
- The user re-explains everything every session.

With it:
- New session starts with full context in ~150 lines (the file's enforced size cap).
- In-progress / blocked / done states are visible.
- Next-step is explicit.

### 1.3 What CURRENT_WORK.md contains

Required sections (in order):

1. **Current state** (date, phase, last commit hash, version).
2. **Immediate next action** — what the next session should do.
3. **In progress** — task list with owner + status + last update timestamp.
4. **Recently completed** — last 3-5 deliverables (with commit refs). Older entries archive.
5. **Known issues / blockers** — anything that prevents next-action.
6. **Decision log** (optional) — recent ADR-style decisions for fast catch-up.

### 1.4 Size cap and archive

CURRENT_WORK.md MUST stay under 200 lines (target: 150). When it exceeds 200:

- Archive the bottom half into `docs/sessions/<YYYY-MM-DD>.md`.
- Leave only the most-recent 5-10 entries in CURRENT_WORK.md.
- The session archive is a permanent reference but no longer auto-loaded.

### 1.5 Stop-hook (Claude and Codex)

`stop-session-log-check` is installed by the Claude and Codex adapters using each
tool's verified Stop-hook dialect. It rejects session completion if:

- Recent commits exist (≥ 1 in the last 30 minutes), AND
- CURRENT_WORK.md was not modified in the last 30 minutes.

The hook emits a reason; the orchestrator updates CURRENT_WORK.md and proceeds.
Cursor, Copilot, Gemini, and Windsurf use this rule's completion checklist because
CONDUCTOR does not emit an unverified equivalent guard for them.

---

## 2. Completed-Task Delete (O3)

When a task in CURRENT_WORK.md, REMAINING_TASKS.md, or TASKS.md transitions to `completed`, it MUST be removed from the active list within the next session boundary.

### 2.1 What "next session boundary" means

- If task completes mid-session: mark `completed` immediately, then DELETE before declaring the turn done.
- If task completes at session end: mark `completed`, then on the next session resume, the orchestrator deletes it as part of the first-read checklist.

### 2.2 Why delete (not retain)

Active task lists with completed items become unreadable. The completed item history lives in:
- Git commit log (the actual durable record).
- Session archive (`docs/sessions/<date>.md`).
- "Recently completed" section of CURRENT_WORK.md (last 3-5 only).

Retaining all completed items in the active list defeats the file's purpose.

### 2.3 Exceptions

- Completed milestones with cross-cutting impact may stay in CURRENT_WORK.md "Recently completed" for one session before archiving.
- Items that surface a new follow-up task: delete the old, add the new — do not chain.

### 2.4 Origin

Production case: TASKS.md grew to 400+ lines, with 60% of entries marked `completed` over months. New contributors couldn't find what was actually pending. The corrective rule made `completed` a transient state, not a permanent annotation.

---

## 3. Dev / Prod Sync (P3)

When the project has multiple environments (dev / staging / prod), every feature that works in dev MUST work identically in prod once shipped. This rule applies to:

- Code (auto-handled by deploy pipeline if branch-strategy is followed).
- Database schema (migrations applied to all environments before code that depends on them ships).
- Environment variables (registered in all environments before referencing code is deployed).
- External service configurations (webhooks, OAuth callbacks, API keys per environment).
- Cron / scheduled jobs (if dev runs them, prod runs them too — or both don't).

### 3.1 The "dev works, prod broken" failure mode

The single most common production incident pattern: a feature passes dev verification, ships to prod, fails because the prod environment is missing one or more of:

- A required environment variable (forgot to register in prod dashboard).
- A database migration (applied to dev but not prod).
- A webhook URL update (third-party still pointing to old endpoint).
- A feature flag (default OFF in prod, but on in dev).

This failure mode is preventable by treating "dev / prod parity" as a checklist item before shipping.

### 3.2 Pre-deploy parity checklist

Before merging code to a release branch:

- [ ] All new env vars registered in prod environment (with same names).
- [ ] All new DB migrations applied to prod (or queued in deploy pipeline).
- [ ] All third-party service configs updated for prod URL (webhook URLs especially — note the apex-domain trap below).
- [ ] All feature flags decided for prod (default state explicit).
- [ ] Cron / scheduled jobs registered in prod scheduler.

### 3.3 Common traps

**Trap 1 — Apex vs subdomain in webhook URLs.** Many third-party services do NOT follow HTTP redirects. If your apex domain redirects to `www.` (or vice versa), a webhook registered with the redirecting form silently fails — every event is "delivered" by the third-party but never reaches your handler. Always register webhook URLs with the canonical (non-redirecting) form.

**Trap 2 — Env var registered but not redeployed.** Most platforms require a redeploy after env var registration before the new value is visible to running code. Build artifacts produced before the env was registered will not see it. Always trigger a fresh build after env changes.

**Trap 3 — Migration applied without code, or code without migration.** Either order causes downtime. Apply schema changes that are backward-compatible first, then deploy code, then apply schema cleanups (drop old columns, etc.). When in doubt, dual-write briefly.

### 3.4 When P3 does not apply

If your project is single-environment (no separate prod), this rule is informational only. The rest of the universal-rules still apply.

---

## 4. Branch strategy (informational link)

CONDUCTOR's universal rules don't mandate a specific branch strategy — they assume one exists. The opt-in `recipes/branch-strategy.md` documents a common 3-branch pattern (main / develop / release) used by the originating project. Adopters with their own strategy ignore the recipe; the operations rules above still hold.

---

## 5. Push timing (informational)

The `recipes/branch-strategy.md` recipe also documents a "push timing" convention: docs-only changes are NOT pushed immediately; they batch with the next code push. This avoids polluting deploy pipelines with docs-only triggers. This is a project-specific preference, not a universal rule. Adopters choose.

---

## 6. Cross-tool enforcement

| Mechanism | Tools that enforce automatically |
|---|---|
| `stop-session-log-check` (CURRENT_WORK staleness) | Claude Code, Codex |
| Branch protection (force-push block, PR required) | GitHub branch protection (any tool) |
| Pre-deploy CI checklist | CI pipeline (any tool) |
| Rule text reminder | All tools |

On adapters without this specific guard, the orchestrator self-checks at session
start and session end.
