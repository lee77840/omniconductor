---
name: plan-change
description: Inspect an existing project and produce an implementation-ready change plan. Use when a request needs scoping, repository-grounded sequencing, risk analysis, acceptance criteria, or a handoff before implementation begins.
---

# Plan Change

Create a plan that another engineer can execute without rediscovering the project.
Keep planning separate from implementation.

## Establish the contract

1. Restate the requested outcome in concrete terms.
2. Identify explicit non-goals, preserved behavior, and compatibility constraints.
3. Read the project instructions, current-work notes, handoff material, and relevant
   design decisions before proposing changes.
4. Inspect the current implementation, tests, generated artifacts, and working-tree
   state. Treat repository evidence as authoritative.
5. Surface only decisions that materially change scope. Make safe, reversible
   assumptions explicit.

Do not redefine project difficulty tiers, routing policy, roles, or other saved
contracts. Refer to them by their repository-defined names.

## Trace the change

Follow the behavior from its source through every consumer:

- canonical configuration or source data;
- shared logic and public interfaces;
- platform-specific or integration-specific compilation;
- validation and failure behavior;
- documentation and generated output;
- packaging, installation, upgrade, and removal paths.

Search for duplicated claims and derived artifacts. Record which files are canonical
and which must be regenerated. Account for existing uncommitted work without claiming
ownership of unrelated changes.

## Define the implementation slices

Order the work by dependency and risk. For each slice, specify:

- the observable outcome;
- files or components likely to change;
- invariants that must remain unchanged;
- collision, migration, rollback, and compatibility behavior;
- focused tests to add or update;
- broader gates that prove integration;
- documentation or decision records that must move with the code.

Prefer independently verifiable slices. Put shared contracts before adapters and
focused tests before broad suites.

## Set acceptance criteria

Write acceptance criteria as observable claims. Include success, failure, upgrade,
uninstall or rollback, and state-preservation cases when relevant. Name the evidence
required for completion, such as:

- exact emitted files or API responses;
- deterministic exit codes and diagnostics;
- byte-preservation or idempotence checks;
- focused regressions;
- full validation and packaging gates.

Do not treat a command exit alone as proof when the claim concerns resulting state.

## Produce the plan

Return:

1. scope and non-goals;
2. repository findings that shape the approach;
3. implementation slices in dependency order;
4. per-slice tests and acceptance criteria;
5. risks, open verification items, and rollback boundaries;
6. explicit completion gates.

Write the plan to the project's canonical plan location only when the request
authorizes a file change. Otherwise report it without mutating the project.
