# Hookify Rule Templates (Claude Code adapter)

> Reusable hookify rule templates for Claude Code consumer projects. Hookify is a Claude Code plugin that intercepts events (Bash, file edits, prompts, stop) and injects warning/blocker messages based on YAML-frontmatter rules. These templates encode universal discipline patterns derived from production iteration in the originating reference project.

## What this directory contains

17 `.local.md.template` files. Each is a hookify rule with placeholders (`${CONDUCTOR_*}`) substituted at install time by `adapters/claude/transform.sh`. The output lands in the consumer project as `.claude/hookify.<name>.local.md`. Most are always-on; five are **recipe-scoped** (emitted only when their recipe is selected — see "Recipe-scoped templates" below).

> **Branch-strategy disclaimer (2026-05-09)**: Direct-push to protected branches is **not** a universal pattern. Trunk-based projects routinely push to `main`. Multi-stage projects (e.g., `develop → release → main`) protect `main`/`release`. Because of this, direct-push blocking ships as an **opt-in** template (`block-direct-push-protected-branch`, recipe-scoped to `branch-strategy`) rather than always-on — adopters who want it select the `branch-strategy` recipe, and trunk-based projects simply omit it. Force-push protection (below) **is** universal — even trunk projects rarely want history rewrites — so it remains always-on.

| Template | Event | Action | Universal trigger |
|---|---|---|---|
| `block-completion-claim-without-push` | stop | block | False completion claim before `git push` evidence |
| `block-force-push-protected-branch` | bash | block | `git push --force origin <protected-branch>` |
| `block-direct-push-protected-branch` | bash | block | Direct `git push` to a protected branch (recipe-scoped: branch-strategy) |
| `warn-current-work-without-remaining-tasks` | file | warn | CURRENT_WORK edited without REMAINING_TASKS sync |
| `warn-plan-spec-without-remaining-tasks` | file | warn | Plan/spec edited without cross-doc flip |
| `warn-on-gh-pr-merge` | bash | warn | `gh pr merge` triggers 4-spot status flip |
| `warn-stop-commit-without-current-work` | stop | warn | Session has commit but CURRENT_WORK not touched |
| `warn-commit-without-pre-commit-review` | bash | warn | `git commit` without Q1 pre-commit review evidence |
| `warn-gh-pr-create-without-pre-merge-review` | bash | warn | `gh pr create` triggers Q2 pre-merge review reminder |
| `warn-user-manual-completion` | prompt | warn | User reports manual completion → docs-sync trigger |
| `warn-any-type-added` | file | warn | TypeScript `: any` added (TS projects only) |
| `warn-console-direct` | file | warn | Direct `console.error/log/warn` in production code |
| `block-server-secret-in-client` | file | block | Server-only secret pattern added to a client-bundled file |
| `warn-create-table-without-access-control` | file | warn | `CREATE TABLE` in a `.sql` file with no row-level access control in the same change (recipe-scoped: database-discipline) |
| `warn-security-definer-without-search-path` | file | warn | `SECURITY DEFINER` function with no explicit `SET search_path` (recipe-scoped: database-discipline) |
| `warn-raw-hex-instead-of-token` | file | warn | Inline raw hex color added to a `.tsx`/`.jsx`/`.css`/`.scss` file instead of a design token (recipe-scoped: design-system) |
| `warn-hardcoded-text-without-i18n-key` | file | warn | Hardcoded user-facing string rendered in a component instead of a translation key (recipe-scoped: i18n) |

## Recipe-scoped templates

Most templates above are **always-on**: every install emits them. Five are **recipe-scoped** — they emit only when the matching recipe is passed via `--recipes`. The mapping lives in the `.recipe-scoped` file in this directory (basename → recipe):

```
warn-create-table-without-access-control.local.md  database-discipline
warn-security-definer-without-search-path.local.md  database-discipline
warn-raw-hex-instead-of-token.local.md  design-system
warn-hardcoded-text-without-i18n-key.local.md  i18n
block-direct-push-protected-branch.local.md  branch-strategy
```

The SQL rules above are stack-shaped (they only make sense for projects with a relational store), so shipping them always-on would inject SQL-specific noise into projects that have no SQL. The same logic applies to the UI-shaped rules: `warn-raw-hex-instead-of-token` only matters where a design-token system exists, and `warn-hardcoded-text-without-i18n-key` only matters on multi-locale projects. Gating each behind its recipe (`design-system`, `i18n`) keeps the always-on set vendor- and stack-neutral while still letting stack-shaped rules ship opt-in.

