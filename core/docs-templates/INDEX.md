# INDEX — `<your-project>` document map

> **What this is**: a single page that points to every other doc in `docs/`. Update when you add a doc.

> **Status (P0 placeholder)**: customize on first install. P1 will provide a more developed example.

## Canonical locations and project overrides

| Artifact class | Project path |
|---|---|
| Session state | `docs/CURRENT_WORK.md` |
| Active tasks | `docs/TASKS.md` |
| Strategic / phase roadmap | `docs/PLANS.md` |
| Implementation plans | `docs/plans/YYYY-MM-DD-<topic>.md` |
| Long-lived domain specs | `docs/specs/<area>.md` |
| Architecture overview | `docs/architecture/README.md` |
| Architecture decisions | `docs/architecture/NNNN-<topic>.md` |
| Research notes | `docs/research/YYYY-MM-DD-<topic>.md` |

This table is the explicit project override registry. Change a path here when this
project intentionally uses a different location. Existing files or plugin-created
folders that are not declared here do not override these paths; stop and ask before
following a conflicting precedent.

---

## Top-level docs

| Doc | Purpose | Read frequency |
|---|---|---|
| `CURRENT_WORK.md` | Session continuity | Every session |
| `REMAINING_TASKS.md` | Launch readiness dashboard | Per milestone |
| `PLANS.md` | Phase roadmap | Per quarter |
| `TASKS.md` | Active phase task tracker | Per task |
| `INDEX.md` | This file — document map | When adding new doc |

## Architecture

| Doc | Purpose |
|---|---|
| `architecture/README.md` | System architecture overview |
| `architecture/NNNN-<topic>.md` | Per-decision ADRs |

## Implementation plans

| Doc | Purpose |
|---|---|
| `plans/README.md` | Plan naming and lifecycle |
| `plans/YYYY-MM-DD-<topic>.md` | Reviewable implementation plan |

## Specs (per area)

| Doc | Area |
|---|---|
| `specs/_example.md` | Template — DO NOT edit; copy + rename |
| `specs/auth.md` | Authentication / authorization |
| `specs/billing.md` | Payment / subscription |
| `specs/email.md` | Email infrastructure |
| `specs/<area>.md` | (add per area) |

## Research

| Doc | Purpose |
|---|---|
| `research/README.md` | Research-source and naming policy |
| `research/YYYY-MM-DD-<topic>.md` | Time-stamped research note |

## Sessions (archive)

| Doc | Purpose |
|---|---|
| `sessions/<date>.md` | Archived `CURRENT_WORK.md` content when it grew too long |

## Reference / legal / compliance

| Doc | Purpose |
|---|---|
| `legal/<doc>.md` | Legal copy (privacy, terms, etc.) |
| `compliance/<doc>.md` | Audit / compliance notes |

---

## How to use

When you create a new doc under `docs/`, add a row to the appropriate table in this file. If the table doesn't exist, create it.

When a doc is archived or deleted, REMOVE its row (don't strikethrough — just delete).

This file is the LANDING PAGE for any new contributor. Keep it scannable in 30 seconds.
