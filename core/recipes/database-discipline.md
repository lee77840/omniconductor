---
recipe_id: database-discipline
recipe_name: "Relational DB discipline — access control, idempotent migrations, drift safety"
applies_when: "Project has a relational store with migrations and an environment split (dev/prod)"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
ships_hookify:
  - warn-create-table-without-access-control
  - warn-security-definer-without-search-path
---

# Recipe — Database Discipline

> Opt-in recipe. Install on projects backed by a relational store that uses migrations and runs a dev/prod environment split. It encodes four disciplines that prevent the most common (and highest-severity) data-layer failures: missing access control, non-idempotent migrations, brittle seeds, and silent production drift. Projects without a relational store skip this recipe.

## 1. Access control on every table

Every table enables row-level (or equivalent) access control. Access without an explicit policy is a security hole, not a convenience.

- Enable row-level access control on the table at creation time — never as a follow-up "we'll add it later" step.
- Every policy names the allowed role explicitly. A policy with no role, or a permissive / PUBLIC default, grants access to everyone.
- No table ships with a permissive default. If a row should be readable by a tier, name that tier in the policy.
- Read-only reference tables (lookup tables, enums-as-rows) may scope SELECT broadly, but they still enable access control — broad SELECT is a deliberate policy, not an absence of one.

## 2. Idempotent migrations

A migration must be safe to re-run. Re-application happens routinely — replays, partial failures, parallel environments — and a non-idempotent migration turns a retry into an outage.

- Create with guards: `CREATE … IF NOT EXISTS`.
- Alter with guards: `ADD COLUMN IF NOT EXISTS`, and equivalent existence checks for indexes / constraints.
- Insert with conflict handling: `ON CONFLICT DO NOTHING` (or an explicit upsert) for seed / lookup rows.
- Guard any data backfill so a second run is a no-op.

If running the migration twice would fail or double-write, it is not idempotent — fix it before it ships.

## 3. Seed by name-lookup, not hardcoded ID

Foreign-key seeds resolve their target by a stable natural key (a name, a slug, a code), never a literal ID.

- IDs differ across environments — an auto-generated primary key in dev is not the same value in prod. A hardcoded ID silently points at the wrong row (or nothing) in another environment.
- Resolve the target row by its natural key at seed time, then use the resolved ID. The natural key is the stable contract across environments; the ID is not.
- This keeps the same seed script correct in dev, staging, and prod without per-environment edits.

## 4. Pre-apply drift verification

Before applying a dev-verified schema or data change to production, verify that production's current state still matches the baseline the change was built against. Production drifts (hotfixes, manual edits, concurrent writes); applying a change blind can overwrite that drift.

- Re-query production's pre-state for the affected range (the rows / schema the change touches) immediately before applying.
- Diff it against the dev baseline: row count, the set of keys, and the pre-state values.
- On any drift → abort and surface the difference. Never overwrite a drifted production silently.
- Apply only when parity holds. After applying, verify the post-state matches the intended result.

The discipline is: dev verifies the change is correct; the pre-apply diff verifies production is still the world the change expects.

## 5. Shipped hookify (Claude adapter)

The Claude adapter ships two recipe-scoped hookify rules that install **only when this recipe is selected** (`--recipes=database-discipline`):

| Rule | Event | Action | Catches |
|---|---|---|---|
| `warn-create-table-without-access-control` | file | warn | A `CREATE TABLE` in a `.sql` file with no row-level access control enabled in the same change (section 1) |
| `warn-security-definer-without-search-path` | file | warn | A `SECURITY DEFINER` function with no explicit `SET search_path`, leaving it open to schema-shadowing privilege hijack |

These are stack-shaped (SQL-specific), so they are gated behind this recipe rather than shipped always-on. See the CONDUCTOR repo's `adapters/claude/hookify-templates/.recipe-scoped` and `docs/DESIGN-DECISIONS.md` ADR-028.
