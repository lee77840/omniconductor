---
recipe_id: loop-engineering
recipe_name: "Loop Engineering (bounded, externally-verified agent loops)"
applies_when: "any agentic coding work that iterates — generate→verify→fix→re-verify, test-fix loops, multi-step tasks"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
  - meta-discipline
  - workflow
---

# Recipe — Loop Engineering

> Opt-in recipe. Install for any project where the agent works in a **loop** — "do → check → fix → re-check until done." It codifies how to run that loop so it **terminates correctly, stays bounded, and never declares success without an external check.** Install if you want agent loops that are reliable instead of ones that thrash, run away, or report "done" on unverified work.

## Why this exists

An agent that loops "until it's right" fails in a few well-documented ways. The evidence (peer-reviewed + Anthropic primary sources) is blunt:

- **Self-correction without an external signal is unreliable and can make things WORSE.** Models asked to fix their own work with no external feedback often flip correct answers to wrong ones (*LLMs Cannot Self-Correct Reasoning Yet*, Huang et al., DeepMind, ICLR'24). The real gains come from loops grounded in **tests/tools** (Reflexion, CRITIC), not self-judgment.
- **"The model says it's done" is not evidence.** LLM self-assessment is systematically over-confident, and LLM-as-judge carries position/verbosity/self-preference bias (*Judging LLM-as-a-Judge*, Zheng et al., NeurIPS'23). Declaring victory without running the check ("early victory") is the most common fidelity failure.
- **Unbounded loops run away.** Infinite / oscillation (edit↔revert) loops are a documented structural failure — in one study **95.6% ended in cost exhaustion / model-DoS** (*When Agents Do Not Stop*, 2026). More iterations help only up to a point, then *saturate and hurt*; long trajectories degrade (context rot, error compounding).

So a good loop is **bounded, progress-checked, and terminated by an external verifier** — not by the model's opinion. Prose gets forgotten, so on the Claude adapter this recipe is backed by a `pretool-loop-guard` hook.

## The loop shape (well-supported)

```
Plan → (act → verify) loop → replan on failure → escalate on repeated stall
```

- **Plan first**, then act (ReAct: interleave reason+act+observe beats act-only).
- On a failed check, **reflect and replan** using the failure (Reflexion) — not a blind retry.
- Reserve expensive search/branching (Tree-of-Thoughts) for genuinely exploratory tasks; the default loop stays simple (Anthropic: "the simplest solution possible; add complexity only when it demonstrably improves outcomes").

## The 6 obligations

### G1 — Terminate on an explicit, verified done-criterion
Before looping, state what "done" IS (a passing test, a matching value, a satisfied spec item). The loop ends when that criterion is **verified true** — never on a vibe or a word-count of effort.

### G2 — Bound the loop (iteration + token budget)
Set a ceiling before you start: a max number of iterations AND a token/time budget. When the ceiling is hit, **stop and report** (with what's done and what's left) — do not silently keep going. Anthropic ships this as `max_turns` / `max_budget_usd` ("a good default for production agents").

### G3 — Require progress each iteration
Every pass must change state toward the goal. If an iteration produces no new information or the same result, that is a **no-progress signal** — stop and rethink rather than repeat. (More iterations past the point of progress saturate, then degrade quality.)

### G4 — Escalate on stall, don't loop forever
After a small number of failed/no-progress iterations (default ~3–5), **hand back to the human** with the state and the blocker, instead of looping. Ties to `meta-discipline.md` AMB — when stuck or the next step is non-trivially reversible, ASK.

### G5 — Verify externally, never by self-judgment (the core rule)
A loop's exit signal MUST be an **external / ground-truth check** — run the test, execute the code, lint against the rule, diff the value — **not** the model asserting "looks correct." Verify hierarchy (Anthropic, strongest first):

1. **Rules / tests / tool output** — deterministic, best (e.g. run the test suite; lint TS instead of eyeballing).
2. **Visual / rendered feedback** — screenshots, output diffs.
3. **LLM-as-judge** — weakest, last resort, and never the sole gate.

This is `quality-gates.md` Q4 (verify-after-changes) applied inside the loop. "Declared done without running the check" = the early-victory anti-pattern; it is a rule violation here.

### G6 — Guard against oscillation / infinite loops
Detect and break repetition: the same action repeated, or an edit↔revert cycle, means the loop is spinning. Track what you've already tried; if you're repeating, **change approach or escalate (G4)** — never keep re-issuing the same failing action.

## Conductor Integration

- **Claude** — a PreToolUse hook `pretool-loop-guard` (from `core/hooks/`) tracks a per-session signature of each tool call and fires a **non-blocking soft-warn** (`permissionDecision: ask`) when the **same action repeats too often** (G3/G6 — likely looping without progress) or the **session's total tool calls exceed a budget** (G2 — runaway). It self-gates on this recipe being installed, is fail-open (never blocks a tool call on error), and honors `CONDUCTOR_SKIP_LOOP_GUARD=1`, `CONDUCTOR_LOOP_REPEAT_MAX` (default 5), `CONDUCTOR_LOOP_BUDGET` (default 120), `CONDUCTOR_LOOP_COOLDOWN_SECONDS` (default 120).
- **Cursor / Copilot / Gemini / Codex / Windsurf** — the hook is Claude-only (per `docs/DESIGN-DECISIONS.md` ADR-034/ADR-038). On these tools this recipe's rule text is the enforcement: follow G1–G6 by discipline (the loop shape + external-verify rule are tool-agnostic).

## Cross-References

- `quality-gates.md` §4 (verify-after-changes) — G5's external-verify rule is Q4 applied inside the loop.
- `meta-discipline.md` §3 (AMB) — G4's escalate-on-stall / ASK-when-stuck gate.
- `meta-discipline.md` §5.9 (output brevity) + §5.7 — G2's token budget shares the token-economy ceiling.
- `tdd.md` / `debugging.md` recipes — concrete instances of a G1–G6 loop (Red-Green; reproduce→root-cause→fix→regression).
- `self-improvement.md` recipe — the session-level Reflector loop is itself a G1–G6 instance (propose → human-verify → apply).
