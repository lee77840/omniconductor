---
recipe_id: tdd
recipe_name: "Test-Driven Development (Red-Green-Refactor)"
applies_when: "project has a test framework (vitest / jest / pytest / etc.) and wants TDD methodology enforced across feature work, bug fixes, and refactors"
severity: STRONG (when installed)
linked_rules:
  - spec-as-you-go
  - quality-gates
---

# Recipe — Test-Driven Development

> Opt-in recipe. Install on projects with an established test framework where TDD discipline is a team standard. Do NOT install on throwaway prototypes or projects with no testing infrastructure — adopt the test framework first.

## When to Apply

Every development activity that changes behavior:

- **New feature** — write the test before writing production code
- **Bug fix** — write a failing test that reproduces the bug; then fix it
- **Refactor** — green test suite is the safety net; refactor to keep it green
- **Behavior change** — update the test first to reflect the new expected behavior

Exceptions (discuss with your human partner before skipping):

- Throwaway exploration / spike — throw away the spike code; start fresh with TDD
- Generated / scaffolded code — add behavior tests before modifying generated output
- Configuration files with no testable behavior

## Pattern — Red-Green-Refactor

The TDD cycle has three phases. Each phase has an explicit STOP-AND-VERIFY step that cannot be skipped.

### RED — Write One Failing Test

Write the smallest test that describes a single desired behavior. Run the suite and confirm the test fails for the right reason (missing feature, not a syntax error).

```bash
# vitest
npx vitest run path/to/file.test.ts

# jest
npx jest path/to/file.test.ts

# pytest
pytest tests/test_feature.py::test_specific_case -v
```

A test that passes immediately proves nothing — it was either testing existing behavior or testing the wrong thing. If it passes on first run, fix the test.

### GREEN — Minimal Implementation

Write the simplest code that makes the failing test pass. "Simplest" means: no speculative features, no generalization the test does not require, no YAGNI extensions. If the test passes with three lines, ship three lines.

Do not refactor during Green. Refactoring while Red is still on the board is how the cycle breaks.

```bash
# Watch mode for rapid Red → Green iteration
npx vitest --watch path/to/file.test.ts
pytest-watch tests/
```

After the test passes, run the full suite to confirm no regression.

### REFACTOR — Clean Up, Stay Green

With Green confirmed, remove duplication, improve names, extract helpers. Every refactor step must keep the suite green. Refactoring does not mean adding new behavior — that starts a new Red phase.

Commit discipline: keep Red, Green, and Refactor as separate commits when the history is audited. This is an option, not a hard requirement — but it makes rollback and review significantly cleaner.

## Canonical Cycle for a Bug Fix

1. Reproduce the bug with a deterministic, minimal failing test
2. Confirm the test fails with the exact error message the bug produces
3. Write the minimal fix
4. Confirm the test passes; run the full suite
5. Refactor the fix if the implementation is rough

Never fix a bug without a test. A fix without a test is a guess that happened to work today.

## Sub-Agent Dispatch Ordering

When delegating implementation via sub-agents, the brief MUST specify this sequence:

1. Write the failing test(s) first
2. Implement until the tests pass
3. Run the full suite and confirm green
4. Report test output as proof of completion

A sub-agent that returns "implemented X" without test output has not completed the task.

## Conductor Integration

**spec-as-you-go (W3)**: Tests are executable specs. When a feature's behavior changes, the test changes first. The spec doc and the test should describe the same invariants.

**quality-gates (Q1 pre-commit)**: Test passage is a pre-commit gate. The gate is not "tests exist" — it is "tests run green." Both conditions are required.

**workflow.md W2 (build phase)**: Every W2 implementation task applies this recipe's Red-Green-Refactor cycle. The plan should include an explicit "write failing tests first" step in the W2 brief.

## Anti-Patterns

| Anti-pattern | Why it breaks TDD |
|---|---|
| Write implementation first, tests after | Tests-after answer "what does this do?" Tests-first answer "what should this do?" Tests-after are biased by the implementation you just wrote. |
| Write 10+ failing tests in one Red phase | Massive Red phases extend the feedback loop and make root cause diagnosis harder when Green fails. Write one test at a time. |
| Mock-heavy tests that never touch real code | Tests that exercise only mock return values give false confidence. Use real code paths; mock only unavoidable I/O boundaries (network, filesystem, clock). |
| "Too simple to test" rationalization | Simple code breaks in context. The test costs 30 seconds. |
| Refactoring during the Red phase | You cannot safely refactor against a failing test. Always refactor from Green. |
| Keeping unverified "reference" implementation | Once you have reference code, you will adapt it instead of deriving from the test. Delete it. Start from the test. |

## Verification Checklist

Before marking any task complete:

- [ ] Every new function or method has a test that was written first
- [ ] Watched each test fail before implementing
- [ ] Each test failed for the expected reason (feature absent, not typo)
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] No warnings or errors in test output
- [ ] Tests cover edge cases and error paths (not just happy path)

## Cross-References

- `core/universal-rules/spec-as-you-go.md` — tests as executable specs; same-turn update rule
- `core/universal-rules/quality-gates.md` — Q1 pre-commit: test green is a hard gate
- `core/recipes/debugging.md` — when a test fails during investigation, this recipe owns the fix cycle
- Red-Green-Refactor is Kent Beck's method; this recipe is independently written. Its structure was informed in part by the **Superpowers** project (idea-level; no text reproduced) — see `THIRD_PARTY_NOTICES.md`.
