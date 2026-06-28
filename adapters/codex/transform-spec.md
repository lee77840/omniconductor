# Codex adapter — transform.sh specification

What `adapters/codex/transform.sh` MUST do when implemented in P3.5.

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
adapters/codex/_native/codex.md.tpl              # Header template (Codex-flavored intro)
```

## Outputs

> **Convention change (post-P0):** the canonical Codex project-rules file is **`AGENTS.md`** at the
> project root — the established cross-agent standard adopted by OpenAI Codex / Codex CLI — NOT the
> early-design `.codex/codex.md` guess. The implemented `transform.sh` emits `AGENTS.md`; references
> to `.codex/codex.md` below are retained as historical design notes only.

```
<target-dir>/
├── AGENTS.md                                   # Bundled all-rules + workflow + intro (project root)
└── docs/
    ├── CURRENT_WORK.md                         # Verbatim
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## `.codex/codex.md` composition (in order)

1. **Header from `_native/codex.md.tpl`** — bilingual (한/영) intro adapted for Codex (one-shot model, shell-task strength).
2. **ABSOLUTE rules section** — R1-R8 minus Claude-only sub-agent enforcement. R-prefix renumbered.
3. **Universal rules section** — for each `core/universal-rules/<rule>.md`:
   - Heading: `## <rule title>`
   - Body: rule content sans front-matter.
4. **Workflow section** — compressed version of `core/workflow/PHASES.md` (Codex's typical use cases skip Plan/Architecture more often than other tools).
5. **Pointer to docs** — `Read docs/CURRENT_WORK.md before any non-trivial task.`
6. **Note on memory** — explain DIY `.memory/`.

## Universal-rules → Codex bundle translation

Same as Gemini adapter — strip front-matter, concatenate, replace tool-specific callouts.

## Edge cases

| Case | Adapter behavior |
|---|---|
| `.codex/` doesn't exist | Create it. |
| Existing `.codex/codex.md` | Skip; report "SKIP (exists)". |
| `.codex/codex.md` exceeds Codex context budget | Warn; document trim strategy in `notes.md`. |

## Idempotency check

Re-run reports "SKIP (exists)" for everything.

## Verification commands (P3.5 will fill)

```bash
test -f "<target>/.codex/codex.md"                     || echo "MISSING codex.md"

# Run Codex in <target>; verify it follows ABSOLUTE rules + universal conventions.
```

## P3.5 Codex version compatibility check

- Confirm `.codex/codex.md` IS the canonical project-rules location.
- Confirm Codex auto-loads it on session start.
- Confirm Codex follows the rule TEXT in its inline code generation.

If Codex has changed conventions by P3.5, document in `notes.md`.

## Out of scope

- Codex authentication / API key.
- Per-stack auto-detection.
