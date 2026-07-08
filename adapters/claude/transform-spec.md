# Claude Code adapter — transform.sh specification

What `adapters/claude/transform.sh` MUST do when implemented in P1.

## Invocation

```bash
./transform.sh <target-dir> [--dry-run]
```

- `<target-dir>` — absolute path to the project directory where files install.
- `--dry-run` — print what would be written without touching disk. Exit 0.

## Inputs

Reads from (relative to conductor repo root):

```
core/workflow/PHASES.md
core/universal-rules/meta-discipline.md
core/universal-rules/operations.md
core/universal-rules/quality-gates.md
core/universal-rules/spec-as-you-go.md
core/universal-rules/workflow.md
core/docs-templates/CURRENT_WORK.md
core/docs-templates/REMAINING_TASKS.md
core/docs-templates/PLANS.md
core/docs-templates/TASKS.md
core/docs-templates/INDEX.md
core/docs-templates/specs/_example.md
core/memory-pattern/README.md
core/memory-pattern/EXAMPLES.md
core/roles/*.md                                        # 6 role personas → .claude/agents/ (planner/builder/reviewer/helper/designer/scribe)
core/hooks/*.sh.template                               # 9 hook templates
adapters/claude/_native/CLAUDE.md.tpl                  # Claude-specific orchestrator manual template
```

> `.claude/settings.json` is synthesized by `transform.sh` via a heredoc (permissions allowlist + hooks registry) — there is no checked-in `settings.template.json`.

## Outputs

Writes to `<target-dir>` at conventional paths. NEVER overwrites existing files at those paths — skip and report.

```
<target-dir>/
├── CLAUDE.md                                  # From CLAUDE.md.tpl, with placeholders preserved
├── .claude/
│   ├── agents/<6 .md files>                   # From core/roles/ (planner/builder/reviewer/helper/designer/scribe)
│   ├── rules/
│   │   ├── meta-discipline.md                 # Translated from core/universal-rules/meta-discipline.md
│   │   ├── operations.md                      # Translated from core/universal-rules/operations.md
│   │   ├── quality-gates.md                   # Translated
│   │   ├── spec-as-you-go.md                  # Translated
│   │   └── workflow.md                        # Translated
│   ├── hooks/<7 .sh files>                    # From core/hooks/*.sh.template, chmod +x
│   └── settings.json                          # Synthesized (permissions allowlist + hooks registry)
└── docs/
    ├── CURRENT_WORK.md                        # Verbatim copy from core/docs-templates/
    ├── REMAINING_TASKS.md
    ├── PLANS.md
    ├── TASKS.md
    ├── INDEX.md
    └── specs/_example.md
```

## Universal-rules → Claude-rules translation

For each `core/universal-rules/<rule>.md`:

1. Parse the YAML front-matter. Extract `applies_to:` and `always_loaded:`.
2. If `always_loaded: true` → APPEND content (sans front-matter) to `<target>/CLAUDE.md`'s "Universal Rules" section.
3. Else → write `<target>/.claude/rules/<rule>.md` with translated front-matter:
   ```yaml
   ---
   paths:
     - "<glob1>"
     - "<glob2>"
   ---
   ```
   (where `<globN>` are the values from `applies_to:`).
4. Body content is preserved verbatim, except:
   - Tool-specific callout markers (`> **Claude-only mechanism**: ...`) — keep as-is (they describe Claude's mechanism, accurate here).
   - Tool-specific callout markers for OTHER tools (`> **Cursor / Copilot / Gemini / Codex / Windsurf**: ...`) — STRIP (not relevant to Claude users).

## Memory pattern handling

- Copy `core/memory-pattern/README.md` → `<target>/.claude/memory-pattern-README.md` for reference.
- Do NOT auto-create the `~/.claude/projects/<encoded>/memory/` directory. Print a hint in the post-install message that explains where memory lives + how to start.

## Edge cases

| Case | Adapter behavior |
|---|---|
| Target dir doesn't exist | Error to stderr, exit 1. |
| Target dir is the conductor repo itself | Error to stderr, exit 1. |
| Target dir is not a git repo | Warn but continue. |
| Existing `CLAUDE.md` at target | Skip; report "SKIP (exists)". |
| Existing `.claude/agents/builder.md` | Skip individually; install other agents. |
| `core/` subdirectory missing | Error to stderr, exit 1 (broken installation). |
| `--dry-run` with no other args | Print all WOULD-WRITE actions. Exit 0. |
| `chmod +x` fails on hook | Warn but continue (hook is installed; user fixes perms). |

## Idempotency check

After install, re-running with the same `<target-dir>` MUST:
- Report "SKIP (exists)" for every file.
- Report "Installed 0, skipped N existing files."
- Exit 0.

## Verification commands (run after `transform.sh`)

```bash
# Core invariants:
test -f "<target>/CLAUDE.md"                           || echo "MISSING CLAUDE.md"
test -d "<target>/.claude/agents"                      || echo "MISSING agents dir"
test -d "<target>/.claude/rules"                       || echo "MISSING rules dir"
test -d "<target>/.claude/hooks"                       || echo "MISSING hooks dir"
test -f "<target>/.claude/settings.json"               || echo "MISSING settings.json"
test -d "<target>/docs/specs"                          || echo "MISSING docs/specs"
test -x "<target>/.claude/hooks/stop-session-log-check.sh" || echo "HOOK NOT EXECUTABLE"

# Open Claude Code in <target> and run /help
# Verify: 6 agents listed; rules load on file-pattern match; hooks fire on Stop.
```

## Diff parity vs v0.1

The v0.2 Claude adapter MUST produce output identical-or-better to `archive/v0.1/install.sh`. The "or-better" exception covers:
- Updates to rule content sourced from sanitized reference-adopter originals (P1 will refresh from current shipping versions).
- Migration of inline spec-as-you-go section to its own top-level rule file.

Before merging the P1 Claude adapter PR, run a diff between v0.1 and v0.2 install outputs on the same fresh target. Document any non-trivial differences.

## Out of scope (post-v1.0)

- Bilingual placeholder substitution (`{{PROJECT_NAME_KO}}`).
- Per-stack auto-detection (web vs mobile vs library).
- Auto-installing the user's `.claude/settings.json` from the template (security-sensitive; requires user edit).

These are deferred to post-v1.0 and tracked in `ROADMAP.md` Out-of-scope section.
