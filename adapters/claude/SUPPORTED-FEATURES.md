# Claude Code — supported features

Detailed matrix of which CONDUCTOR features Claude Code supports natively.

## Feature support

| Feature | Claude support | Mechanism | Notes |
|---|---|---|---|
| **Sub-agent dispatch** | ✅ Native | `Agent` tool with `subagent_type` arg | Named personas live in `.claude/agents/*.md`. Each is isolated — does NOT inherit `CLAUDE.md`. |
| **Per-call model routing** | ✅ Native | Agent `model` accepts family alias or exact ID | Orchestrator classifies the invariant Tier first, then passes the configured Claude translation. |
| **Hooks (PreToolUse, Stop, etc.)** | ✅ Native | `.claude/settings.json` `hooks:` block | Stop hooks are CONDUCTOR's spec-as-you-go enforcement. PreToolUse for routing. |
| **Lazy rule loading** | ✅ Native | `paths:` front-matter on `.claude/rules/*.md` | Rule loads when matching file path is touched. |
| **Always-loaded baseline** | ✅ Native | `CLAUDE.md` | Auto-read on every session start. Keep slim (~200 lines). |
| **Custom slash commands** | ✅ Native | `.claude/commands/*.md` | Project-level commands available in chat (`/<command>`). |
| **Skills (plugin ecosystem)** | ✅ Native | `Skill` tool + plugin marketplace | CONDUCTOR doesn't depend on skills, but is compatible. |
| **MCP servers** | ✅ Native | `~/.claude/mcp.json` or project `.mcp.json` | CONDUCTOR doesn't ship MCP integration; projects can add their own. |
| **Memory directory** | ✅ Native | `~/.claude/projects/<encoded>/memory/` | 4-type pattern: user / feedback / project / reference. |
| **In-repo doc templates** | ✅ Native | Plain markdown under `docs/` | Read by orchestrator on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ✅ Stop hook | `stop-session-log-check.sh` blocks session-end if code commit is detected without spec update | Strongest CONDUCTOR feature. |
| **Two-stage code review enforcement** | ✅ Stop hook | `stop-r6-review-check.sh` reminds about Stage A pre-commit + Stage B pre-merge PR | |
| **Token economy enforcement** | ⚠️ Rule reminder | `meta-discipline.md` rule + agent self-discipline | No mechanical enforcement; relies on agent following the rule. |

## Model tier mapping

CONDUCTOR's universal `meta-discipline.md` rubric (token economy + difficulty routing) maps the three invariant Tiers to Claude aliases:

| Universal tier | Claude model | Use cases |
|---|---|---|
| Tier 1 | `opus` family alias | Conceptual, multi-file, cross-cutting |
| Tier 2 | `sonnet` family alias | Routine implementation following patterns |
| Tier 3 | `haiku` family alias | Trivial reads / single-line edits |

Family aliases follow Claude's current model in that family, avoiding dated IDs.
Exact pins are saved through `omniconductor models configure --target=claude`;
pins do not change the Tier triggers. Inherited environment variables cannot
override the saved project mapping during a real install.

## Hook execution model

CONDUCTOR ships 10 hooks, all registered in the generated `.claude/settings.json` (written directly by `transform.sh` — there is no `settings.template.json`):

| Hook | Event | Purpose |
|---|---|---|
| `pretool-agent-routing.sh` | `PreToolUse` (Agent calls) | Optionally remap or validate sub-agent dispatch (e.g., block `general-purpose` per CONDUCTOR R1). |
| `pretool-commit-current-work-check.sh` | `PreToolUse` (Bash commit) | Block a commit if `CURRENT_WORK.md` was not updated alongside the change. |
| `pretool-commit-test-coverage-check.sh` | `PreToolUse` (Bash commit) | Block a commit that adds code without matching test coverage. |
| `pretool-large-file-read-guard.sh` | `PreToolUse` (Read) | Warn / guard against reading very large files wholesale (token economy). |
| `pretool-loop-guard.sh` | `PreToolUse` (all tools) | Warn on repeated no-progress actions or a blown session tool budget when loop-engineering is selected. |
| `stop-session-log-check.sh` | `Stop` | Block session end if code commits detected without matching spec update. |
| `stop-r6-review-check.sh` | `Stop` (session end) | Inject reminder to run Stage B `/code-review` slash command if a feature/fix branch has open PR + cool-down. |
| `stop-cache-hit-baseline-check.sh` | `Stop` | Flag prompt-cache baseline regressions at session end. |
| `stop-trajectory-log.sh` | `Stop` | Record a bounded trajectory pointer when self-improvement is selected. |
| `stop-git-hygiene-guard.sh` | `Stop` | Remind on orphan worktrees, local-only commits, or branch sprawl when git-hygiene is selected. |

`transform.sh` registers all 10 in `.claude/settings.json` (5 `PreToolUse` + 5 `Stop`). Users customize paths and conditions in that generated file, or override per-user in `settings.local.json` (gitignored).

## Hookify activation contract

Full and strict installs emit the applicable `.claude/hookify.*.local.md` rule
definitions and declare `hookify@claude-plugins-official: true` under the
project's `.claude/settings.json` `enabledPlugins`. A fresh settings file gets
the declaration directly. An existing valid settings file receives only the
missing plugin key and missing core-hook registrations; all other values and
existing hook options are preserved, and uninstall restores the exact pre-merge
file. An explicit project `false` is never overridden.

The same validator/doctor path also rejects emitted core hook scripts that are
not registered in settings. The project declaration is not permission to
download plugin code silently.
On a machine that has not installed the official plugin, Claude Code asks for
consent; the equivalent explicit command is
`claude plugin install hookify@claude-plugins-official --scope project`, followed
by `/reload-plugins`. `omniconductor doctor` reports a failure when rule files
exist without the project declaration and a warning when the declaration exists
but the local Claude runtime still reports the plugin inactive.

## What Claude DOES NOT support that CONDUCTOR doesn't try to compensate for

- Direct CI integration. Hooks run locally; CI is the project's responsibility.
- IDE-style inline completion (Claude is a chat agent, not an IDE assistant — Cursor / Copilot fill that role).
- Visual GUI for rule management (CLI / file-on-disk only).

## Verification (P1 complete)

The Claude adapter ships a working `transform.sh`. Verified by fresh-target install:

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `transform.sh` emits 8 base roles, 5 rules, verified hooks, settings.json, docs | ✅ | `bash adapters/claude/transform.sh <tmp>` then inspect `<tmp>/.claude/` |
| Sub-agent dispatch works | ✅ | `.claude/agents/{planner,builder,reviewer,helper,designer,scribe}.md` recognized by `/help` |
| Lazy / always-loaded rules present | ✅ | `.claude/rules/{workflow,spec-as-you-go,quality-gates,operations,meta-discipline}.md` |
| Hooks registered in settings.json | ✅ | `.claude/settings.json` `hooks:` block lists 5 PreToolUse + 5 Stop |
| Hookify rules have an active engine contract | ✅ | validator requires the project declaration and accepts deliberate per-rule disablement with a warning; doctor probes the local Claude plugin list and checkout path |
| Stop hook blocks on missing spec update | ✅ | commit code without spec → `stop-session-log-check.sh` fires |
| Idempotent re-run | ✅ | second run reports "SKIP (exists)" for every emitted file |
