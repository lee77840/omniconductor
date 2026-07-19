# Adapter — Claude Code (T1, full support)

The reference implementation. Claude Code is CONDUCTOR's most-feature-complete target because:

- It supports per-call sub-agent dispatch via the `Agent` tool.
- It supports hooks (PreToolUse, Stop, etc.) for ABSOLUTE rule enforcement.
- It supports lazy rule loading via `paths:` front-matter on `.claude/rules/*.md`.
- It supports per-call model routing via the `model:` argument.
- It has a built-in per-project memory directory (`~/.claude/projects/<encoded>/memory/`).

**Tier**: T1 — Full.

## Installation path

```bash
# Current usage (shipping):
bash adapters/claude/transform.sh <target> [--dry-run]

# Or by absolute path:
/path/to/conductor/adapters/claude/transform.sh /path/to/target [--dry-run]

# Or via the npm CLI (no clone needed):
npx omniconductor init --target=claude [target-dir]
```

The local `transform.sh` command requires Node.js and delegates to the same CLI,
including the one-time project-saved Tier-model setup. It is not a model-routing
bypass.

## What gets installed

```
<target>/
├── CLAUDE.md                                  # Slim orchestrator manual (~200 lines)
├── .claude/
│   ├── agents/
│   │   ├── planner.md
│   │   ├── builder.md
│   │   ├── reviewer.md
│   │   ├── helper.md
│   │   ├── designer.md
│   │   └── scribe.md
│   ├── rules/
│   │   ├── workflow.md
│   │   ├── spec-as-you-go.md
│   │   ├── quality-gates.md
│   │   ├── operations.md
│   │   └── meta-discipline.md
│   ├── hooks/                                 # 10 hook scripts
│   │   ├── pretool-agent-routing.sh
│   │   ├── pretool-commit-current-work-check.sh
│   │   ├── pretool-commit-test-coverage-check.sh
│   │   ├── pretool-large-file-read-guard.sh
│   │   ├── pretool-loop-guard.sh
│   │   ├── stop-session-log-check.sh
│   │   ├── stop-r6-review-check.sh
│   │   ├── stop-cache-hit-baseline-check.sh
│   │   ├── stop-trajectory-log.sh
│   │   └── stop-git-hygiene-guard.sh
│   ├── hookify.*.local.md                     # 12 always-on + recipe-scoped rule definitions
│   └── settings.json                          # Hookify dependency + permissions + hooks registry
├── docs/
│   ├── CURRENT_WORK.md
│   ├── REMAINING_TASKS.md
│   ├── PLANS.md
│   ├── TASKS.md
│   ├── INDEX.md
│   └── specs/
│       └── _example.md
└── (memory pattern docs — for reference; actual memory at ~/.claude/projects/.../memory/)
```

## Native features supported

- ✅ Sub-agent dispatch (`Agent` tool with named persona).
- ✅ Hooks (Stop, PreToolUse) for ABSOLUTE rule enforcement.
- ✅ Lazy rule loading (`paths:` front-matter, glob-matched).
- ✅ Per-call Tier routing through Claude family aliases (`opus` / `sonnet` / `haiku` by default); exact IDs are optional Tier overrides.
- ✅ Custom slash commands.
- ✅ Built-in memory directory.
- ✅ Always-loaded baseline (`CLAUDE.md`).

## Features NOT supported (Claude limitations)

None relevant to CONDUCTOR's scope. Claude is the reference implementation.

## After install — first steps

1. Edit `CLAUDE.md` — replace `{{PROJECT_NAME}}` and `{{DESIGN_SYSTEM_NAME}}` placeholders with your project's values.
2. Review the generated `.claude/settings.json` (Hookify project dependency + permissions allowlist + hooks registry). On a machine where Hookify is not installed yet, approve Claude Code's official-plugin prompt or run `claude plugin install hookify@claude-plugins-official --scope project`, then `/reload-plugins`. Per-user opt-outs belong in `.claude/settings.local.json`.
3. Rename `docs/specs/_example.md` → `docs/specs/<your-area>.md` and start a real spec.
4. Restart Claude Code in the project directory. Verify with `/help` that the new agents are recognized.
5. Add your first entry to `docs/CURRENT_WORK.md`.

## Status

The Claude adapter ships a working `transform.sh`, eight base roles, the full
verified guard set, project-saved Tier routing, manifest-safe uninstall, and the
opt-in Reflector runtime. Full/strict installs also declare Hookify at project
scope and doctor distinguishes configured rules from a plugin that is actually
active in the checkout. The frozen `archive/v0.1/` scaffold is historical only;
new installs use the current adapter or `npx omniconductor`.
