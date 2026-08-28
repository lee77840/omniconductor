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

## Read-only workspace bootstrap plan

An isolated worktree may declare the small amount of local setup it expects in
`.conductor/bootstrap.json`:

```json
{
  "schema_version": 1,
  "copy_allowlist": [".tool-versions", "config/local.defaults.json"],
  "setup_steps": [
    { "id": "dependencies", "cwd": ".", "argv": ["npm", "ci"] }
  ]
}
```

Inspect the manifest against an explicitly trusted source worktree before doing any
manual setup:

```bash
omniconductor workspace bootstrap check ./feature-worktree --source=./main-checkout
omniconductor workspace bootstrap plan ./feature-worktree --source=./main-checkout
```

Both commands are read-only. `plan` prints the same-relative-path copy candidates and
setup argv, but it never copies a file or executes a command. There is deliberately no
`apply`, cleanup, network, secret-resolution, or command-execution path.

The validator fails closed on all `.env` variants (including `.env.example`),
credential/key paths, known credential literals and credential-bearing URLs,
repository/CONDUCTOR control metadata, binary or oversized files, absolute or
parent-traversing paths, symlink components, hardlinked files, unsafe setup
directories, direct shell interpreters, indirect command wrappers, explicit
interpreter-evaluation flags, and destination conflicts. Existing byte-identical
destinations are reported as already present; different content is never overwritten.
Use a non-secret template such as `config/local.defaults.example` instead of an
`.env*` file. This is a bounded preflight, not a claim that arbitrary programs such
as package managers cannot execute project code if a human later chooses to run them.
This provider-independent CLI contract is available to all seven adapters without
claiming a provider-native bootstrap hook.

## Boundaries

- Local clone/worktree family only; no cross-machine or remote authority claim.
- A claim coordinates ownership but never authorizes commit, push, merge, deployment,
  workflow mutation, or credential access.
- Released task IDs remain tombstones and cannot be reused.
- `doctor` D14 reads the ledger and fails on unsafe records, conflicting scopes,
  missing worktrees, or handed-off snapshot drift.
- Bootstrap `check` and `plan` authorize no copy or execution; a human must separately
  perform and review any displayed action.
- The `coordinate-work` skill is emitted on all seven adapters only with the
  `git-hygiene` recipe.
