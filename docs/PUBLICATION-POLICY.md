# Publication Policy — private source, public distribution

## Decision

CONDUCTOR uses a **dual-repository model**:

| Surface | Visibility | Purpose |
|---|---|---|
| Working source repository | Private | Development, operational history, internal audits/plans, release safety controls, and the private-token deny list. |
| `omniconductor` mirror | Public | User-visible source, GitHub Releases, issue/discussion entry point, and the exact tree used for npm publication. |

The working source repository **must never be made public**. Changing its
visibility would expose all historical commits, including artifacts that a
current file filter cannot remove. A clean public repository is produced only
by the filtered-mirror process below.

## Enforced publication boundary

`scripts/sync-public.sh` creates a snapshot from committed private `main` and
fails closed before any push when either control fails:

1. A structural DENY list removes private-only paths, including operational
   session files, maintainer scripts, internal audit/plan/spec/data directories,
   and the private-token list itself.
2. Every private token is scanned across the entire filtered snapshot. One hit
   aborts the operation even if the affected file was not anticipated by the
   DENY list.
3. The framework-purity gate must pass.

`npm run release:verify:local` is the routine validation entry point. On a clean
tree it also runs `bash scripts/sync-public.sh HEAD --check`, an offline, no-push
verification of those three controls. On a dirty development tree it clearly
defers that committed-snapshot step; the strict release invocation below rejects
that state. The actual sync remains human-triggered and requires `--push`.

GitHub workflows are disabled remotely and declared `workflow_dispatch` only.
Pushes and pull requests do not consume Actions minutes. A maintainer may manually
dispatch them immediately before a necessary release, but local validation remains
the required gate. There is no scheduled automatic reactivation.

## Required release order

1. During development, run `npm run release:verify:local`. It tests the full local
   suite, exact packed npm artifact, fresh six-tool install, published-version
   upgrade matrix, doctor/uninstall behavior, and `npm publish --dry-run` without
   pushing, dispatching CI, or publishing.
2. Commit the release candidate in the private source repository, then run
   `CONDUCTOR_RELEASE_REQUIRE_CLEAN=1 npm run release:verify:local`. This reruns the
   suite and fails unless the exact committed `HEAD` passes the filtered public
   snapshot boundary.
3. Only when a release genuinely needs the extra remote signal, manually dispatch
   the disabled GitHub workflows and verify them. This is optional; never re-enable
   push/PR triggers.
4. Read the version from `package.json`, then run
   `bash scripts/sync-public.sh main --push --release v<version>` from the private
   source repository.
5. Clone or otherwise check out the resulting public `v<version>` release.
6. From that public checkout, run `npm pack --dry-run`, then the interactive
   `npm publish` command.
7. Verify `npm view omniconductor version` reports the exact `package.json` version.

Feature branches and uncommitted working trees are never synchronized. A new
internal document must be added to the sync script's DENY list before release.
