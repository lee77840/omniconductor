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
core/docs-templates/{plans,architecture,research}/README.md
core/memory-pattern/README.md
core/runtime-kernel.md                              # portable bounded baseline
```

## Outputs

Full/minimal/strict also copy the three byte-identical portable procedures from
`core/skills/` to Copilot's documented alternative
`.agents/skills/<name>/SKILL.md` project path. Recipes-only and Reflector-only
do not emit the baseline set.
`self-improvement` adds `propose-skill` at the same root, including
Reflector-only; review preserves `applied: false`.

Each emitted role compiles `capabilities` into an exact native `tools` alias
allowlist. Portable `test` does not imply `execute`, edit remains provider-coarse,
and unnamed abstract MCP authority fails closed.

```
<target-dir>/
├── .github/
│   ├── copilot-instructions.md                  # DEFAULT: bounded repo-wide kernel
│   ├── conductor/rules/*.md                    # complete byte-identical rules
│   ├── conductor/recipes/*.md                  # complete selected recipes
│   └── instructions/                            # alternate kernel + scoped recipe pointers
│       └── conductor-kernel.instructions.md     # --per-rule bounded-kernel alternative
└── docs/
    ├── CURRENT_WORK.md                          # Verbatim
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    ├── specs/_example.md
    ├── plans/README.md
    ├── architecture/README.md
    └── research/README.md
```

## Universal-rules → Copilot bounded translation

1. Render the shared bounded kernel into the default root file or the `--per-rule`
   alternative with `applyTo: '**'`.
2. Copy complete rules byte-identically to `.github/conductor/rules/`.
3. Emit selected complete recipes plus small `applyTo:` pointers using canonical globs.
4. Preserve capability-aware callouts from the universal source. Never rewrite a
   Claude + Codex shared guard as Claude-only, and never claim that Copilot emits
   a local guard that the adapter does not install.

## Repo-wide baseline (`.github/copilot-instructions.md`)

The default file contains only the portable kernel. Complete policy remains on
demand, with a 12 KiB kernel and 16 KiB always-active budget enforced by
`audit instructions`.

## Copilot-specific extensions

- Configure suggested PR review settings as a `notes.md` post-install instruction (not auto-configured — requires repo admin action).

## Edge cases

| Case | Adapter behavior |
|---|---|
| `.github/` doesn't exist | Create it. |
| Existing unmanaged baseline | Central adoption policy requires recipes-only preservation, explicit backup-and-replace, or abort before writes. |
| Glob patterns contain commas (Copilot uses CSV) | Properly escape; warn if any pattern itself contains comma. |

## Idempotency check

Re-run reports "SKIP (exists)" for everything.

## Verification commands (P3 will fill)

```bash
test -f "<target>/.github/copilot-instructions.md"                   || echo "MISSING copilot-instructions.md"
# --per-rule mode:
# test -f "<target>/.github/instructions/conductor-kernel.instructions.md" || echo "MISSING kernel"

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
