---
recipe_id: visual-baseline-integrity
recipe_name: "Visual baseline integrity — pinned rendering, reviewable diffs, fail-closed verification"
applies_when: "Project treats screenshot or rendered-output comparison as a release or regression gate"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
linked_recipes:
  - non-vacuous-testing
---

# Recipe — Visual Baseline Integrity

> Opt-in recipe for screenshot, document-render, and other pixel/image baselines. It
> defines the evidence contract; it does not require one browser, test runner, CI
> provider, operating system, or image-diff library.

## 1. Pin the rendering contract

Record the operating system or container image, architecture, browser/renderer and
version, fonts, locale, timezone, viewport/device scale, color mode, and relevant
feature/configuration state. Generate and verify a baseline under the same declared
contract. Host-local rendering in a different environment is diagnostic, not a valid
replacement for the canonical gate.

The baseline inventory records one stable case ID per expected image. Missing,
duplicate, unexpectedly added, or orphaned images fail the inventory check.

## 2. Separate update from verification

- Verification compares current output with committed/approved baselines and must not
  update them.
- Rebaseline is an intentional operation with a reviewable diff and explicit reason.
- After an update, run a separate verify-only pass from a clean rendering environment.
- A test process may not approve the baseline it just generated.

## 3. Preserve review evidence

For every mismatch retain bounded references to expected, actual, and diff images plus
the exact code tree, baseline tree, render contract, test case, and command. Review the
images rather than accepting a changed checksum alone. Mask only data proven irrelevant
and nondeterministic; record each mask because expanding it reduces coverage.

## 4. Timing, retries, and configuration

- Prefer readiness markers tied to the intended UI state over arbitrary sleeps.
- A retry-recovered attempt remains flaky evidence. A gate claiming deterministic or
  fail-closed behavior must fail on flaky tests or report a non-passed status.
- Trusted/internal gates fail when required configuration or credentials are missing.
  A fork or untrusted context may be explicitly `blocked` or `not-run`, never PASS.
- Preserve traces, logs, and diff artifacts on terminal failure. Artifact upload itself
  must fail visibly when the contract says those diagnostics are required.

## 5. Result semantics

Bind verification to one final snapshot. Record baseline count, tested count, passed,
failed, flaky, skipped, and missing-artifact counts. Only a complete verify-only run
with no unresolved mismatch, undocumented flaky result, or missing required artifact
is `passed`. Environment mismatch is `environment-limited`; an intentional baseline
change awaiting visual review is `verification-required`.
