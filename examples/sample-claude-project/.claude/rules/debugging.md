---
paths:
  - "**"
---

---
recipe_id: debugging
recipe_name: "Systematic Debugging (Root-Cause-First)"
applies_when: "any bug, test failure, unexpected behavior, or production incident — whenever the temptation to 'just try something' arises"
severity: STRONG (when installed)
linked_rules:
  - meta-discipline
  - spec-as-you-go
---

# Recipe — Systematic Debugging

> Opt-in recipe. Install on any project where bugs are a reality (i.e., all of them). Especially valuable on codebases where time pressure makes guess-and-check feel faster — it isn't.

## When to Apply

Any technical issue where behavior diverges from expectation:

- Test failures (unit, integration, E2E)
- Production bugs
- Unexpected output or side effects
- Build or compilation failures
- Performance regressions
- Integration failures between services

**Apply especially when:**

- Under time pressure — urgency makes guessing tempting, which is when it causes the most damage
- "One quick fix" seems obvious — obvious fixes treat symptoms
- You have already tried at least one fix — if the first fix failed, the root cause is not what you thought
- You do not fully understand why the issue occurs

## Pattern — Four Phases

Phases are sequential. Do not advance to the next phase until the current phase is complete.

### Phase 1 — Reproduce

Establish a deterministic, minimal reproduction. A bug you cannot reproduce consistently cannot be verified as fixed.

Steps:
1. Read the full error message and stack trace — they frequently contain the exact file, line, and cause
2. Write down the exact steps that trigger the issue
3. Confirm the issue occurs every time those steps are followed
4. If not reproducible: add logging at component boundaries to gather evidence before continuing

For multi-component systems (API → service → database, CI → build → signing), add boundary logging at each layer before forming any hypothesis:

```bash
# Example: trace where in a pipeline a value goes wrong
echo "=== component A output: ${VALUE:+SET}${VALUE:-UNSET} ==="
# ... run the pipeline ...
echo "=== component B received: $RECEIVED ==="
```

Run once to gather evidence. Identify which layer breaks. Then investigate that specific layer.

### Phase 2 — Isolate

Narrow the search space before forming a hypothesis.

Steps:
1. Find working code similar to the broken code in the same codebase
2. Compare working vs. broken — list every difference, however small
3. Check recent changes: `git log --oneline -20`, `git diff HEAD~5`
4. Identify what changed that could cause this (new dependency, config change, environment difference)
5. Use `git bisect` for regressions that appeared between two known-good commits

```bash
# Binary search for the commit that introduced a regression
git bisect start
git bisect bad HEAD
git bisect good <last-known-good-commit>
# git bisect will check out commits; run your test and mark good/bad
git bisect run npx vitest run path/to/failing.test.ts
```

### Phase 3 — Hypothesize and Verify

Form one specific hypothesis. Test it minimally.

1. Write down: "I believe X is the root cause because Y"
2. Make the smallest possible change that would confirm or refute this hypothesis
3. Run the test — did it work?
   - Yes → proceed to Phase 4
   - No → form a NEW hypothesis; do NOT layer additional changes on top of the failed one
4. If you genuinely do not know: say so, add more logging, return to Phase 1 with new evidence

One variable at a time. Multiple simultaneous changes make it impossible to know which change fixed (or broke) something.

### Phase 4 — Fix and Regression-Test

Fix only the confirmed root cause. Then lock it in with a test.

1. Write a failing test that reproduces the bug (apply `core/recipes/tdd.md`)
2. Implement the minimal fix
3. Confirm the test passes
4. Run the full suite — confirm no regression introduced
5. If the fix does not work: return to Phase 1 with new evidence

**If three or more fixes have failed:** stop attempting fixes. The root cause may be architectural — a coupling or shared-state assumption that no local fix can address. Discuss with your team before attempting another fix.

After a confirmed fix, update the relevant spec or known-issues section (spec-as-you-go). Bugs that recur after being fixed typically had no regression test and no spec update.

## Tool Reference

| Tool | Use |
|---|---|
| `git bisect` | Binary-search commits to find regression introduction point |
| `git stash` | Temporarily remove local changes to verify they are or are not the cause |
| `git diff HEAD~N` | See what changed in the last N commits |
| Structured logging | Add `console.log` / logger at component boundaries during Phase 1; remove before commit |
| Debugger / breakpoints | Confirm data values at specific points in the call stack |
| Minimal reproduction test | Isolate the failing behavior in the smallest possible test case |

## Conductor Integration

**meta-discipline (M1 — verify before claim)**: A fix is not complete until the test passes and the full suite is green. Do not report "fixed" before verifying.

**spec-as-you-go (W3)**: Bug fixes update the spec. If the bug was a known edge case not previously documented, add it to the spec's known-issues section. If the fix changes behavior, update the relevant spec section.

**workflow.md W2 (build phase)**: When a build-phase failure occurs, invoke this recipe before proposing any code change. The recipe gates Phase 4 on Phases 1-3 being complete.

**tdd.md**: Phase 4 of this recipe directly invokes the TDD cycle — write the failing test first, then fix. The two recipes are complementary: TDD prevents bugs; this recipe resolves them when they occur anyway.

## Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| "Just try X and see if it works" | Sets a guess-and-check precedent. First guess being right is luck; subsequent guesses are compounding debt. |
| Suppress the error with try/catch | Treats the symptom. The root cause continues to fire; you just stopped hearing about it. |
| Multiple simultaneous fixes | If the bug disappears, you cannot know which fix resolved it. If it persists, you have added noise. |
| Asking an LLM before gathering evidence | Without a minimal reproduction and specific error output, LLM responses are pattern-matched hallucinations, not diagnosis. |
| Time-pressure skip of Phase 1-2 | Systematic debugging is faster than guess-and-check. Urgency is when discipline matters most, not when to abandon it. |
| Fix without a regression test | The bug will recur. A fix with no test is a temporary suppression. |
| "One more fix attempt" after two failures | Three failures indicate the hypothesis model is wrong, not that a better fix exists within the same model. |

## Cross-References

- `core/universal-rules/meta-discipline.md` — M1 verify before claim: fix is not done until verified
- `core/universal-rules/spec-as-you-go.md` — bug fixes update specs and known-issues sections
- `core/recipes/tdd.md` — Phase 4 creates the failing test; TDD cycle drives the fix
- Methodology adapted from Superpowers `systematic-debugging` skill (paraphrased; not reproduced verbatim)
