---
recipe_id: branch-strategy
recipe_name: "3-branch deploy model (main / develop / release)"
applies_when: "project wants a 3-branch deploy model with auto-deploy environments"
severity: STRONG (when installed)
linked_rules:
  - operations
  - quality-gates
---

# Recipe — Branch Strategy (3-branch model)

> Opt-in recipe. Install when the project wants a 3-branch model (or the example pattern). Adopters with their own strategy (trunk-based, GitFlow, etc.) ignore this recipe; the universal `operations.md` rules still apply.

## 1. Branch roles

| Branch | Role | Auto-deploys to |
|---|---|---|
| `main` | Source of truth — last successful release snapshot. NO auto-deploy. | None |
| `develop` | Integration / dev environment. Auto-deploy. | dev environment (e.g., `<project>-dev` on your hosting provider + dev DB) |
| `release` | Pre-prod / staging. Auto-deploy. | prod environment (e.g., `<project>-prod` on your hosting provider + prod DB) |

The originating project uses this model; the names (`main` / `develop` / `release`) are the reference. Adopters with `main` / `staging` / `production` semantics map equivalently.

## 2. New work flow

```
main → branch off → feature/<name> (or fix/<name>, chore/<name>)
     → PR to develop → CI green + review → merge develop
     → PR to release → prod verification → merge release
     → PR release → main → merge main
```

Each step has a quality gate:

| Step | Gate |
|---|---|
| `feature/*` → `develop` PR | Q1 pre-commit + Q2 pre-merge + CI green |
| `develop` → `release` PR | dev verification confirmed + Q2 |
| `release` → `main` PR | prod verification confirmed (smoke tests) |

## 3. Hotfix flow

```
main → branch off → hotfix/<name>
     → PR to release → emergency review → merge
     → cherry-pick to develop (sync)
     → PR release → main
```

Hotfixes skip the develop integration step because the urgency demands it. The cherry-pick to develop ensures the fix is not lost when develop next merges into release.

## 4. Push policy

| Branch | Direct push | PR required | Force push |
|---|---|---|---|
| `main` | FORBIDDEN | Required | FORBIDDEN |
| `release` | FORBIDDEN | Required | FORBIDDEN |
| `develop` | Allowed for orchestrator (with review) | Strongly preferred | FORBIDDEN |
| `feature/*`, `fix/*`, `chore/*`, `hotfix/*` | Allowed | Required to land | Allowed locally |

GitHub branch protection (or equivalent) enforces the FORBIDDEN rows. Force push is FORBIDDEN on every protected branch — even by admins, without a documented exception.

## 5. PR review (Q2 cross-link)

Every code PR to `develop`, `release`, or `main` requires Q2 pre-merge code review per `quality-gates.md`. Docs-only PRs are exempt.

The orchestrator runs the slash command (Claude Code) or its equivalent on PR open. The Stop-hook (Claude Code) reminds if the orchestrator forgets.

## 6. Push timing

> Adopters CHOOSE this convention. It is not universal.

The originating project's push timing convention:

- Code commits: push immediately (CI runs, deploy triggers).
- Docs-only commits: do NOT push immediately. Batch with the next code push.

### 6.1 Why batch docs

Each push triggers a deploy pipeline. Docs-only pushes consume deploy budget without changing what runs in production. On platforms with deploy quotas (many hosting providers cap free-tier deploys per day), batching docs-only pushes is non-trivial savings.

### 6.2 Exceptions to batch

- Time-critical doc updates (a public-facing doc page must update now).
- Docs that gate other work (CURRENT_WORK.md mid-day update so another session can resume).

## 7. Cross-tool enforcement

| Mechanism | Where |
|---|---|
| Direct-push prevention on protected branches | GitHub branch protection (or platform equivalent) |
| Force-push prevention on protected branches | Branch protection |
| PR review required | Branch protection (require approving review) |
| CI green required | Branch protection (require status checks) |
| Push timing convention | Rule text + orchestrator self-discipline |

## 8. Connection to `operations.md` (universal)

The universal operations rule (`P3` dev/prod sync) assumes a branch model exists. This recipe provides one example. Adopters with different conventions still satisfy P3 by ensuring env-var / migration / external-service parity at deploy time, regardless of branch names.
