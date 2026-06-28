# Windsurf adapter — transform.sh specification

What `adapters/windsurf/transform.sh` MUST do when implemented in P3.5.

## Invocation

```bash
./transform.sh <target-dir> [--dry-run]
```

## Inputs

```
core/universal-rules/meta-discipline.md
core/universal-rules/operations.md
core/universal-rules/quality-gates.md
core/universal-rules/spec-as-you-go.md
core/universal-rules/workflow.md
core/docs-templates/*.md
core/docs-templates/specs/_example.md
core/memory-pattern/README.md
adapters/windsurf/_native/windsurfrules.tpl       # Header template (Windsurf-flavored intro)
```

## Outputs

```
<target-dir>/
├── .windsurfrules                              # Always-loaded baseline (orchestrator manual + ABSOLUTE rules + always-loaded rules)
├── .windsurf/
│   └── rules/
│       ├── meta-discipline.md
│       ├── operations.md
│       ├── quality-gates.md
│       ├── spec-as-you-go.md
│       └── workflow.md
└── docs/
    ├── CURRENT_WORK.md                         # Verbatim
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## `.windsurfrules` composition (in order)

1. **Header from `_native/windsurfrules.tpl`** — bilingual (한/영) intro adapted for Windsurf.
2. **ABSOLUTE rules section** — R1-R8 minus Claude-only sub-agent enforcement. R-prefix renumbered.
3. **Always-loaded universal rules** — content from rules with `always_loaded: true` in `core/`.
4. **Pointer to docs** — `Read docs/CURRENT_WORK.md first every session.`
5. **Pointer to `.windsurf/rules/`** — informational ("additional rules load from .windsurf/rules/").

## Universal-rules → Windsurf translation

For each `core/universal-rules/<rule>.md`:

1. Parse YAML front-matter.
2. If `always_loaded: true`:
   - APPEND content (sans front-matter, with section heading) to `.windsurfrules` "Universal Rules" section.
   - Do NOT also emit to `.windsurf/rules/` (would double-load).
3. Else:
   - Emit `.windsurf/rules/<rule>.md` with front-matter STRIPPED (Windsurf doesn't use it).
   - Body preserved verbatim (with tool-specific callout replacement).

## Edge cases

| Case | Adapter behavior |
|---|---|
| `.windsurf/` doesn't exist | Create it. |
| Existing `.windsurfrules` at target | Skip; report "SKIP (exists)". |
| Existing `.windsurf/rules/operations.md` | Skip individually. |

## Idempotency check

Re-run reports "SKIP (exists)" for everything.

## Verification commands (P3.5 will fill)

```bash
test -f "<target>/.windsurfrules"                      || echo "MISSING .windsurfrules"
test -d "<target>/.windsurf/rules"                     || echo "MISSING .windsurf/rules dir"
test -f "<target>/.windsurf/rules/spec-as-you-go.md"   || echo "MISSING spec-as-you-go"

# Open project in Windsurf; verify rule indicator shows .windsurfrules + all .windsurf/rules/ files.
```

## P3.5 Windsurf version compatibility check

- Confirm `.windsurfrules` IS the canonical always-loaded location.
- Confirm Windsurf reads ALL files under `.windsurf/rules/` (not just a manifest-listed subset).
- Confirm priority order when same rule exists in both locations.

If Windsurf has changed conventions by P3.5, document in `notes.md`.

## Out of scope

- Windsurf authentication.
- Per-stack auto-detection.
