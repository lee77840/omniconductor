# Cursor adapter — transform.sh specification

What `adapters/cursor/transform.sh` MUST do when implemented in P2.

## Invocation

```bash
./transform.sh <target-dir> [--dry-run]
```

## Inputs

Reads from (relative to conductor repo root):

```
core/universal-rules/meta-discipline.md
core/universal-rules/operations.md
core/universal-rules/quality-gates.md
core/universal-rules/spec-as-you-go.md
core/universal-rules/workflow.md
core/docs-templates/*.md
core/docs-templates/specs/_example.md
core/memory-pattern/README.md
adapters/cursor/_native/cursorrules.tpl                # Cursor-specific orchestrator manual template
adapters/cursor/_native/commands/*.md                  # (optional) project commands
```

## Outputs

```
<target-dir>/
├── .cursorrules                                # From _native/cursorrules.tpl + always-loaded rules merged
├── .cursor/
│   ├── rules/
│   │   ├── meta-discipline.mdc                 # Translated (alwaysApply: true)
│   │   ├── operations.mdc                      # Translated (alwaysApply: true)
│   │   ├── quality-gates.mdc                   # Translated (alwaysApply: true)
│   │   ├── spec-as-you-go.mdc                  # Translated (alwaysApply: true)
│   │   └── workflow.mdc                        # Translated (alwaysApply: true)
│   └── commands/                                # (optional) project commands
└── docs/
    ├── CURRENT_WORK.md                         # Verbatim copy
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Universal-rules → Cursor `.mdc` translation

For each `core/universal-rules/<rule>.md`:

1. Parse YAML front-matter. Extract `applies_to:`, `always_loaded:`.
2. If `always_loaded: true`:
   - APPEND content (sans front-matter, with section heading) to `.cursorrules` "Universal Rules" section.
   - ALSO emit a `.mdc` with `alwaysApply: true` (Cursor reads both — having both ensures the rule loads even if the user customized `.cursorrules`).
3. Else:
   - Emit `.cursor/rules/<rule>.mdc` with translated front-matter:
     ```yaml
     ---
     description: <derived from rule's first paragraph or title>
     globs:
       - "<glob1>"
       - "<glob2>"
     ---
     ```
   - Body content preserved verbatim, except:
     - `> **Cursor-only mechanism**` callouts: keep as-is.
     - `> **Claude-only mechanism**` callouts: REPLACE with a degraded callout: `> **Note (Cursor)**: this rule is enforced by hook on Claude Code; on Cursor, follow self-policed.`
     - Other tool-specific callouts: STRIP.

## Cursor-specific orchestrator manual

`.cursorrules` body:

1. Header — bilingual (한/영) "you are the orchestrator" intro.
2. The 6 role personas (planner/builder/reviewer/helper/designer/scribe) reformatted as "manual orchestrator personas" — when starting a complex task, paste the relevant persona from this file as your prompt.
3. ABSOLUTE rules (R1-R8 from CONDUCTOR universal, with R-prefix renumbered for Cursor reality — drop sub-agent-specific rules, keep spec-as-you-go / two-stage review / token economy / model routing).
4. Universal rule TEXT (from `core/` always-loaded rules).
5. Pointer to `docs/CURRENT_WORK.md` as session-start read.

## Edge cases

| Case | Adapter behavior |
|---|---|
| Target dir doesn't exist | Error to stderr, exit 1. |
| Target dir is the conductor repo itself | Error to stderr, exit 1. |
| Existing `.cursorrules` at target | Skip; report "SKIP (exists)". |
| Existing `.cursor/rules/operations.mdc` | Skip individually. |
| Cursor version doesn't support `.cursor/commands/` | Skip the commands directory; warn. |
| Cursor version uses `.cursor/rules.json` instead of `.mdc` | TBD — verify in P2 against the user's Cursor version. |

## Idempotency check

Same as Claude adapter — re-run reports "SKIP (exists)" for everything.

## Verification commands (P2 will fill)

```bash
test -f "<target>/.cursorrules"                        || echo "MISSING .cursorrules"
test -d "<target>/.cursor/rules"                       || echo "MISSING .cursor/rules dir"
test -f "<target>/.cursor/rules/spec-as-you-go.mdc"    || echo "MISSING spec-as-you-go.mdc"

# Open project in Cursor.
# Touch a docs/specs/*.md file.
# Verify Cursor rule indicator shows spec-as-you-go.mdc loaded.
```

## P2 Cursor-version compatibility check

Cursor's rule format has evolved. P2 must verify:

- `.cursor/rules/*.mdc` is the current canonical location (true as of late 2025).
- `globs:` front-matter is the supported scoping mechanism (true as of late 2025).
- `alwaysApply: true` is honored.

If any of these have changed by P2 implementation time, document in `adapters/cursor/notes.md` and adjust the spec.

## Out of scope

- Auto-installing Cursor itself.
- Auto-configuring Cursor settings (privacy mode, model preferences).
- Per-stack auto-detection.
