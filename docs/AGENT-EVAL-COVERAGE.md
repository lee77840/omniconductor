# Agent Policy Assurance Coverage

> Generated from repository evidence. Do not hand-edit. A general adapter live
> probe does not upgrade a specific recipe, skill, or hook without exact evidence.

Levels: `—` unsupported · `I` instruction-only · `E` emit-verified ·
`N` native-contract-tested · `L` live-verified · `A` adversarially-verified.

| Artifact | Kind | Claude | Cursor | Copilot | Gemini | Codex | Windsurf |
|---|---|---:|---:|---:|---:|---:|---:|
| `adapter-load:claude` | adapter-instruction-load | L | — | — | — | — | — |
| `adapter-load:codex` | adapter-instruction-load | — | — | — | — | L | — |
| `adapter-load:copilot` | adapter-instruction-load | — | — | E | — | — | — |
| `adapter-load:cursor` | adapter-instruction-load | — | E | — | — | — | — |
| `adapter-load:gemini` | adapter-instruction-load | — | — | — | E | — | — |
| `adapter-load:windsurf` | adapter-instruction-load | — | — | — | — | — | E |
| `hook:commit-current-work` | hook-policy | N | I | N | I | N | I |
| `hook:commit-test-coverage` | hook-policy | N | I | N | I | N | I |
| `hook:git-hygiene-before-stop` | hook-policy | I | I | I | I | N | I |
| `hook:loop-budget` | hook-policy | I | I | I | I | N | I |
| `hook:output-cap` | hook-policy | I | I | I | N | I | I |
| `hook:review-before-stop` | hook-policy | N | N | N | N | N | I |
| `hook:session-state-before-stop` | hook-policy | I | I | I | I | N | I |
| `hook:trajectory-log` | hook-policy | I | N | N | N | N | N |
| `recipe:auto-mock-data` | recipe | E | E | E | E | E | E |
| `recipe:branch-strategy` | recipe | E | E | E | E | E | E |
| `recipe:coding-conventions` | recipe | E | E | E | E | E | E |
| `recipe:database-discipline` | recipe | E | E | E | E | E | E |
| `recipe:debugging` | recipe | E | E | E | E | E | E |
| `recipe:design-system` | recipe | E | E | E | E | E | E |
| `recipe:git-hygiene` | recipe | E | E | E | E | E | E |
| `recipe:i18n` | recipe | E | E | E | E | E | E |
| `recipe:loop-engineering` | recipe | E | E | E | E | E | E |
| `recipe:monorepo` | recipe | E | E | E | E | E | E |
| `recipe:self-improvement` | recipe | E | E | E | E | E | E |
| `recipe:tdd` | recipe | E | E | E | E | E | E |
| `recipe:web-mobile-parity` | recipe | E | E | E | E | E | E |
| `rule:meta-discipline` | universal-rule | E | E | E | E | E | E |
| `rule:operations` | universal-rule | E | E | E | E | E | E |
| `rule:quality-gates` | universal-rule | E | E | E | E | E | E |
| `rule:spec-as-you-go` | universal-rule | E | E | E | E | E | E |
| `rule:workflow` | universal-rule | E | E | E | E | E | E |
| `runtime-contract:claude` | runtime-contract | N | — | — | — | — | — |
| `runtime-contract:codex` | runtime-contract | — | — | — | — | N | — |
| `runtime-contract:copilot` | runtime-contract | — | — | N | — | — | — |
| `runtime-contract:cursor` | runtime-contract | — | N | — | — | — | — |
| `runtime-contract:gemini` | runtime-contract | — | — | — | N | — | — |
| `runtime-contract:windsurf` | runtime-contract | — | — | — | — | — | N |
| `skill:coordinate-work` | portable-skill | E | E | E | E | E | E |
| `skill:plan-change` | portable-skill | E | E | E | E | E | E |
| `skill:propose-skill` | portable-skill | E | E | E | E | E | E |
| `skill:review-change` | portable-skill | E | E | E | E | E | E |
| `skill:verify-change` | portable-skill | E | E | E | E | E | E |

## Evidence summary

| Adapter | I | E | N | L | A | Unsupported |
|---|---:|---:|---:|---:|---:|---:|
| claude | 5 | 23 | 4 | 1 | 0 | 10 |
| cursor | 6 | 24 | 3 | 0 | 0 | 10 |
| copilot | 4 | 24 | 5 | 0 | 0 | 10 |
| gemini | 5 | 24 | 4 | 0 | 0 | 10 |
| codex | 1 | 23 | 8 | 1 | 0 | 10 |
| windsurf | 7 | 24 | 2 | 0 | 0 | 10 |

Machine-readable evidence paths and reasons are in `docs/AGENT-EVAL-COVERAGE.json`.
