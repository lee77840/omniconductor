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

- **Observe** — a stop-hook logs a trajectory pointer each session (Claude adapter); git history and `docs/CURRENT_WORK.md` are always-available fallbacks.
- **Reflect** — the `reflector` role reads the period's trajectories (success AND failure) and distils atomic lessons.
- **Propose** — the reflector appends `ADD/UPDATE/STALE` deltas to `docs/REFLECTION-PROPOSALS.md`. This is the ONLY output. Nothing is written to memory or rules.
- **Apply** — a human reviews the proposals like a diff and accepts/edits/rejects. On acceptance, the lesson becomes a `feedback_lesson-*.md` memory entry (see `core/memory-pattern/README.md`).

## Safety contract (read first)

- **Propose-only.** The reflector must never edit rules, memory, or code. Applying is a human decision.
- **Grounded-or-dropped.** Every proposed lesson cites a trajectory; un-cited lessons are discarded.
- **Delta, never rewrite.** Lessons are atomic items merged/pruned by a deterministic script, never by rewriting a whole file. This prevents "context collapse" (accumulated detail eroded by repeated full rewrites).

## Cadence

Run weekly (batch), or on demand via `/reflect`. To automate the weekly run, register the emitted `.conductor/reflect/run-weekly.sh` with a scheduler — see `.conductor/reflect/SCHEDULING.md` for per-tool instructions (OS cron/launchd is the universal local path). Reflection must not exceed the rule-file-edit budget in `core/anti-patterns/frequent-rule-file-edit.md` (more than 3 rule-file commits/week is itself a smell) — batch proposals, do not drip per-session edits.

## Trajectory sources (precedence)

1. Session transcript (richest) — via `.conductor/trajectories/index.jsonl`.
2. git history — universal.
3. Retro artifact — `docs/CURRENT_WORK.md`, `docs/sessions/*`.

## Per-tool automation

- **Claude**: the `stop-trajectory-log` hook records pointers; a scheduled run (Routines / Desktop Scheduled Task / cron → `claude -p`) invokes the reflector weekly; `.conductor/reflect/prune-lessons.sh` keeps the store bounded; `/reflect` runs it on demand.
- **Other tools**: the WHAT above is identical. Each adapter emits the trajectory hook, the native `/reflect` command, the reflector agent/rule, `.conductor/reflect/prune-lessons.sh`, and `.conductor/reflect/run-weekly.sh` + `reflect-brief.md` + `SCHEDULING.md`. Register `run-weekly.sh` with OS cron/launchd (or a native local scheduler where available) per `SCHEDULING.md`; the universal floor is running `/reflect` manually.

## Bounded store (deterministic prune)

`.conductor/reflect/prune-lessons.sh` (non-LLM) decays lessons unused for K weeks to `status: stale`, and marks-stale lessons whose provenance path no longer exists. It never deletes a lesson — only exact byte-duplicate files are removed (no information is lost). It is idempotent. This is the anti-collapse guarantee. (Non-destructive marking matches the propose-only philosophy: an unattended script must not destroy user memory.)

## Conductor Integration

**meta-discipline (M1 originality / M2 token economy)**: the reflector reads with ranges and map-then-reduce; proposals are original, grounded distillations, not copied text.

**operations (O1 real-time docs sync)**: accepted lessons and the proposals file are part of the project's documentation state.

## Cross-References

- `core/roles/reflector.md` — the actor this recipe drives.
- `core/memory-pattern/README.md` — the `feedback_lesson-*` file format proposals target.
- `core/anti-patterns/frequent-rule-file-edit.md` — the edit-budget guardrail.