`transform.sh` Step 4.5 consults `.recipe-scoped`: a listed template is skipped unless its recipe is in `--recipes`; a template NOT listed is always emitted. Lines beginning with `#` are comments. See `docs/DESIGN-DECISIONS.md` ADR-028.

## Placeholder reference

These tokens are substituted by `transform.sh` `substitute_template()`:

| Placeholder | Default | Override |
|---|---|---|
| `${CONDUCTOR_PROTECTED_BRANCHES}` | `main\|release` | env `CONDUCTOR_PROTECTED_BRANCHES` (alternation regex) |
| `${CONDUCTOR_CURRENT_WORK_PATH}` | `docs/CURRENT_WORK.md` | env `CONDUCTOR_CURRENT_WORK_PATH` |
| `${CONDUCTOR_REMAINING_TASKS_PATH}` | `docs/REMAINING_TASKS.md` | env `CONDUCTOR_REMAINING_TASKS_PATH` |
| `${CONDUCTOR_SOURCE_GLOB}` | `apps/.*\\.(ts\|tsx)$` | env `CONDUCTOR_SOURCE_GLOB` |
| `${CONDUCTOR_CLIENT_GLOB}` | `(src/(components\|hooks\|pages\|ui)\|public)/.*\\.(ts\|tsx\|js\|jsx)$` | env `CONDUCTOR_CLIENT_GLOB` (client-bundled paths; lookahead-free) |
| `${CONDUCTOR_SERVER_SECRET_PATTERN}` | `(SERVICE_ROLE_KEY\|SERVICE_ROLE\|_SECRET_KEY\|_PRIVATE_KEY\|ADMIN_API_KEY\|SECRET_ACCESS_KEY)` | env `CONDUCTOR_SERVER_SECRET_PATTERN` (generic credential env-var name shapes, not a vendor reference) |
| `${CONDUCTOR_PROJECT_NAME}` | `your-project` | env `CONDUCTOR_PROJECT_NAME` |

If an adopter project doesn't use a particular convention (e.g., no `docs/REMAINING_TASKS.md`), the relevant rule body should be edited or the file deleted post-install. Templates are scaffolding, not enforcement.

## Install / update

Run via the Claude adapter:

```bash
bash adapters/claude/transform.sh <target-project> [--recipes=...]
```

Step 4.5 of the pipeline copies these templates to `<target>/.claude/hookify.<name>.local.md` with placeholders substituted. Existing files in `<target>/.claude/hookify.*` are NOT overwritten — adopter customizations win.

## Adopting / removing individual rules

After install, every emitted file has `enabled: true` in frontmatter. To disable a rule without deleting it, flip to `enabled: false`. To delete entirely, remove the file. Adopters MAY add their own `hookify.<custom-name>.local.md` — the framework-emitted templates are namespaced clearly enough to coexist (no collisions expected, but check before adding).

## Why hookify-only (no Cursor / Copilot equivalent)

Hookify is a Claude Code plugin. Cursor uses MDC files with separate semantics. Copilot uses repository instructions without runtime intercept. If those tools add comparable runtime hook plugins, equivalent templates land under their respective adapter (`adapters/cursor/`, `adapters/copilot/`).

## Originating reference project

Patterns abstracted from production iteration. Each template body cites the universal rule it enforces (`workflow.md`, `quality-gates.md`, `spec-as-you-go.md`) — NOT vendor-specific stack rules. Vendor-specific rules (database row-level-security policies, transactional-email header conventions, UI-library / icon-pack banlists, design-token enforcement, multi-platform parity) are intentionally out of scope: they belong in the adopter project as project-local hookify files, not in framework templates.

**Refinement (ADR-027)**: the original port boundary (ADR-018) placed "service-role key in client" entirely out of scope as a vendor-specific literal. That boundary is now refined. The *vendor literal* (a specific key name) stays project-local — but the *generalized server-secret-leak pattern* (any server-only credential-shaped name appearing in a client-bundled path) is a universal security hazard, not a stack specific. It now ships as `block-server-secret-in-client` with overridable `${CONDUCTOR_CLIENT_GLOB}` and `${CONDUCTOR_SERVER_SECRET_PATTERN}` placeholders (the latter defaults to generic credential env-var name shapes, never a vendor product name). See ADR-027.

## Related

- `adapters/claude/transform.sh` — installer
- `adapters/claude/SUPPORTED-FEATURES.md` — Claude adapter feature matrix
- `core/universal-rules/workflow.md`, `quality-gates.md`, `spec-as-you-go.md` — the rule bodies these templates enforce
- `docs/DESIGN-DECISIONS.md` ADR-018 — port boundary decision
- `docs/DESIGN-DECISIONS.md` ADR-027 — generalized server-secret-leak pattern carved back in (refines ADR-018)
