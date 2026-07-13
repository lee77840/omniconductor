# Gemini CLI adapter — transform.sh specification

Normative behavior for the implemented `adapters/gemini/transform.sh`.

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
adapters/gemini/_native/GEMINI.md.tpl              # Header template (orchestrator manual intro for Gemini)
```

## Outputs

```
<target-dir>/
├── GEMINI.md                                   # Bundled all-rules + orchestrator manual + universal rule TEXT
├── .gemini/
│   └── styleguide.md                           # coding-conventions recipe excerpt (opt-in)
└── docs/
    ├── CURRENT_WORK.md                         # Verbatim
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## `GEMINI.md` composition (in order)

1. **Header from `_native/GEMINI.md.tpl`** — bilingual (한/영) "you are the orchestrator" intro adapted for Gemini and its native agent profiles.
2. **ABSOLUTE rules section** — R1-R8 plus the native eight-role surface; omit only unverified guard contracts.
3. **Universal rules section** — for each `core/universal-rules/<rule>.md`:
   - Heading: `## <rule title>`
   - Body: rule content sans front-matter.
4. **Workflow section** — content from `core/workflow/PHASES.md`, slightly compressed for size.
5. **Pointer to docs** — `Read docs/CURRENT_WORK.md first every session.`
6. **Note on memory** — explain DIY `.memory/` setup (since Gemini has no built-in directory).

## `.gemini/styleguide.md` composition

- Body of `core/recipes/coding-conventions.md` (sans front-matter; opt-in recipe).
- Header: `# Code style guide for <project>` (with `{{PROJECT_NAME}}` placeholder for user to fill).

## Universal-rules → Gemini bundle translation

For each `core/universal-rules/<rule>.md`:

1. Strip front-matter (Gemini doesn't use front-matter).
2. Concatenate body into `GEMINI.md` as documented above.
3. Preserve capability-aware callouts from the universal source. Never rewrite a
   Claude + Codex shared guard as Claude-only, and never claim that Gemini emits
   a local guard that the adapter does not install.

## Edge cases

| Case | Adapter behavior |
|---|---|
| Existing `GEMINI.md` at target | Skip; report "SKIP (exists)". |
| Existing `.gemini/styleguide.md` | Skip individually. |
| `GEMINI.md` would exceed Gemini context limit | Warn (and document mitigation in `notes.md`). |

## Idempotency check

Re-run reports "SKIP (exists)" for everything.

## Verification commands (P3 will fill)

```bash
test -f "<target>/GEMINI.md"                           || echo "MISSING GEMINI.md"
test -f "<target>/.gemini/styleguide.md"               || echo "MISSING styleguide"

# Open Gemini CLI in <target>; verify it cites GEMINI.md content in responses.
# Ask Gemini for code-style guidance; verify .gemini/styleguide.md is consulted.
```

## P3 Gemini version compatibility check

Verify against current Gemini CLI conventions:
- `GEMINI.md` IS the canonical project-rules file.
- `.gemini/styleguide.md` IS the canonical style-guide convention.
- Whether Gemini walks parent directories for `GEMINI.md` (mono-repo implication).

If Gemini has changed conventions by P3, document in `notes.md`.

## Out of scope

- Gemini API key configuration (user does this in Gemini CLI auth flow).
- Per-stack auto-detection.
