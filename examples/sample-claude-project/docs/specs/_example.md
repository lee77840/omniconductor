---
area: <your-area>            # e.g., auth, billing, email
owner: <you-or-team>
status: draft|active|archived
last_synced: YYYY-MM-DD
api_routes:                  # list of API route paths owned by this area
  - /api/<your-area>/<route>
pages:                       # list of pages owned by this area
  - /<your-area>
components:                  # list of components owned by this area
  - <YourComponent>
services:                    # list of services owned by this area
  - <yourAreaService>
hooks:                       # list of hooks owned by this area
  - useYourArea
db_tables:                   # list of DB tables owned by this area
  - <table_name>
---

# Spec — `<your-area>` (PLACEHOLDER — copy + rename per area)

> **What this is**: single source-of-truth for everything in the `<your-area>` domain. Updated EVERY time code in this area changes (spec-as-you-go ABSOLUTE rule).

> **Status (P0 placeholder)**: copy this file, rename to your area, replace contents. P1 will provide a richer example.

---

## Overview

One paragraph: what is this area, what problem does it solve, what are the boundaries.

---

## User-facing flows

For each user flow:

### Flow: <flow name>

1. User does X.
2. System responds Y.
3. User sees Z.

**Edge cases**:
- What happens on error.
- What happens on empty state.
- What happens on permission denied.

---

## API

For each route:

### `<METHOD> /api/<your-area>/<route>`

- **Auth**: required / optional / none.
- **Body**: schema.
- **Response**: schema (Result pattern: `{ data: T; error: null } | { data: null; error: string }`).
- **Errors**: list of error codes + meanings.

---

## UI

For each page or major component:

### Page: `/<your-area>`

- **Layout**: brief description.
- **Components used**: list.
- **State**: what state the page manages.
- **Permissions**: who can access.

---

## Services

For each service function:

### `<yourAreaService>.<method>()`

- **Input**: parameters.
- **Output**: Result-pattern return.
- **Side effects**: DB writes, external API calls, etc.

---

## DB Schema

For each table:

### `<table_name>`

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| ... | ... | ... |

**Indexes**:
- ...

**RLS policies**:
- ...

---

## Known constraints / gotchas

- Limits, quotas, rate limits.
- Browser-specific behavior.
- Things future contributors must know.

---

## Recent changes

- YYYY-MM-DD: <what changed and why>.
- YYYY-MM-DD: ...

(Append-only; oldest at bottom; archive once it grows past 20 entries.)
