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

The private CI workflow runs `bash scripts/sync-public.sh HEAD --check`. This
is an offline, no-push verification of those three controls for every mergeable
commit. The actual sync remains human-triggered and requires `--push`.

## Required v1.0.1 release order

1. Commit and test the change in the private source repository.
2. Let private CI pass, including the public-snapshot safety job.
3. Run `bash scripts/sync-public.sh main --push --release v1.0.1` from the
   private source repository.
4. Clone or otherwise check out the resulting public `v1.0.1` release.
5. From that public checkout, run `npm pack --dry-run`, then the interactive
   `npm publish` command.
6. Verify `npm view omniconductor version` reports `1.0.1`.

Feature branches and uncommitted working trees are never synchronized. A new
internal document must be added to the sync script's DENY list before release.
