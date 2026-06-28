# `core/docs-templates/` — Universal doc template skeletons

Tool-agnostic markdown templates that every CONDUCTOR-installed project gets at `docs/<file>.md`. The same files install regardless of which AI coding tool drives the project — adapters do NOT transform these (they are already universal).

## What lives here

| Template | Installed at | Purpose |
|---|---|---|
| `CURRENT_WORK.md` | `docs/CURRENT_WORK.md` | Session continuity. Always-load on session start. Lean (~150 lines max). |
| `REMAINING_TASKS.md` | `docs/REMAINING_TASKS.md` | Launch readiness dashboard / open scope. |
| `PLANS.md` | `docs/PLANS.md` | Long-term phase roadmap. |
| `TASKS.md` | `docs/TASKS.md` | Phase completion tracker. |
| `INDEX.md` | `docs/INDEX.md` | Document map — pointer to every other doc in `docs/`. |
| `specs/_example.md` | `docs/specs/_example.md` | Spec template. User renames + duplicates per area (e.g., `auth.md`, `billing.md`). |

## Why these are universal

- They are plain markdown.
- They reference no tool-specific syntax.
- The same workflow phase definitions reference them regardless of tool.
- The `Read first every session` instruction in adapter outputs always points to `docs/CURRENT_WORK.md`.

## Why they aren't transformed by adapters

Unlike `core/universal-rules/*` (which adapters re-emit with tool-specific front-matter), the doc templates are READ by every tool's chat session as plain markdown. No transformation needed.

The adapter's job is just to COPY them into the target project's `docs/` directory if they don't already exist (idempotent — never overwrite).

## Status (P0 foundation)

All template files are PLACEHOLDERS. P1 fills them with starter content sanitized from the reference adopter.

## Authoring guidance for P1

Each template should:
- Have a clear "What this is" header at the top.
- Use ATX headings.
- Include 1-2 example entries the user can immediately replace.
- Be SHORT (~30-100 lines). These are templates; the user grows them.
- Have NO project-specific names. Use generic placeholders (`<your-project>`, `<your-area>`).
