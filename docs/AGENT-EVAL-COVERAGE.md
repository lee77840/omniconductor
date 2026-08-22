# Agent Policy Assurance Coverage

> Generated from repository evidence. Do not hand-edit. A general adapter live
> probe does not upgrade a specific recipe, skill, or hook without exact evidence.

Levels: `—` unsupported · `I` instruction-only · `E` emit-verified ·
`N` native-contract-tested · `L` live-verified · `A` adversarially-verified.

| Artifact | Kind | Claude | Cursor | Copilot | Gemini | Codex | Windsurf | Opencode |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `adapter-load:claude` | adapter-instruction-load | L | — | — | — | — | — | — |
| `adapter-load:codex` | adapter-instruction-load | — | — | — | — | L | — | — |
| `adapter-load:copilot` | adapter-instruction-load | — | — | E | — | — | — | — |
| `adapter-load:cursor` | adapter-instruction-load | — | E | — | — | — | — | — |
| `adapter-load:gemini` | adapter-instruction-load | — | — | — | E | — | — | — |
| `adapter-load:opencode` | adapter-instruction-load | — | — | — | — | — | — | L |
| `adapter-load:windsurf` | adapter-instruction-load | — | — | — | — | — | L | — |
| `hook:commit-current-work` | hook-policy | N | I | N | I | N | I | N |
| `hook:commit-test-coverage` | hook-policy | N | I | N | I | N | I | N |
| `hook:git-hygiene-before-stop` | hook-policy | I | I | I | I | N | I | I |
| `hook:loop-budget` | hook-policy | I | I | I | I | N | I | I |
| `hook:output-cap` | hook-policy | I | I | I | N | I | I | I |
| `hook:review-before-stop` | hook-policy | N | N | N | N | N | I | I |
| `hook:session-state-before-stop` | hook-policy | I | I | I | I | N | I | I |
| `hook:trajectory-log` | hook-policy | I | N | N | N | N | N | I |
| `recipe:auto-mock-data` | recipe | E | E | E | E | E | E | E |
| `recipe:branch-strategy` | recipe | E | E | E | E | E | E | E |
| `recipe:coding-conventions` | recipe | E | E | E | E | E | E | E |
| `recipe:database-change-assurance` | recipe | E | E | E | E | E | E | E |
| `recipe:database-discipline` | recipe | E | E | E | E | E | E | E |
| `recipe:debugging` | recipe | E | E | E | E | E | E | E |
| `recipe:design-system` | recipe | E | E | E | E | E | E | E |
| `recipe:git-hygiene` | recipe | E | E | E | E | E | E | E |
| `recipe:i18n` | recipe | E | E | E | E | E | E | E |
| `recipe:loop-engineering` | recipe | E | E | E | E | E | E | E |
| `recipe:monorepo` | recipe | E | E | E | E | E | E | E |
| `recipe:non-vacuous-testing` | recipe | E | E | E | E | E | E | E |
| `recipe:release-provenance` | recipe | E | E | E | E | E | E | E |
| `recipe:self-improvement` | recipe | E | E | E | E | E | E | E |
| `recipe:tdd` | recipe | E | E | E | E | E | E | E |
| `recipe:visual-baseline-integrity` | recipe | E | E | E | E | E | E | E |
| `recipe:web-mobile-parity` | recipe | E | E | E | E | E | E | E |
| `rule:meta-discipline` | universal-rule | E | E | E | E | E | E | E |
| `rule:operations` | universal-rule | E | E | E | E | E | E | E |
| `rule:quality-gates` | universal-rule | E | E | E | E | E | E | E |
| `rule:spec-as-you-go` | universal-rule | E | E | E | E | E | E | E |
| `rule:workflow` | universal-rule | E | E | E | E | E | E | E |
| `runtime-contract:claude` | runtime-contract | N | — | — | — | — | — | — |
| `runtime-contract:codex` | runtime-contract | — | — | — | — | N | — | — |
| `runtime-contract:copilot` | runtime-contract | — | — | N | — | — | — | — |
| `runtime-contract:cursor` | runtime-contract | — | N | — | — | — | — | — |
| `runtime-contract:gemini` | runtime-contract | — | — | — | N | — | — | — |
| `runtime-contract:opencode` | runtime-contract | — | — | — | — | — | — | N |
| `runtime-contract:windsurf` | runtime-contract | — | — | — | — | — | N | — |
| `skill:coordinate-work` | portable-skill | E | E | E | E | E | E | E |
| `skill:plan-change` | portable-skill | E | E | E | E | E | E | E |
| `skill:propose-skill` | portable-skill | E | E | E | E | E | E | E |
| `skill:review-change` | portable-skill | E | E | E | E | E | E | E |
| `skill:verify-change` | portable-skill | E | E | E | E | E | E | E |

## Evidence summary

| Adapter | I | E | N | L | A | Unsupported |
|---|---:|---:|---:|---:|---:|---:|
| claude | 5 | 27 | 4 | 1 | 0 | 12 |
| cursor | 6 | 28 | 3 | 0 | 0 | 12 |
| copilot | 4 | 28 | 5 | 0 | 0 | 12 |
| gemini | 5 | 28 | 4 | 0 | 0 | 12 |
| codex | 1 | 27 | 8 | 1 | 0 | 12 |
| windsurf | 7 | 27 | 2 | 1 | 0 | 12 |
| opencode | 6 | 27 | 3 | 1 | 0 | 12 |

Machine-readable evidence paths and reasons are in `docs/AGENT-EVAL-COVERAGE.json`.
