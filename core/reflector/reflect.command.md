---
description: Run the CONDUCTOR Reflector — read recent trajectories and propose lesson deltas (propose-only).
---

Dispatch the `reflector` role (Tier 1 — conceptual / complex) with this brief:

- **Objective**: read the recent session trajectories and propose atomic lesson deltas. Apply nothing.
- **Files to read**: `.conductor/trajectories/index.jsonl` (follow its `transcript` pointers), `git log --oneline -30` and diffs of referenced commits, `docs/CURRENT_WORK.md`.
- **Constraints**: propose-only; cite provenance on every lesson; emit `ADD/UPDATE/STALE` deltas only; respect the weekly rule-file-edit budget; read with ranges (map-then-reduce).
- **Output**: return the single typed proposal envelope from `.conductor/reflect/reflect-brief.md`. Do not let the model write files.
- **Reusable procedure note**: identify repeated procedures in the proposal text; creating a typed skill proposal is a separate human-reviewed action.
- **Stop condition**: typed envelope returned; nothing written or applied.

After the reflector returns, pipe only its exact envelope to the trusted writer:
`node .conductor/reflect/reflection-proposals.js`. Then remind the user: review
`docs/REFLECTION-PROPOSALS.md` and apply accepted deltas only through a separate
explicit change. Optionally run `.conductor/reflect/prune-lessons.sh`.
Review skill inbox items separately with `omniconductor skills list`; an accepted
item remains unapplied until a later reviewed implementation.
