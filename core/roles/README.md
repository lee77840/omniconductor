# `core/roles/` — 6 universal roles + 1 opt-in (reflector)

Per ADR-013, CONDUCTOR ships 6 universal role definitions; per ADR-030 it also ships one opt-in role, `reflector`, emitted only with the `self-improvement` recipe. Adapters that support sub-agent dispatch (Claude Code as of v0.2) compile these into native role files. Adapters without native sub-agent support (Cursor / Copilot / Gemini / Codex / Windsurf) operate in **Single-Agent Mode**: the orchestrator absorbs all roles, and the role files are read as discipline references rather than dispatched.

## The roles (6 universal + `reflector`, opt-in)

| Role | Purpose | Default model tier |
|---|---|---|
| `planner` | Architecture, gap analysis, ADRs, trade-off decisions. No code. | Opus |
| `builder` | Multi-file or cross-cutting code implementation (3+ files). | Opus |
| `reviewer` | Plan validation before implementation begins. Read-only. | Opus |
| `helper` | Single-file or 1-2-file work where the pattern is established. | Sonnet |
| `designer` | UI / UX work. Visual components, design tokens. | Sonnet |
| `scribe` | Documentation sync after implementation. No code. | Sonnet |
| `reflector` *(opt-in)* | Reads session trajectories; proposes atomic lesson deltas for human approval. No code, no auto-apply. Shipped only with the `self-improvement` recipe (ADR-030). | Opus |

Project-specific roles (e.g., a translator role for multi-locale work, a mailer role for transactional email) live in `core/recipes/` and are opt-in.

## Frontmatter convention (CONDUCTOR schema)

Every role file uses the same frontmatter:

```yaml
---
role: builder
purpose: "Multi-file or cross-cutting code implementation"
default_model: opus
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

## Flat-with-leader topology

Roles do NOT dispatch each other. Multi-step work returns intermediate results to the orchestrator, which decides the next dispatch. Full rationale in `universal-rules/meta-discipline.md` section 7.

## Per-tool transformation

| Adapter | Output |
|---|---|
| Claude | `.claude/agents/<role>.md` with native frontmatter (`name`, `description`, `model`). |
| Cursor / Copilot / Gemini / Codex / Windsurf | Role text concatenated into the tool's primary rule file under a "Roles" section. Single-Agent Mode: the operator reads role contracts as discipline reference. |
