---
name: review-change
description: Perform a read-only review of a local change, patch, or proposed merge for concrete correctness, security, compatibility, and test defects. Use when findings and a merge-readiness verdict are needed without modifying the implementation.
---

# Review Change

Review the change as a skeptical maintainer. Remain read-only: do not edit files,
resolve comments, commit, push, publish, or alter external state.

## Establish the review baseline

1. Read project instructions, acceptance criteria, current-work notes, and relevant
   design decisions.
2. Identify the intended base and enumerate the complete diff, including untracked
   files and generated artifacts.
3. Separate the reviewed change from pre-existing or unrelated working-tree edits.
4. Note unverified assumptions instead of inventing intent.
5. Record the reviewed base and exact snapshot identity: commit/tree SHA when
   available, otherwise a deterministic complete-diff digest that includes untracked
   files.

If prior review evidence exists, compare its snapshot identity first. An identical
head/base needs only a provenance check plus PR-specific evidence. New commits require
review of the unreviewed delta and affected callers. Rewritten history, an incompatible
base change, or missing provenance requires a fresh full review.

## Trace affected behavior

For each changed contract, follow all producers and consumers. Inspect:

- input validation and failure paths;
- state transitions, cleanup, retry, and idempotence;
- callers, adapters, installers, migrations, and uninstall behavior;
- trust boundaries, credentials, logs, paths, and process execution;
- generated documentation and packaging allowlists;
- tests that should fail if the implementation is wrong.

Check preserved behavior and compatibility claims explicitly. A locally correct helper
can still break a downstream consumer or leave stale output.

## Find actionable defects

Prioritize issues that can cause incorrect behavior, data loss, security exposure,
unrecoverable state, compatibility regression, or false confidence from missing tests.

For each finding:

1. identify the smallest relevant file and location;
2. describe the concrete trigger;
3. trace the resulting failure or risk;
4. explain why existing validation does not prevent it;
5. suggest the direction of a fix or regression test without implementing it;
6. assign severity based on user impact and likelihood.

Do not report style preferences, speculative future work, or project-wide issues
unrelated to the change. Avoid duplicating the same root cause across multiple
findings.

## Evaluate tests and claims

Confirm that tests reach the changed branch, assert observable state, cover failure
and cleanup behavior, and cannot pass for the wrong reason. Compare reported counts,
paths, metadata, and compatibility statements against direct evidence.

If execution is safe and read-only, run focused checks that materially increase
confidence. Otherwise explain what remains unverified.

## Return the review

Lead with findings ordered by severity. Include precise locations and concise evidence.
Then state:

- open questions or verification-required items;
- the checks performed;
- reviewed base and snapshot identity;
- review scope (`full`, `delta`, or `provenance-check`);
- the merge-readiness verdict.

If no actionable defects are found, say so directly and name any residual testing or
environmental risk. Do not imply that absence of findings proves correctness.
