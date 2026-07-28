---
name: verify-change
description: Verify concrete implementation or release claims and diagnose failures from evidence. Use after a change, during regression investigation, or before handoff when acceptance criteria, safety properties, generated output, or package contents must be proven.
---

# Verify Change

Turn each claimed outcome into a reproducible observation. Diagnose by default; change
implementation only when the request explicitly includes a fix.

## Build the claim matrix

1. List each claim separately.
2. Map it to the source, generated artifact, runtime behavior, or preserved state that
   can prove or disprove it.
3. Identify negative claims that require searching for absence, such as leaked
   credentials, stale output, unexpected writes, or unsupported configuration.
4. Mark claims that need an external service, credentials, unavailable runtime, or
   nondeterministic environment as requiring verification. Do not infer a pass.

Include compatibility and no-change invariants, not only the new happy path.

## Inspect before executing

Read project instructions, the relevant design record, the current diff, callers, and
existing tests. Check whether tests actually exercise the named branch and assert the
observable result. A code path or fixture name is not coverage by itself.

Preserve unrelated working-tree changes. Do not rewrite generated files, install
dependencies, contact external services, or mutate durable state unless those actions
are authorized and required by the verification contract.

## Verify from narrow to broad

Run the smallest deterministic check that can disprove a claim, then expand as the
change stabilizes:

1. syntax and structural validation;
2. focused unit or regression tests;
3. integration, installation, migration, and removal tests;
4. full project gates once on the final stable snapshot;
5. package or consumer checks when distribution behavior is in scope.

Inspect both command status and resulting state. Use fresh temporary locations for
stateful tests. Capture exact counts, exit codes, key diagnostics, file inventories,
digests, or byte comparisons as appropriate.

During a fix loop, rerun the affected focused checks rather than the unchanged full
suite. If the exact head SHA already has trusted full-gate evidence, verify the SHA and
reuse it. Any code change invalidates that snapshot's evidence: rerun affected checks
and establish one new final full-gate result before completion.

For read-only or security claims, compare state before and after and inspect process
boundaries, environment forwarding, logs, and error paths.

## Diagnose failures

When a check fails:

1. reproduce it with the narrowest command;
2. distinguish implementation defects from test defects, environment limits, and
   stale generated output;
3. trace the earliest violated invariant;
4. explain the root cause and affected scope;
5. propose the smallest safe repair and its regression test.

Never weaken, skip, or relabel a failing gate to make the result pass. If repair is
authorized, apply it and rerun the failed check plus the relevant broader gates.

## Report evidence

For every claim, report `confirmed`, `failed`, or `verification-required`, followed by
the specific evidence. Separate observed facts from inference. State:

- what was inspected or executed;
- the exact result;
- gaps or environmental limitations;
- any mutations performed;
- the final working-tree and external-action status.

Do not claim complete verification while a required check remains unrun or ambiguous.
