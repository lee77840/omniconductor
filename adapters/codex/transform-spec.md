# Codex adapter — transform.sh specification

Normative behavior for the implemented `adapters/codex/transform.sh`.

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
adapters/codex/AGENTS-kernel.md                  # Bounded always-loaded contract
```

## Outputs

> **Convention change (post-P0):** the canonical Codex project-rules file is **`AGENTS.md`** at the
> project root — the established cross-agent standard adopted by OpenAI Codex / Codex CLI — NOT the
> early-design `.codex/codex.md` guess. The implemented `transform.sh` emits `AGENTS.md`; references
> to `.codex/codex.md` below are retained as historical design notes only.

```
<target-dir>/
├── AGENTS.md                                   # Bounded always-loaded runtime kernel
├── .codex/
│   ├── conductor/rules/*.md                    # Complete universal rules
│   ├── conductor/recipes/*.md                  # Complete selected recipes
│   ├── agents/*.toml                           # Eight native role profiles
│   ├── hooks/*.sh
│   └── hooks.json
└── docs/
    ├── CURRENT_WORK.md                         # Verbatim
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## `AGENTS.md` composition

1. Runtime and hook trust boundary.
2. Compact non-negotiable execution contract.
3. Activity-to-reference routing table.
4. Compressed workflow phases and native role routing.
5. Selected recipe pointers and an explicit end marker.

The generated kernel MUST remain at or below 24 KiB. The explicit end marker lets
the validator distinguish a complete kernel from an old oversized bundle.

## Universal-rules → Codex reference translation

Strip front-matter and write each complete rule to
`.codex/conductor/rules/<rule>.md`. Selected recipes use
`.codex/conductor/recipes/<recipe>.md`. These files are manifest-owned, checksum
verified, and explicitly routed from the always-loaded kernel; they are not claimed
to auto-load.

## Edge cases

| Case | Adapter behavior |
|---|---|
| Existing `AGENTS.md` | Back up, then write (manifest-tracked; `--uninstall` restores). |
| Generated `AGENTS.md` exceeds 24 KiB | Validator fails; release cannot proceed. |
| Installed `AGENTS.md` exceeds the default 32 KiB budget | Doctor fails because Codex may truncate trailing instructions. |

## Idempotency check

Re-run reports "SKIP (exists)" for everything.

## Verification commands (P3.5 will fill)

```bash
test -f "<target>/AGENTS.md"                                      || echo "MISSING AGENTS.md"
test "$(wc -c < "<target>/AGENTS.md")" -le 24576                 || echo "OVERSIZED AGENTS.md"
test -f "<target>/.codex/conductor/rules/quality-gates.md"        || echo "MISSING detailed rules"
codex -C "<target>" debug prompt-input "probe" | grep CONDUCTOR_KERNEL_END

# Run Codex in <target>; verify it follows ABSOLUTE rules + universal conventions.
```

## P3.5 Codex version compatibility check

- Confirm `AGENTS.md` IS the canonical project-rules location. (Confirmed — live-verified; current status in `docs/ADAPTER-LIVE-VERIFICATION.md`.)
- Confirm Codex auto-loads it on session start.
- Confirm the native prompt-input renderer includes the kernel end marker.
- Confirm detailed rule references remain present and checksum-tracked.

If Codex has changed conventions by P3.5, document in `notes.md`.

## Out of scope

- Codex authentication / API key.
- Per-stack auto-detection.
