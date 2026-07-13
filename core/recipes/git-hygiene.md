---
recipe_id: git-hygiene
recipe_name: "Git Hygiene / Shared-Repo Discipline"
applies_when: "any git project — especially repos worked by multiple sessions/agents or with protected branches"
severity: STRONG (when installed)
linked_rules:
  - operations
  - quality-gates
  - meta-discipline
---

# Recipe — Git Hygiene / Shared-Repo Discipline

> Opt-in recipe. Install for any project under git — strongly recommended when more than one session/agent may touch the repo, or when it has protected branches. It codifies the workflow-hygiene habits that stop *completed* work from *looking* lost. Install if you have ever spent time reconciling "where did my feature go" — you likely will again without it.

## Why this exists

Left undisciplined, an agent can turn a healthy repo into one where merged work looks stranded: it spins up `git worktree`s nobody asked for and never cleans them up, hoards commits locally instead of pushing, and never deletes branches after their PRs merge. The classic collapse — dozens of stale local branches, a pile of local-only commits, orphan worktrees — loses *nothing* (it's all merged), but it makes finished work read as **unmerged / lost**, triggers a false "it's only backed up, not applied" scramble, and burns large reconciliation time and trust. Claude and Codex add a verified Stop-hook reminder; every adapter installs the obligations below.

## The 7 obligations

### G1 — No worktrees unless explicitly requested
The default work model is **normal branches in the single working tree**. Reach for `git worktree` only when the user explicitly asks, or a documented isolation need exists. If you create one, **remove it in the same session** (`git worktree remove`) and delete its branch. An orphan worktree's uncommitted/unpushed work reads as a phantom "lost / unmerged feature" to the next actor.

### G2 — Push, never hoard
The moment a commit is worth keeping, push it to a **named branch on origin**. Do not accumulate local-only commits. Invariant: at session end `git log --branches --not --remotes` is **empty**. Local-only piles are the direct cause of "unpushed/lost feature" panics and the cost of later diffing what is *actually* missing.

### G3 — Merge means delete
When a PR merges, immediately delete that branch **both local and remote** (`git branch -d/-D` + `git push origin --delete`). Stale pointers — especially a pre-squash local pointer left after a squash-merge — masquerade as an "unmerged feature" and are the #1 source of the illusion.

### G4 — Backup ≠ applied
Pushing to an isolated/backup branch is **not** integration. "It's backed up" and "the feature is on the target branch / live" are separate claims. Verify a feature is on your integration/target branch by reading the **actual code** there (file / symbol / value grep), never by the existence of a backup branch. This is `quality-gates.md` Q4 (verify-after-changes) applied to git: a backup is a safety net, never a completion verdict.

### G5 — No reckless branch ops on a shared repo
No force-push / rebase / reset / branch-move / protected-branch rewrite that a concurrent session or another actor might be building on. Minimize branch churn; when a branch operation's scope or reversibility is unclear, ASK (`meta-discipline.md` AMB-3/AMB-4 — non-trivially-reversible ops and protected-branch writes force ASK). **Another session's uncommitted/unpushed work is inviolable** — back it up and surface it, but never merge/delete/rewrite it on your own judgment.

### G6 — Bundle PRs (CI economy)
Bundle related work into as few PRs as reasonable — CI runs per PR and free-tier minutes are finite. Do not fragment one change into many PRs that each re-consume CI, and do not push docs-only commits mid-review that re-trigger the whole pipeline. Verify locally before the single push so the one CI run passes first try.

### G7 — Session-end hygiene check
Before finishing a session: **0 orphan worktrees · 0 local-only commits (all on origin) · merged branches deleted · current branch + working-tree state clear.**

- [ ] `git worktree list` → only the main tree (unless a requested worktree is still mid-use)?
- [ ] `git log --branches --not --remotes --oneline` → empty?
- [ ] Merged PR branches deleted (local + remote)?
- [ ] Not sitting on a stale/behind branch that hides completed work?

## Conductor Integration

- **Claude / Codex** — `stop-git-hygiene-guard` fires a **non-blocking
  reminder** in the product's verified Stop-hook dialect when it detects extra
  worktrees, local-only commits, or an abnormal local-branch count. It self-gates
  on this recipe, cools down, always fails open, and honors the documented
  environment overrides.
- **Cursor / Copilot / Gemini / Windsurf** — CONDUCTOR does not emit an unverified
  equivalent Stop guard. The installed G7 checklist is the enforcement floor;
  Windsurf also lacks a Stop-style event.
- **Target branch** — G2/G3/G4 reference your *integration/target branch* (commonly `main`, or `develop` if you also install the `branch-strategy` recipe). Substitute your project's value.

## Cross-References

- `quality-gates.md` §4 (verify-after-changes) — G4's "verify by real code, not by a backup branch."
- `meta-discipline.md` §3 (AMB-3/AMB-4) — G5's ASK-before-reckless-branch-op gate.
- `meta-discipline.md` §5.7 (lossless-before-lossy compaction) — the *uncommitted-durability* layer beneath G2's *unpushed-hygiene* layer; complementary.
- `branch-strategy.md` recipe — defines the target/integration branch model G2–G4 build on.
- `core/anti-patterns/frequent-rule-file-edit.md` — G6's "don't re-trigger CI with churn" echoes the cost-of-churn principle.
