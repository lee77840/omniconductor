---
description: Run the CONDUCTOR Reflector — read recent trajectories and propose lesson deltas (propose-only).
---

Dispatch the `reflector` role (Opus) with this brief:

- **Objective**: read the recent session trajectories and propose atomic lesson deltas. Apply nothing.
- **Files to read**: `.conductor/trajectories/index.jsonl` (follow its `transcript` pointers), `git log --oneline -30` and diffs of referenced commits, `docs/CURRENT_WORK.md`.
- **Constraints**: propose-only; cite provenance on every lesson; emit `ADD/UPDATE/STALE` deltas only; respect the weekly rule-file-edit budget; read with ranges (map-then-reduce).
- **Output**: append proposals to `docs/REFLECTION-PROPOSALS.md` in the format from `core/roles/reflector.md`.
- **Stop condition**: proposals appended; nothing applied.

After the reflector returns, remind the user: review `docs/REFLECTION-PROPOSALS.md` and, for each accepted delta, apply it as a `feedback_lesson-*.md` memory entry. Then optionally run `.conductor/reflect/prune-lessons.sh` on the memory dir to keep it bounded.
