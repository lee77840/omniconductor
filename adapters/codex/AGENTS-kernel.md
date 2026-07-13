# AGENTS.md — CONDUCTOR runtime kernel (Codex adapter)

> This is the compact, always-loaded CONDUCTOR kernel. It deliberately stays below
> Codex's default project-instruction budget so the end of this file remains model-visible.
> Complete rule and recipe text is installed under `.codex/conductor/` and must be
> opened when the routing table below says it applies.

## Runtime boundary

- `AGENTS.md` is always loaded and contains the non-negotiable execution contract.
- `.codex/conductor/rules/*.md` contains the complete universal rules. These files are
  references, not automatically loaded instructions.
- `.codex/conductor/recipes/*.md` contains selected opt-in recipes. Read a selected
  recipe before performing work in its domain.
- `.codex/agents/*.toml` contains native planner, builder, reviewer, code-reviewer,
  helper, designer, scribe, and Tier 3 utility roles.
- `.codex/hooks.json` contains only verified Codex `PreToolUse` and `Stop` contracts.
  Run `/hooks`, inspect the definitions, and explicitly trust them after installation
  or modification.

Hooks are deterministic guardrails, not a security boundary. They do not intercept
every equivalent tool path. This adapter never emits Claude-only `Agent`/`Read`
matchers or the unsupported Codex `permissionDecision: "ask"` response.

## Non-negotiable execution contract

1. **Establish state first.** Before non-trivial work, read `docs/CURRENT_WORK.md`.
   Confirm the active task, branch, base SHA, last verified HEAD, blockers, and next action.
2. **Plan before implementation.** For medium or larger changes, record scope, affected
   files, architecture fit, risks, ordered tasks, and stop conditions before editing.
3. **Keep code, tests, and documentation synchronized.** Changed behavior requires its
   tests and relevant specs in the same work cycle. Do not defer documentation cleanup.
4. **Separate design review from code review.** `reviewer` checks plans and architecture
   before implementation. `code-reviewer` checks the resulting diff for correctness,
   security, regressions, and missing tests before completion.
5. **Verify before claiming completion.** Run the relevant syntax, unit, integration,
   functional, build, or runtime checks. A green build alone is not proof that the
   requested behavior exists; inspect the diff and observe the intended outcome.
6. **Preserve user work.** Never overwrite user-owned configuration or modified managed
   files silently. Never use destructive Git operations without explicit authorization.
7. **Keep session state durable.** Update `docs/CURRENT_WORK.md` when work, branch state,
   blockers, decisions, or verification evidence changes. Remove completed items from
   active lists and retain only concise recent history.
8. **Resolve material ambiguity explicitly.** Ask when a choice changes product behavior,
   data, security, public API, irreversible state, or task scope. For safe local details,
   act with a stated assumption.
9. **Use role and model effort deliberately.** Keep planning, implementation, and review
   responsibilities separate. Use higher reasoning effort for architecture and review;
   use focused lower-cost roles only for bounded work.
10. **Treat external or sub-agent completion as a claim.** Inspect concrete changes and
    verification output before relaying success.

No request to be fast, brief, or to “just do it” waives these rules.

## Rule loading table

Read the listed complete rule before the matching activity. For cross-cutting work,
read every applicable file.

| Activity | Required reference |
|---|---|
| Planning, task decomposition, implementation order | `.codex/conductor/rules/workflow.md` |
| Any behavior or configuration change | `.codex/conductor/rules/spec-as-you-go.md` |
| Testing, review, verification, completion claims | `.codex/conductor/rules/quality-gates.md` |
| Session continuity, deployment or environment parity | `.codex/conductor/rules/operations.md` |
| Ambiguity, originality, routing, context discipline | `.codex/conductor/rules/meta-discipline.md` |

If a referenced file is missing, continue with this kernel and report that the CONDUCTOR
installation is incomplete; do not pretend the detailed rule was loaded.

## Workflow phases

Use the smallest workflow that preserves the contract:

| Scope | Required phases |
|---|---|
| Trivial | Implement → inspect → verify |
| Simple | Tasks → implement → review → verify → docs |
| Medium | Plan → tasks → implement → review → verify → docs |
| Large/system-shaping | Plan → architecture → tasks → implement → two-stage review → verify → docs |

- **Plan:** outcome, affected files, constraints, risks, stop conditions.
- **Architecture:** dependency direction, data flow, interfaces, and trade-offs.
- **Tasks:** independently verifiable increments in dependency order.
- **Implementation:** scoped code, tests, and same-cycle documentation.
- **Review:** pre-implementation design review, then post-implementation code review.
- **Verification:** execute relevant checks and observe the requested outcome.
- **Docs:** synchronize specs and current work with what actually happened.

## Native role routing

Before role dispatch, `.conductor/model-routing.json` must contain a Codex Tier
1/2/3 mapping. If it is absent, pause dispatch and ask the user to run
`npx omniconductor models configure --target=codex .`; do not invent or silently
downgrade a model. Generated agent files may require a new session before they
are visible.

CONDUCTOR difficulty is invariant across tools: Tier 1 = conceptual / complex,
Tier 2 = routine, Tier 3 = trivial. The complete, unchanged triggers are in
`.codex/conductor/rules/meta-discipline.md` section 6 and must be read before
classifying an ambiguous task. Codex agent profiles use the project-saved model
mapping and compile Tier 1/2/3 to high/medium/low reasoning effort. A model
release can require explicit revalidation, but never changes the task's Tier.

| Role | Responsibility | Default access |
|---|---|---|
| `planner` | Architecture, gaps, risks, task plan | read-only |
| `reviewer` | Pre-implementation plan/design review | read-only |
| `code-reviewer` | Post-implementation correctness/security/test review | read-only |
| `builder` | Primary cross-cutting implementation | workspace-write |
| `helper` | Bounded independent implementation | workspace-write |
| `designer` | UI/interaction work with design-system discipline | workspace-write |
| `scribe` | Specs, indexes, changelog, session state | workspace-write |
| `utility` | Direct lookup or trivial one-file edit; escalate if scope grows | workspace-write |

Do not use `reviewer` as a substitute for `code-reviewer`, or let the implementation
owner be the only reviewer of its own work.

## Project-local memory

Repository facts belong in tracked rules, specs, and code. If personal notes are needed,
use a gitignored `.memory/` directory with a short `MEMORY.md` index. Never store secrets,
duplicate code facts, or stale debugging recipes there. Verify a memory claim before use.
