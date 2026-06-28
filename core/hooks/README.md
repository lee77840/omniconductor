# `core/hooks/` — Universal hook templates

CONDUCTOR's universal hook spec. Templates here are compiled into native shell scripts by adapters that natively support hooks (Claude Code as of v0.2). Adapters without native hook support transform these into rule-text reminders embedded in the tool's primary rule file.

## The templates

| Template | Trigger | Action | Compile target |
|---|---|---|---|
| `pretool-agent-routing.sh.template` | Agent / sub-agent dispatch about to fire | Validate routing (no `general-purpose`, explicit model) | Claude `.claude/hooks/pretool-agent-routing.sh` |
| `pretool-commit-current-work-check.sh.template` | PreToolUse on Bash `git commit` | Soft `ask` warn — surfaces a reason at commit time when 3+ source files are staged but `CURRENT_WORK.md` is not part of the commit; non-blocking, orchestrator approves to proceed. Override env disables: `CONDUCTOR_SKIP_CURRENT_WORK_HOOK=1`. | Claude `.claude/hooks/pretool-commit-current-work-check.sh` |
| `pretool-commit-test-coverage-check.sh.template` | PreToolUse on Bash `git commit` | Soft `ask` warn (quality-gates Q3) — surfaces a reason when a newly-added feature-shaped source file has no new test (path with `test`/`spec`/`__tests__`/`e2e`) in the same commit; non-blocking, orchestrator approves to proceed. Override env disables: `CONDUCTOR_SKIP_TEST_COVERAGE_HOOK=1`. | Claude `.claude/hooks/pretool-commit-test-coverage-check.sh` |
| `pretool-large-file-read-guard.sh.template` | PreToolUse on the Read tool | **Block** a Read of files ≥ `${CONDUCTOR_LARGE_FILE_LINE_THRESHOLD}` (default 500) lines when no `offset`/`limit` is supplied; recommends range-read or Grep (token-economy / anti-pattern `large-file-read-no-range`). Fail-open. Override env disables: `CONDUCTOR_ALLOW_LARGE_READ=1`. | Claude `.claude/hooks/pretool-large-file-read-guard.sh` |
| `stop-session-log-check.sh.template` | Session stop event | Block stop if recent commits exist + CURRENT_WORK.md or specs are stale | Claude `.claude/hooks/stop-session-log-check.sh` |
| `stop-r6-review-check.sh.template` | Session stop event | Remind to run pre-merge review on open PR | Claude `.claude/hooks/stop-r6-review-check.sh` |
| `stop-cache-hit-baseline-check.sh.template` | Session stop event | Non-blocking diagnostic — reads the latest session JSONL, computes cache hit rate, reminds when below baseline (token-economy). Fail-open. Override env disables: `CONDUCTOR_SKIP_CACHE_CHECK=1`. | Claude `.claude/hooks/stop-cache-hit-baseline-check.sh` |

The two `pretool-commit-*` templates are **soft `ask` warns**: they emit
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":...}}`,
which surfaces the reason and routes to the permission flow — the orchestrator approves and
proceeds (or justifies). This is non-blocking and does NOT auto-approve (unlike
`permissionDecision: allow`, which would silently bypass the permission prompt). It mirrors
`pretool-agent-routing.sh.template`'s `deny`+reason shape (here `ask`+reason). They also fail
soft — any internal error exits 0. Each honors a per-commit override env var (above) for the
rare intentional exception.

## Frontmatter convention

Templates use a comment-block frontmatter (because shell scripts don't read YAML at runtime — the adapter parses the comment block):

```bash
#!/usr/bin/env bash
#
# CONDUCTOR universal hook template
# hook_id: <id>
# trigger: <pretool | stop>
# action: <description>
# compile_targets: claude
# fallback: rule-text-reminder
```

## Per-tool compilation

| Adapter | Compile behavior |
|---|---|
| Claude | `transform.sh` substitutes placeholders (paths, branch names, cool-down windows), writes to `.claude/hooks/<hook>.sh`, runs `chmod +x`. |
| Cursor / Copilot / Gemini / Codex / Windsurf | Hook compiles to a rule-text reminder added to the appropriate rule file. The reminder includes the trigger condition, the action, and the rationale. |

## Placeholders

Templates use `${PLACEHOLDER}` syntax for values that the adapter substitutes at compile time:

| Placeholder | Replaced with |
|---|---|
| `${CONDUCTOR_PROJECT_DIR}` | Absolute path to the target project |
| `${CONDUCTOR_PROTECTED_BRANCHES}` | Pipe-separated list (e.g., `main\|release\|develop`) |
| `${CONDUCTOR_COOLDOWN_SECONDS}` | Cool-down between reminders (typical: 1800 = 30 min) |
| `${CONDUCTOR_STALE_MINUTES}` | Staleness threshold (typical: 30) |
| `${CONDUCTOR_SOURCE_GLOB}` | Alternation of source extensions (e.g., `ts\|tsx`) |
| `${CONDUCTOR_CURRENT_WORK_PATH}` | Session-log path (default `docs/CURRENT_WORK.md`) |

Placeholders that the adapter does not know how to fill are passed through unchanged (with a warning) so the user can edit them post-install.
