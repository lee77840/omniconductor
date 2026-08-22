# `core/recipes/` — Policy-classified project patterns

ADR-073 amends the original all-opt-in model from ADR-013. Recipes are classified
instead of asking 17 independent questions:

- `debugging` and `loop-engineering` are safe automatic defaults on a fresh
  full/strict install;
- stack-shaped recipes are detected and recommended once as a group;
- permission-, data-, Git-, or database-impacting recipes require explicit consent;
- updates preserve the existing per-adapter selection;
- an explicit `--recipes=` value is exact and overrides onboarding.

## The 17 recipes

| File | When to install |
|---|---|
| `web-mobile-parity.md` | Project has both web and mobile surfaces sharing business logic |
| `i18n.md` | Project supports multiple locales |
| `monorepo.md` | Project uses npm workspaces (or equivalent) with shared packages |
| `branch-strategy.md` | Project uses a 3-branch model (or wants the example pattern) |
| `auto-mock-data.md` | Project has a database and wants seed data autogen on schema change |
| `coding-conventions.md` | Project wants explicit naming / TS / error-handling conventions enforced |
| `tdd.md` | Project has a test framework and wants Red-Green-Refactor methodology enforced across feature work and bug fixes |
| `non-vacuous-testing.md` | Tests or gates must prove they detect the named defect, not merely return green |
| `debugging.md` | Any project — enforces root-cause-first investigation before any fix is attempted |
| `database-discipline.md` | Project has a relational store with migrations + dev/prod split. Ships 2 recipe-scoped hookify rules (SQL access-control + SECURITY DEFINER search_path) — see ADR-028 |
| `database-change-assurance.md` | Project performs high-risk production/bulk/destructive DB changes and needs approval, impact, postcondition, and rollback evidence |
| `design-system.md` | Project maintains a design-token system (color/spacing/typography tokens). Ships 1 recipe-scoped hookify rule (raw-hex-instead-of-token) — see ADR-028 |
| `visual-baseline-integrity.md` | Screenshot or rendered-output baselines are release/regression evidence |
| `release-provenance.md` | Release contains third-party, regulated, external, or policy-bound material requiring provenance evidence |
| `self-improvement.md` | Project wants a periodic, human-approved Reflector that distils session lessons into memory/rules. Propose-only; nothing auto-applies. Drives the `reflector` role — see ADR-030 |
| `git-hygiene.md` | Any git project — esp. repos worked by multiple sessions/agents or with protected branches. Shared-repo discipline (no orphan worktrees, push-don't-hoard, merge=delete-branch, backup≠applied). Claude/Codex add a verified Stop reminder; other adapters install the checklist — ADR-037 as amended by ADR-045 |
| `loop-engineering.md` | Any agentic loop (generate→verify→fix→re-verify, test-fix, multi-step). Bounded, externally-verified loops: explicit done-criterion, iteration+token budget, require-progress, escalate-on-stall, verify-externally-not-self-judgment, oscillation guard. Claude/Codex add verified `PreToolUse` reminders; other adapters install the rule text — ADR-038 as amended by ADR-045 |

## Selection patterns

| Project type | Recommended recipes |
|---|---|
| Solo SaaS, web-only, single-locale | `coding-conventions` + `tdd` + `debugging` |
| SaaS with mobile companion | `web-mobile-parity` + `coding-conventions` + `tdd` + `debugging` |
| Multi-locale SaaS | `i18n` + `coding-conventions` + `tdd` + `debugging` |
| Relational-DB-backed SaaS (migrations + dev/prod) | `database-discipline` + `coding-conventions` + `tdd` + `debugging` |
| Token-driven design system (theming / dark-mode) | `design-system` + `coding-conventions` + `tdd` + `debugging` |
| Full-stack SaaS with web + mobile + i18n | Select all relevant recipes; do not install DB/visual/provenance assurance without matching gates |
| High-risk DB release | `database-discipline` + `database-change-assurance` |
| Release-grade test evidence | `tdd` + `non-vacuous-testing`; add `visual-baseline-integrity` for screenshot gates |
| Third-party or policy-bound release material | `release-provenance` plus adopter-owned domain policy |
| Any git repo, esp. shared / multi-session | add `git-hygiene` to any of the above |
| Agentic / iterative loops (fix-verify, test-fix) | add `loop-engineering` to any of the above |
| Greenfield experiment | Automatic `debugging` + `loop-engineering` only |

## How adapters consume these files

Adapter `transform.sh` accepts a `--recipes=<comma-separated-list>` flag (or per-tool equivalent). Selected recipes are written to:

| Adapter | Output path |
|---|---|
| Claude | `.claude/rules/<recipe>.md` (with `paths:` frontmatter where the recipe ships its own path scope) |
| Cursor | `.cursor/rules/<recipe>.mdc` |
| Copilot | `.github/instructions/<recipe>.instructions.md` |
| Gemini | Section in `GEMINI.md` |
| Codex | Section in `AGENTS.md` |
| Windsurf | Full: `.devin/conductor/recipes/<recipe>.md`; à-la-carte: compact `.devin/rules/<recipe>.md` pointer |
| OpenCode | `.opencode/rules/<recipe>.md` |

Recipes are layered on TOP of universal-rules. They never override; they extend.
