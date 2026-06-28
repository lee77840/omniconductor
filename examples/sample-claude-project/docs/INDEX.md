# INDEX — `<your-project>` document map

> **What this is**: a single page that points to every other doc in `docs/`. Update when you add a doc.

> **Status (P0 placeholder)**: customize on first install. P1 will provide a more developed example.

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
| `architecture/<adr>.md` | Per-decision ADRs |

## Specs (per area)

| Doc | Area |
|---|---|
| `specs/_example.md` | Template — DO NOT edit; copy + rename |
| `specs/auth.md` | Authentication / authorization |
| `specs/billing.md` | Payment / subscription |
| `specs/email.md` | Email infrastructure |
| `specs/<area>.md` | (add per area) |

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
