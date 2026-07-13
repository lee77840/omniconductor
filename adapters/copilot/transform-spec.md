# GitHub Copilot adapter — transform.sh specification

Normative behavior for the implemented `adapters/copilot/transform.sh`.

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
adapters/copilot/_native/all.instructions.tpl       # Always-loaded baseline template
```

## Outputs

```
<target-dir>/
├── .github/
│   ├── copilot-instructions.md                  # DEFAULT: 5 universal rules concatenated (repo-wide)
│   └── instructions/                            # --per-rule mode and/or selected recipes
│       ├── meta-discipline.instructions.md      # applyTo: '**'  (only in --per-rule mode)
│       ├── operations.instructions.md           # applyTo: '**'  (only in --per-rule mode)
│       ├── quality-gates.instructions.md        # applyTo: '**'  (only in --per-rule mode)
│       ├── spec-as-you-go.instructions.md       # applyTo: '**'  (only in --per-rule mode)
│       └── workflow.instructions.md             # applyTo: '**'  (only in --per-rule mode)
└── docs/
    ├── CURRENT_WORK.md                          # Verbatim
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Universal-rules → Copilot `.instructions.md` translation

For each `core/universal-rules/<rule>.md`:

1. Parse YAML front-matter. Extract `applies_to:`, `always_loaded:`.
2. Translate `applies_to:` array → CSV string for `applyTo:` (Copilot uses CSV glob syntax).
3. If `always_loaded: true` → emit with `applyTo: '**'`.
4. Else → emit with `applyTo: '<csv>'`.
5. Preserve capability-aware callouts from the universal source. Never rewrite a
   Claude + Codex shared guard as Claude-only, and never claim that Copilot emits
   a local guard that the adapter does not install.

## Repo-wide baseline (`.github/copilot-instructions.md`)

In the default mode, the 5 universal rules are concatenated (body only) into `.github/copilot-instructions.md`. Body composition (in order):

1. Header: orchestrator manual intro adapted for Copilot Chat and its native custom-agent surface.
2. ABSOLUTE rules plus the native eight-role topology and a Copilot-specific note about PR review for Stage B; omit only contracts the adapter cannot verify.
3. All universal-rule content where `always_loaded: true`.
4. Pointer to `docs/CURRENT_WORK.md` as session-start read.

Maximum size guidance: keep ≤ 1500 lines (Copilot has context limits; check Copilot's current docs for exact limit at P3 implementation time).

## Copilot-specific extensions

- Configure suggested PR review settings as a `notes.md` post-install instruction (not auto-configured — requires repo admin action).

## Edge cases

| Case | Adapter behavior |
|---|---|
| `.github/` doesn't exist | Create it. |
| Existing `.github/copilot-instructions.md` | Skip; report "SKIP (exists)". |
| Existing `.github/instructions/<rule>.instructions.md` | Skip individually. |
| Glob patterns contain commas (Copilot uses CSV) | Properly escape; warn if any pattern itself contains comma. |

## Idempotency check

Re-run reports "SKIP (exists)" for everything.

## Verification commands (P3 will fill)

```bash
test -f "<target>/.github/copilot-instructions.md"                   || echo "MISSING copilot-instructions.md"
# --per-rule mode:
# test -f "<target>/.github/instructions/spec-as-you-go.instructions.md" || echo "MISSING spec-as-you-go"

# Open Copilot Chat in project; ask "what rules apply?"; verify list.
# Touch a docs/specs/*.md file; ask Copilot for guidance; verify spec-as-you-go content surfaces.
```

## P3 Copilot version compatibility check

Verify against the user's Copilot version:
- `.github/instructions/*.instructions.md` is the canonical location.
- `applyTo:` uses CSV glob syntax (verify exact syntax — comma-separated vs YAML list).
- Multiple matching files compose (additive) rather than override.

If Copilot has changed format by P3, document in `notes.md`.

## Out of scope

- Auto-configuring Copilot PR review (requires repo admin permissions).
- Per-stack auto-detection.
- VS Code / JetBrains editor settings.
