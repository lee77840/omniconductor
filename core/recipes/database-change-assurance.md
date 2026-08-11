---
recipe_id: database-change-assurance
recipe_name: "High-risk database change assurance — intent, approval, impact, rollback"
applies_when: "Project performs production, destructive, bulk, permission, or schema/data migration operations that require an auditable change envelope"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
  - operations
linked_recipes:
  - database-discipline
---

# Recipe — Database Change Assurance

> Opt-in strict profile layered on `database-discipline`. It governs high-risk writes;
> it does not require human approval for every local transaction or pretend one SQL
> dialect is universal. Projects define which environments and operation classes are
> protected before enabling this recipe.

## 1. Classify before writing

Before executing a protected operation, record one bounded change envelope:

- `action_id`, target environment, database identity, and operation class;
- **WHAT** changes, **WHY** it is needed, and **HOW** it will be applied;
- exact migration/script/content digest and current schema or data snapshot;
- expected row or object impact, including the stable keys in scope;
- preconditions, postconditions, rollback or forward-recovery procedure;
- whether approval is required and the direct human decision when it is.

Production, destructive, bulk, access-policy, credential, and irreversible operations
default to approval-required. A plan approval is not an execution approval when the
exact statement, target, snapshot, or expected impact has changed.

## 2. Prove the pre-state

Immediately before execution:

1. Query the rows, objects, or schema facts the change assumes.
2. Compare count, stable keys, and relevant values with the approved snapshot.
3. Verify every name-based lookup and referenced column/constraint exists with the
   expected type, nullability, and default where those properties affect safety.
4. Abort on drift, ambiguity, unavailable evidence, or a changed target. Do not
   silently widen the predicate to make the change apply.

Never place credentials, row contents, personal data, or full query results in the
change envelope. Record bounded counts, identifiers safe for the project, digests, and
artifact references instead.

## 3. Apply and assert

- Use a transaction when the engine and operation permit it.
- Capture actual affected-object or affected-row count using the database's verified
  mechanism. Compare it with the approved expectation before commit.
- Evaluate the declared postconditions in the same transaction when possible.
- On mismatch, roll back or stop at the documented safe boundary. Do not relabel a
  partial write as success.
- Re-read the bounded post-state and attach the observation to the exact change
  snapshot.

Database-specific mechanisms such as PostgreSQL diagnostics, migration dry-runs, or
schema catalogs are implementation examples, not portable guarantees. Use only a
mechanism verified for the project's database and migration tool.

## 4. Connected-impact audit

For schema, key, enum, access-policy, or canonical-data changes, inspect all direct
consumers before approval: migrations, generated types, queries, fixtures, jobs,
analytics, APIs, caches, and release/rollback procedures. Record intentional exclusions
instead of assuming an unsearched consumer does not exist.

## 5. Result semantics

Report the operation with the CONDUCTOR verification evidence statuses. Only concrete
pre-state, execution, and post-state evidence can be `passed`. Missing credentials,
unavailable production access, pending approval, or an unverified rollback is
`blocked`, `environment-limited`, or `verification-required` — never PASS.

This recipe does not grant database authority, reuse authority from a subagent or
external message, or replace the adopter's incident, privacy, retention, or legal
policies.
