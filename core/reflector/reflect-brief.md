Run the CONDUCTOR Reflector over recent sessions — **propose-only, apply nothing.**

Adopt the reflector persona for this task (the reflector agent/rule installed alongside this command defines it). Then:

1. Read `.conductor/trajectories/index.jsonl` and follow each `transcript` pointer it names; read `git log --oneline -30` and the diffs of referenced commits; read `docs/CURRENT_WORK.md`.
2. Distil atomic lessons from BOTH successes and failures (prefer a failure→later-success contrast). Every lesson MUST cite provenance (a session id, commit, or retro line); drop any lesson you cannot ground.
3. Append each lesson as an `ADD`/`UPDATE`/`STALE` delta to `docs/REFLECTION-PROPOSALS.md` in this format:
   - `**[ADD]** target: feedback_lesson-<slug>.md` — lesson / why / how-to-apply / provenance.
4. Apply NOTHING else. Do not edit rules, memory, or code. Stop after writing proposals.

After you finish, remind the user to review `docs/REFLECTION-PROPOSALS.md` and, for accepted deltas, add them as `feedback_lesson-*.md` memory entries, then optionally run `.conductor/reflect/prune-lessons.sh` on the memory dir.
