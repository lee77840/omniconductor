# `core/roles/` — 8 universal roles + 1 opt-in (reflector)

Per ADR-013/045/049, CONDUCTOR ships 8 universal role definitions; per ADR-030 it also ships one opt-in role, `reflector`, emitted only with the `self-improvement` recipe. `reviewer` is the pre-implementation plan/design gate; `code-reviewer` is the independent post-implementation correctness gate; `utility` is the bounded Tier 3 execution path. Each adapter compiles roles only when its project-scoped native agent format is verified; otherwise the primary rule text remains an explicit fallback.

## The roles (8 universal + `reflector`, opt-in)

| Role | Purpose | Required difficulty |
|---|---|---|
| `planner` | Architecture, gap analysis, ADRs, trade-off decisions. No code. | Tier 1 — conceptual / complex |
| `builder` | Multi-file or cross-cutting code implementation (3+ files). | Tier 1 — conceptual / complex |
| `reviewer` | Plan validation before implementation begins. Read-only. | Tier 1 — conceptual / complex |
| `code-reviewer` | Post-implementation correctness, security, regression, and test review. Read-only. | Tier 1 — conceptual / complex |
| `helper` | Single-file or 1-2-file work where the pattern is established. | Tier 2 — routine |
| `designer` | UI / UX work. Visual components, design tokens. | Tier 2 — routine |
| `scribe` | Documentation sync after implementation. No code. | Tier 2 — routine |
| `utility` | Direct lookup, one-file rename, or trivial text edit; returns for reclassification if scope grows. | Tier 3 — trivial |
| `reflector` *(opt-in)* | Reads session trajectories; proposes atomic lesson deltas for human approval. No code, no auto-apply. Shipped only with the `self-improvement` recipe (ADR-030). | Tier 1 — conceptual / complex |

Project-specific roles (e.g., a translator role for multi-locale work, a mailer role for transactional email) live in `core/recipes/` and are opt-in.

## Frontmatter convention (CONDUCTOR schema)

Every role file uses the same frontmatter:

```yaml
---
role: builder
purpose: "Multi-file or cross-cutting code implementation"
difficulty_tier: 1
must_do:
  - read AGENT.md (project rules)
  - update specs/*.md in same turn
  - run quality gates per quality-gates.md
must_not_do:
  - design decisions without planner consult
  - merge to protected branches
output_format: "code edits + spec updates + verification log"
stop_condition: "all touched files saved + specs synced + quality gates green"
---
```

## Dispatch contract

The orchestrator dispatches a role with a dispatch brief (≤ 2K tokens). The brief MUST include:

1. **Objective** — one sentence.
2. **Files to read** — absolute paths.
3. **Constraints** — `must_do` + `must_not_do` (extends the role's frontmatter, doesn't replace).
4. **Output** — expected file paths and format.
5. **Stop condition** — single criterion that determines done.

See `docs/HOW-IT-WORKS-PER-TOOL.md` for the per-tool dispatch mechanism. On Single-Agent-Mode tools, the brief becomes a section header inside the human's chat message rather than a separate dispatch.

`difficulty_tier` is the portable contract. Adapters translate it into their own
native controls using the project-saved Tier mapping (model-family/semantic alias,
exact native model, reasoning effort, or an honestly advisory session selector);
role sources never name a vendor model.

## Flat-with-leader topology

Roles do NOT dispatch each other. Multi-step work returns intermediate results to the orchestrator, which decides the next dispatch. Full rationale in `universal-rules/meta-discipline.md` section 7.

## Per-tool transformation

| Adapter | Output |
|---|---|
| Claude | `.claude/agents/<role>.md` with native frontmatter (`name`, `description`, `model`). |
| Codex | `.codex/agents/<role>.toml` with sandbox and reasoning-effort profiles. |
| Cursor / Copilot / Gemini | Native project agent files when emitted by that adapter; otherwise role-text fallback is stated explicitly. |
| Windsurf | Rule/workflow fallback until a stable project-scoped custom-agent contract is verified. |
