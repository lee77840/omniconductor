---
name: propose-skill
description: Turn a repeated, evidenced procedure into a typed proposal for human review without applying it.
---

# Propose a Reusable Skill

Use this procedure only when the same useful workflow has been observed at least
twice and the `self-improvement` recipe is installed.

1. Gather bounded evidence. Record project-relative provenance paths, a short
   observation for each path, and the number of independent occurrences. Never
   copy credentials, transcript bodies, or private tool output into a proposal.
2. Write a proposal input JSON with `schema_version`, a kebab-case `name`, a
   concise `summary`, two or more ordered `procedure` steps, and an `evidence`
   array. The combined evidence occurrence count must be at least two.
3. Run `omniconductor skills propose <project> --from=<input.json>`. This writes
   only a pending item under `.conductor/skill-proposals/`; it does not create or
   edit a live skill.
4. Ask a human to inspect the proposal with `omniconductor skills list <project>`
   and record `accept` or `reject` with `omniconductor skills review`.
5. Stop after the decision is recorded. An accepted proposal is still not
   applied automatically; promotion into a project skill is a separate reviewed
   change.

Reject a candidate that is provider-specific without a portable fallback,
duplicates an existing skill, lacks cited evidence, or would require executable
payloads hidden inside the skill.
