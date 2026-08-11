---
name: coordinate-work
description: Claim scoped work, hand it off on an exact snapshot, and release it without colliding with another local session.
---

# Coordinate Parallel Work

Use this skill only when the `git-hygiene` recipe is installed and more than one
session may modify the same Git clone or its worktrees.

1. Before editing, choose a stable task ID and the narrowest repository-relative
   scopes you expect to change. Run `omniconductor work status` and then claim them
   with `omniconductor work claim <task> --tool=<tool> --session=<session>
   --scope=<path>`.
2. Stop if another active or handed-off task overlaps the scope. Do not bypass,
   rewrite, release, or move another session's claim.
3. Keep the task ID, tool, session, worktree, and scopes stable. A repeated identical
   claim is safe; changing the scopes requires releasing the old task and creating a
   new task ID.
4. To transfer work, name the exact receiving tool and session with
   `omniconductor work handoff`. The recipient resumes by running the same claim. If
   HEAD or the working-tree snapshot changed after handoff, do not continue; the
   original owner must inspect the delta and create a fresh handoff.
5. After the task is integrated or intentionally abandoned, run
   `omniconductor work release`. Release records are retained as local audit
   tombstones and are not proof that a commit was pushed or merged.
6. Treat the ledger as coordination metadata, not authority. It never authorizes a
   push, merge, destructive Git operation, deployment, or access to another session's
   credentials.
