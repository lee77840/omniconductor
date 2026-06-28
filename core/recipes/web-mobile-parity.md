---
recipe_id: web-mobile-parity
recipe_name: "Web ↔ Mobile feature and bug parity"
applies_when: "project has both web and mobile surfaces sharing user-facing features or business logic"
severity: ABSOLUTE (when installed)
linked_rules:
  - workflow
  - quality-gates
---

# Recipe — Web ↔ Mobile Parity

> Opt-in recipe. Install when the project has both web and mobile surfaces. Do NOT install on web-only or mobile-only projects.

## 1. Feature parity (P1)

Every user-facing feature MUST be developed for both web and mobile in the same iteration. Pair-development is the default; one-surface-only is an explicit exception that requires a written justification (a one-line note in CURRENT_WORK.md is sufficient).

### 1.1 Why pair-development

If web ships first, mobile parity gets deprioritized indefinitely. The originating project tracked this and found that "mobile follow-up" tasks aged out at a 60% rate within 3 months. Pairing eliminates the queue entirely.

### 1.2 Acceptable single-surface exceptions

- Admin features (web-only by policy — admins don't operate from mobile).
- Experimental features behind a feature flag (mobile waits for the flag to flip).
- Surface-specific hardware integrations (camera, biometrics — mobile only).
- Marketing pages (web only).

### 1.3 Pair-development workflow

For a feature touching user-facing flow:

1. Planner produces design with explicit web + mobile section.
2. Builder dispatch implements both surfaces in same logical task. (Mechanically may be 2 sub-tasks, but they share a single task ID.)
3. Tests cover both surfaces (web E2E + mobile E2E or equivalent).
4. Pre-commit review covers both diffs.
5. Spec update mentions both surfaces.

## 2. Bug-fix parity (P2 — ABSOLUTE)

When a bug is found on one surface, the orchestrator MUST verify whether the same bug exists on the other surface and fix BOTH in the same PR.

### 2.1 The half-fix anti-pattern

The single most-violated rule in the originating project's history. A bug was reported on web; the orchestrator fixed web; the user found the same bug on mobile two days later. This pattern repeated until the rule was promoted to ABSOLUTE.

### 2.2 Verification protocol

When a bug is reported:

1. Reproduce on the reported surface.
2. **Before fixing**: check whether the same bug exists on the other surface. (`grep` for the same logic, run the same scenario.)
3. If yes: fix both in the same PR.
4. If no: state explicitly in the commit message that the other surface was checked and found unaffected.

### 2.3 Why "before fixing"

Fixing on one surface first means the orchestrator's mental model is loaded with that surface's code. Switching contexts to the other surface afterward is harder; the rule treats both surfaces as the same diagnostic context.

## 3. Code organization to support parity

| Pattern | Rationale |
|---|---|
| Shared business logic in a shared package (e.g., `packages/shared`) | Single source of truth → no drift. |
| Shared types and constants in shared package | Type drift between surfaces is the worst kind. |
| Surface-specific UI in `<web-app>/` and `<mobile-app>/` | Surfaces have different UI primitives; that's correct. |
| Translation source-of-truth in shared package, with per-app local copies kept in sync | Web build doesn't depend on shared package import resolution at runtime; the local copy is the runtime artifact. |

The `recipes/monorepo.md` recipe describes the npm-workspaces structure that makes this organization practical.

## 4. Test coverage parity

If a flow has a web E2E test, the mobile equivalent flow MUST have a mobile E2E test (or documented reason why not — typically "mobile uses native components that web E2E doesn't exercise").

The `recipes/i18n.md` recipe handles the translation-key parity concern (8-locale or N-locale sync between web and mobile).

## 5. Cross-tool enforcement

| Mechanism | Enforcement |
|---|---|
| Shared package import structure | TypeScript compiler at build time |
| E2E test coverage | CI test runner |
| Bug-fix parity | Rule text + pre-commit review (Q1) prompts |
| Pair-development | Planner gate + reviewer checklist |

This recipe has no automated cross-surface check beyond rule text. The reviewer role is the final gate that catches single-surface PRs that should have been pair-developed.
