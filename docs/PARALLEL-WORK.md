# Local Parallel Work Contract

CONDUCTOR coordinates concurrent sessions in one Git clone/worktree family without a
server or distributed lock. Records live below Git's common directory, so they are
visible to sibling worktrees but never enter commits or provider prompts.

## Claim and release

```bash
omniconductor work status .
omniconductor work claim feature-auth . \
  --tool=codex --session=local-42 --scope=src/auth --scope=tests/auth

# after integration or intentional abandonment
omniconductor work release feature-auth . \
  --tool=codex --session=local-42 --note=complete
```

Scopes are normalized repository-relative paths. `.` overlaps every scope; `src`
overlaps `src/auth`; siblings such as `src/web` and `src/mobile` do not overlap.
Active and handed-off scopes are reserved. Another session cannot override or release
them.

## Snapshot-bound handoff

```bash
omniconductor work handoff feature-auth . \
  --tool=codex --session=local-42 \
  --to-tool=claude --to-session=review-7 \
  --note=implementation-ready

# named recipient, in the same worktree
omniconductor work claim feature-auth . \
  --tool=claude --session=review-7 --scope=src/auth --scope=tests/auth
```

Handoff captures HEAD plus a digest of the tracked diff, Git status, and content hashes
for untracked files. It stores no diff or file content. If the snapshot changes before
the named recipient claims it, resume fails and the source owner must inspect and
recreate the handoff.

## Boundaries

- Local clone/worktree family only; no cross-machine or remote authority claim.
- A claim coordinates ownership but never authorizes commit, push, merge, deployment,
  workflow mutation, or credential access.
- Released task IDs remain tombstones and cannot be reused.
- `doctor` D14 reads the ledger and fails on unsafe records, conflicting scopes,
  missing worktrees, or handed-off snapshot drift.
- The `coordinate-work` skill is emitted on all seven adapters only with the
  `git-hygiene` recipe.
