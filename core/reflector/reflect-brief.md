Run the CONDUCTOR Reflector over recent sessions — **propose-only, apply nothing.**

Adopt the reflector persona for this task (the reflector agent/rule installed alongside this command defines it). Then:

1. For a manual run, select at most 12 sessions from the last 14 days in `.conductor/trajectories/index.jsonl`. Inspect only explicitly relevant, trusted transcript ranges, at most 32 KiB total evidence. If no index exists, use `git log --oneline -20` and the first 16 KiB of `docs/CURRENT_WORK.md` (or the project's root override). Do not read full histories or follow arbitrary hook-supplied paths. Scheduled bounded mode supplies evidence directly and overrides these discovery steps.
2. Distil atomic lessons from BOTH successes and failures (prefer a failure→later-success contrast). Every lesson MUST cite provenance (a session id, commit, or retro line); drop any lesson you cannot ground.
3. Emit one machine-readable proposal envelope to stdout. Do not write it to a
   file. Use this exact shape and no additional envelope:

```text
<conductor-reflection-proposals>
{"schema_version":1,"proposals":[{"op":"ADD|UPDATE|STALE","target":"feedback_lesson-<slug>.md","lesson":"...","why":"...","how_to_apply":"...","provenance":["session/commit/retro citation"]}]}
</conductor-reflection-proposals>
```

4. Apply NOTHING. Do not edit proposals, rules, memory, skills, configuration,
   or code. A trusted deterministic writer validates the envelope and is the
   only process allowed to append `docs/REFLECTION-PROPOSALS.md`.

If a repeated procedure is a stronger fit for a reusable skill, mention that in
the lesson text. Do not invoke `omniconductor skills propose`; skill proposal
creation remains a separate human-reviewed action.

After you finish, remind the user to review `docs/REFLECTION-PROPOSALS.md` and, for accepted deltas, add them as `feedback_lesson-*.md` memory entries, then optionally run `.conductor/reflect/prune-lessons.sh` on the memory dir.
Also list `.conductor/skill-proposals/` items and remind the user that `accept`
records a decision but never promotes a skill automatically.
