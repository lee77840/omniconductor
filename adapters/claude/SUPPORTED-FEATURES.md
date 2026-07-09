# Claude Code — supported features

Detailed matrix of which CONDUCTOR features Claude Code supports natively.

## Feature support

| Feature | Claude support | Mechanism | Notes |
|---|---|---|---|
| **Sub-agent dispatch** | ✅ Native | `Agent` tool with `subagent_type` arg | Named personas live in `.claude/agents/*.md`. Each is isolated — does NOT inherit `CLAUDE.md`. |
| **Per-call model routing** | ✅ Native | `model: "opus" \| "sonnet" \| "haiku"` arg on Agent call | Orchestrator classifies task → picks tier per call. |
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

CONDUCTOR's universal `meta-discipline.md` rubric (token economy + model routing) maps directly to Claude's three tiers:

| Universal tier | Claude model | Use cases |
|---|---|---|
| Opus | `claude-opus-4` (or current Opus equivalent) | Conceptual, multi-file, cross-cutting |
| Sonnet | `claude-sonnet-4` (or current Sonnet equivalent) | Routine implementation following patterns |
| Haiku | `claude-haiku-4` (or current Haiku equivalent) | Trivial reads / single-line edits |

## Hook execution model

CONDUCTOR ships 10 hooks, all registered in the generated `.claude/settings.json` (written directly by `transform.sh` — there is no `settings.template.json`):

| Hook | Event | Purpose |
|---|---|---|
| `pretool-agent-routing.sh` | `PreToolUse` (Agent calls) | Optionally remap or validate sub-agent dispatch (e.g., block `general-purpose` per CONDUCTOR R1). |
| `pretool-commit-current-work-check.sh` | `PreToolUse` (Bash commit) | Block a commit if `CURRENT_WORK.md` was not updated alongside the change. |
| `pretool-commit-test-coverage-check.sh` | `PreToolUse` (Bash commit) | Block a commit that adds code without matching test coverage. |
| `pretool-large-file-read-guard.sh` | `PreToolUse` (Read) | Warn / guard against reading very large files wholesale (token economy). |
| `stop-session-log-check.sh` | `Stop` | Block session end if code commits detected without matching spec update. |
| `stop-r6-review-check.sh` | `Stop` (session end) | Inject reminder to run Stage B `/code-review` slash command if a feature/fix branch has open PR + cool-down. |
| `stop-cache-hit-baseline-check.sh` | `Stop` | Flag prompt-cache baseline regressions at session end. |

`transform.sh` registers all 10 in `.claude/settings.json` (5 `PreToolUse` + 5 `Stop`). Users customize paths and conditions in that generated file, or override per-user in `settings.local.json` (gitignored).

## What Claude DOES NOT support that CONDUCTOR doesn't try to compensate for

- Direct CI integration. Hooks run locally; CI is the project's responsibility.
- IDE-style inline completion (Claude is a chat agent, not an IDE assistant — Cursor / Copilot fill that role).
- Visual GUI for rule management (CLI / file-on-disk only).

## Verification (P1 complete)

The Claude adapter ships a working `transform.sh`. Verified by fresh-target install:

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `transform.sh` emits 6 roles, 5 rules, 10 hooks, settings.json, docs | ✅ | `bash adapters/claude/transform.sh <tmp>` then inspect `<tmp>/.claude/` |
| Sub-agent dispatch works | ✅ | `.claude/agents/{planner,builder,reviewer,helper,designer,scribe}.md` recognized by `/help` |
| Lazy / always-loaded rules present | ✅ | `.claude/rules/{workflow,spec-as-you-go,quality-gates,operations,meta-discipline}.md` |
| Hooks registered in settings.json | ✅ | `.claude/settings.json` `hooks:` block lists 5 PreToolUse + 5 Stop |
| Stop hook blocks on missing spec update | ✅ | commit code without spec → `stop-session-log-check.sh` fires |
| Idempotent re-run | ✅ | second run reports "SKIP (exists)" for every emitted file |
