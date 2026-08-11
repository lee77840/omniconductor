---
recipe_id: non-vacuous-testing
recipe_name: "Non-vacuous test assurance — prove the gate detects the named defect"
applies_when: "A test or release gate is used as evidence that a behavior, regression, permission, integration, or failure mode is protected"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
linked_recipes:
  - tdd
---

# Recipe — Non-Vacuous Testing

> Opt-in assurance layered on normal testing or TDD. A green test proves only that its
> executed assertions passed. This recipe requires evidence that the test reaches the
> intended branch and fails when the protected behavior is absent or wrong.

## 1. Name the defect the gate must detect

For each material test claim, identify:

- protected behavior and observable outcome;
- defect or mutation that must make the test fail;
- assertion, probe, or artifact that detects it;
- boundary dependencies that are real, stubbed, simulated, or unavailable;
- exact code and test snapshot used for the observation.

Test names, fixture names, coverage percentages, and a green command are not sufficient
evidence by themselves.

## 2. Establish negative sensitivity

Use the narrowest applicable proof method:

1. **RED-before-fix** — reproduce the real defect and retain the expected failure.
2. **Targeted mutation** — temporarily invert/remove the protected behavior and prove
   the named test fails for the intended reason.
3. **Fault injection** — make the dependency return the relevant error, timeout, empty,
   unauthorized, or malformed state and prove the assertion observes it.
4. **Assertion reachability** — prove conditional assertions and helper assertions ran;
   a test that skipped its meaningful branch is not a pass.
5. **Stub contract** — prove the intended route/mock was consumed, its request matched,
   and an unused or wrong stub cannot silently produce green.

Do not mutate production or shared external state to obtain negative proof. Work in a
temporary checkout, local fixture, transaction, or reversible test seam. Restore the
original code and rerun the final positive gate on the recorded snapshot.

## 3. Audit common vacuity patterns

- caught errors that never rethrow or assert;
- assertions guarded by conditions that may never become true;
- tests with no meaningful assertion or observable state check;
- selectors that match an unrelated element;
- mocks that test their own return value instead of product behavior;
- retries that turn a first-attempt failure into an undocumented green gate;
- optional credentials or configuration that skip a trusted/internal gate;
- snapshots updated by the same verification step that is supposed to detect drift.

Static scans produce candidates, not verdicts. Review each hit and retain the evidence
that distinguishes a real defect from a valid helper or negative-path test.

## 4. Evidence and status

Record the negative proof, final positive run, exact snapshot, command, exit status, and
bounded artifact reference. If negative sensitivity was not established, use
`verification-required`; if the required runtime or credential is unavailable, use
`environment-limited` or `blocked`. Never promote “did not throw” or “not reproduced”
to `passed` without the named observable.

Mutation frameworks are optional accelerators. No language, test runner, mutation
score, or provider-specific tool is a universal requirement.
