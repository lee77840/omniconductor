---
recipe_id: auto-mock-data
recipe_name: "Auto-generate mock seed data on schema change"
applies_when: "project has a relational database and wants seed data autogen"
severity: STRONG (when installed)
linked_rules:
  - spec-as-you-go
---

# Recipe — Auto Mock Data

> Opt-in recipe. Install when the project has a relational database (Postgres, MySQL, SQLite, etc.) and wants seed data automatically generated whenever the schema changes. Do NOT install on document-store-only projects.

## 1. The rule

Whenever a database table is created, modified, or removed, the corresponding mock seed SQL (or seed script) MUST be generated or updated in the SAME turn as the schema change.

### 1.1 Why same-turn

The orchestrator that just finished the migration has the table's column types, constraints, and example values fresh in mind. By the next session, that context is gone. Seed data generated later is generic and misses the realistic data shapes that the migration was actually for.

### 1.2 What "mock seed" means

- A SQL file (or seed script) that inserts representative rows for the new / changed table.
- "Representative" = covers the access patterns the application code will use:
  - Edge cases (null values where allowed, empty strings, max-length strings).
  - Realistic values (not "lorem ipsum" — actual data shapes the dev / staging environment needs).
  - Foreign-key relationships intact (seed parent rows before child rows).

## 2. File organization

```
db/
├── migrations/
│   ├── 20260506_add_foo_table.sql
│   └── 20260507_alter_bar_column.sql
├── seeds/
│   ├── foo.seed.sql
│   └── bar.seed.sql
└── README.md
```

Or whatever convention the project's ORM / migration tool prefers. The recipe is "seed updates land alongside schema updates", not a specific tool.

## 3. The "no manual ask" sub-rule

The orchestrator does NOT ask "should I add seed data?" after a migration. Seed data is a default deliverable of any schema change. The dispatch brief for a database change MUST include "and update seed data" without the user requesting it.

This is the recipe's central discipline: seed data autogen is automatic, not opt-in per change.

## 4. Seed quality requirements

| Requirement | Why |
|---|---|
| At least 3 rows per new table | Single-row seeds don't exercise list / pagination paths |
| Foreign keys intact | Broken references defeat the seed |
| Mix of edge cases (nulls, empty strings, max lengths) | Catches column constraint mistakes |
| Realistic values (not placeholder "test1", "test2") | Dev environment should look like prod, just smaller |
| Idempotent inserts (`INSERT ... ON CONFLICT DO NOTHING` or equivalent) | Safe to re-run during dev environment resets |

## 5. When schema is removed

When a table or column is dropped:

- Remove the corresponding seed entries.
- Remove dependent seeds in other tables (foreign-key cleanup).
- Document the removal in the migration's commit message.

## 6. Production case

Documented case: a new table was added without seed updates. The dev environment had the table empty. UI code that read the table with an `expects-non-empty` assumption crashed when developers tried to render the new feature locally. The seed update would have caught this immediately.

## 7. Cross-tool enforcement

| Mechanism | Where |
|---|---|
| Spec-as-you-go (universal) | Same-turn doc + seed update enforced by `spec-as-you-go.md` |
| Migration script template | Project's migration tool template includes a "seed updated?" checkbox in commit message |
| Pre-commit review (Q1) | Reviewer checklist: "DB schema changed → seed updated?" |
| Rule text | This recipe loaded into the tool's rule context |

The recipe does not add a new automated check; it adds a discipline that the existing checks (spec-as-you-go, Q1) catch when followed.
