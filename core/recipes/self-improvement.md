---
recipe_id: self-improvement
recipe_name: "Self-Improvement (Reflector, propose-only)"
applies_when: "a project wants periodic, human-approved distillation of session lessons into its memory/rules"
severity: STRONG (when installed)
linked_rules:
  - meta-discipline
  - operations
---

# Recipe — Self-Improvement (Reflector)

> Opt-in recipe. Install when you want CONDUCTOR to periodically read your recent sessions and PROPOSE lessons for your memory/rules. It never applies anything automatically. Do NOT install if you do not want a retrospective step — there is no silent learning here by design.

## The loop

```
Observe → Reflect → Propose → (human GO) → Apply
```

- **Observe** — each adapter's verified lifecycle hook logs a trajectory pointer;
  git history and `docs/CURRENT_WORK.md` are always-available fallbacks.
- **Reflect** — the `reflector` role reads the period's trajectories (success AND failure) and distils atomic lessons.
- **Propose** — lesson deltas still go to `docs/REFLECTION-PROPOSALS.md`. A repeated reusable procedure may instead be submitted through the typed `.conductor/skill-proposals/` inbox with `omniconductor skills propose`. Both paths are proposal-only; nothing is written to live memory, rules, or skills.
- **Apply** — a human reviews the proposals like a diff and accepts/edits/rejects. On acceptance, the lesson becomes a `feedback_lesson-*.md` memory entry (see `core/memory-pattern/README.md`).

## Safety contract (read first)

- **Propose-only.** The reflector must never edit rules, memory, or code. Applying is a human decision.
- **Grounded-or-dropped.** Every proposed lesson cites a trajectory; un-cited lessons are discarded.
- **Delta, never rewrite.** Lessons are atomic items merged/pruned by a deterministic script, never by rewriting a whole file. This prevents "context collapse" (accumulated detail eroded by repeated full rewrites).
- **Skill proposals are typed and repeated.** A skill candidate needs at least two cited occurrences, ordered procedure steps, and a human `accept` or `reject` decision. Acceptance records intent only; promotion into a live skill is a separate reviewed change.

## Cadence

Run weekly (batch), or on demand via `/reflect`. To automate the weekly run, register the emitted `.conductor/reflect/run-weekly.sh` with a scheduler — see `.conductor/reflect/SCHEDULING.md` for per-tool instructions (OS cron/launchd is the universal local path). Reflection must not exceed the rule-file-edit budget in `core/anti-patterns/frequent-rule-file-edit.md` (more than 3 rule-file commits/week is itself a smell) — batch proposals, do not drip per-session edits.

## Trajectory sources (precedence)

1. Session transcript (richest) — via `.conductor/trajectories/index.jsonl`.
2. git history — universal.
3. Retro artifact — `docs/CURRENT_WORK.md`, `docs/sessions/*`.

## Per-tool automation

- **All seven adapters**: emit a native or portable `/reflect` entry point,
  reflector agent/workflow, deterministic pruning utility, runner, brief, and
  scheduling guide. The nearest verified lifecycle hook is added only when it can
  supply the required trajectory evidence. OpenCode remains manual/propose-only;
  Windsurf's response hook is not represented as identical to a Stop event.
- **Proposal skill**: all seven adapters emit `propose-skill` only with this recipe.
  Claude and OpenCode use their native skill roots; the other adapters share
  `.agents/skills`. Native
  capture/suggestion features may help collect evidence, but the CONDUCTOR inbox
  and human decision contract is identical.
- **Scheduling**: register `run-weekly.sh` with OS cron/launchd, or a verified native
  local scheduler where available, per `SCHEDULING.md`. Manual `/reflect` is the
  universal floor.

## Bounded store (deterministic prune)

`.conductor/reflect/prune-lessons.sh` (non-LLM) decays lessons unused for K weeks to `status: stale`, and marks-stale lessons whose provenance path no longer exists. It never deletes a lesson — only exact byte-duplicate files are removed (no information is lost). It is idempotent. This is the anti-collapse guarantee. (Non-destructive marking matches the propose-only philosophy: an unattended script must not destroy user memory.)

## Conductor Integration

**meta-discipline (M1 originality / M2 token economy)**: the reflector reads with ranges and map-then-reduce; proposals are original, grounded distillations, not copied text.

**operations (O1 real-time docs sync)**: accepted lessons and the proposals file are part of the project's documentation state.

## Cross-References

- `core/roles/reflector.md` — the actor this recipe drives.
- `core/memory-pattern/README.md` — the `feedback_lesson-*` file format proposals target.
- `core/anti-patterns/frequent-rule-file-edit.md` — the edit-budget guardrail.
