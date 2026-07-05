# `core/recipes/` — Project-specific opt-in patterns

Per ADR-013, CONDUCTOR ships project-specific recipes as OPT-IN. They are not loaded by default. Adopters select the recipes that match their project and the adapter wires them into the appropriate native location.

## The 11 recipes

| File | When to install |
|---|---|
| `web-mobile-parity.md` | Project has both web and mobile surfaces sharing business logic |
| `i18n.md` | Project supports multiple locales |
| `monorepo.md` | Project uses npm workspaces (or equivalent) with shared packages |
| `branch-strategy.md` | Project uses a 3-branch model (or wants the example pattern) |
| `auto-mock-data.md` | Project has a database and wants seed data autogen on schema change |
| `coding-conventions.md` | Project wants explicit naming / TS / error-handling conventions enforced |
| `tdd.md` | Project has a test framework and wants Red-Green-Refactor methodology enforced across feature work and bug fixes |
| `debugging.md` | Any project — enforces root-cause-first investigation before any fix is attempted |
| `database-discipline.md` | Project has a relational store with migrations + dev/prod split. Ships 2 recipe-scoped hookify rules (SQL access-control + SECURITY DEFINER search_path) — see ADR-028 |
| `design-system.md` | Project maintains a design-token system (color/spacing/typography tokens). Ships 1 recipe-scoped hookify rule (raw-hex-instead-of-token) — see ADR-028 |
| `self-improvement.md` | Project wants a periodic, human-approved Reflector that distils session lessons into memory/rules. Propose-only; nothing auto-applies. Drives the `reflector` role — see ADR-030 |

## Selection patterns

| Project type | Recommended recipes |
|---|---|
| Solo SaaS, web-only, single-locale | `coding-conventions` + `tdd` + `debugging` |
| SaaS with mobile companion | `web-mobile-parity` + `coding-conventions` + `tdd` + `debugging` |
| Multi-locale SaaS | `i18n` + `coding-conventions` + `tdd` + `debugging` |
| Relational-DB-backed SaaS (migrations + dev/prod) | `database-discipline` + `coding-conventions` + `tdd` + `debugging` |
| Token-driven design system (theming / dark-mode) | `design-system` + `coding-conventions` + `tdd` + `debugging` |
| Full-stack SaaS with web + mobile + i18n | All 11 |
| Greenfield experiment | None — universal-rules + roles only is enough |

## How adapters consume these files

Adapter `transform.sh` accepts a `--recipes=<comma-separated-list>` flag (or per-tool equivalent). Selected recipes are written to:

| Adapter | Output path |
|---|---|
| Claude | `.claude/rules/<recipe>.md` (with `paths:` frontmatter where the recipe ships its own path scope) |
| Cursor | `.cursor/rules/<recipe>.mdc` |
| Copilot | `.github/instructions/<recipe>.instructions.md` |
| Gemini | Section in `GEMINI.md` |
| Codex | Section in `.codex/codex.md` |
| Windsurf | `.windsurf/rules/<recipe>.md` |

Recipes are layered on TOP of universal-rules. They never override; they extend.
