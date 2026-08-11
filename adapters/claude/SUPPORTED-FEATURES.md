# Claude Code — supported features

Detailed matrix of which CONDUCTOR features Claude Code supports natively.

## Feature support

| Feature | Claude support | Mechanism | Notes |
|---|---|---|---|
| **Sub-agent dispatch** | ✅ Native | `Agent` tool with `subagent_type` arg | Named personas live in `.claude/agents/*.md`. Each is isolated — does NOT inherit `CLAUDE.md`. Full/strict installs target the current `Agent` matcher contract; historical `Task`-name compatibility is not claimed. |
| **Per-call model routing** | ✅ Native | Agent `model` accepts family alias or exact ID | Orchestrator classifies the invariant Tier first, then passes the configured Claude translation. |
| **Hooks (PreToolUse, Stop, etc.)** | ✅ Native | `.claude/settings.json` `hooks:` block | Stop hooks are CONDUCTOR's spec-as-you-go enforcement. PreToolUse for routing. |
| **Lazy rule loading** | ✅ Native | `paths:` front-matter on `.claude/rules/*.md` | Rule loads when matching file path is touched. |
| **Always-loaded baseline** | ✅ Native | `CLAUDE.md` | Auto-read on every session start. Keep slim (~200 lines). |
| **Runtime compatibility diagnosis** | ✅ Offline | metadata `runtime_contract` + doctor D13 | Local version/floor inspection only; authentication stays opt-in. |
| **Custom slash commands** | ✅ Native | `.claude/commands/*.md` | Project-level commands available in chat (`/<command>`). |
| **Portable Agent Skills** | ✅ Emitted | `.claude/skills/*/SKILL.md` | Full/minimal/strict emit `plan-change`, `verify-change`, and `review-change`; automatic relevance matching or explicit slash invocation. |
| **Skill proposal inbox** | ✅ Opt-in | `.claude/skills/propose-skill/SKILL.md` + `.conductor/skill-proposals/` | Emitted only with `self-improvement`; accept/reject never auto-applies. |
| **Extension/MCP trust audit** | ✅ Read-only | `omniconductor audit extensions --target=claude` | Scans bounded project config, skips symlinks, and redacts values; MCP 2026-07-28 runtime boundary remains verification-required. |
| **Provider package** | ⚠️ Native partial | `.claude-plugin/plugin.json` | Skills and agents only. Rules, executable hooks, Reflector, routing, and reversible ownership still require direct install. |
| **MCP servers** | ✅ Native | `~/.claude/mcp.json` or project `.mcp.json` | CONDUCTOR doesn't ship MCP integration; projects can add their own. |
| **Memory directory** | ✅ Native | `~/.claude/projects/<encoded>/memory/` | 4-type pattern: user / feedback / project / reference. |
| **In-repo doc templates** | ✅ Native | Plain markdown under `docs/` | Read by orchestrator on demand. |
| **Spec-as-you-go ABSOLUTE enforcement** | ✅ Stop hook | `stop-session-log-check.sh` blocks session-end if code commit is detected without spec update | Strongest CONDUCTOR feature. |
| **Two-stage code review enforcement** | ✅ Stop hook | `stop-r6-review-check.sh` reminds about Stage A pre-commit + Stage B pre-merge PR | |
| **Token economy enforcement** | ⚠️ Rule reminder | `meta-discipline.md` rule + agent self-discipline | No mechanical enforcement; relies on agent following the rule. |
| **Tool-output cap (store-time)** | ✅ Native (`PostToolUse`) | `.claude/hooks/output-cap.sh` returns a **shape-preserving** `hookSpecificOutput.updatedToolOutput` (object responses keep their structure; oversized string leaves are clipped head 70% + marker + tail 30%) above `CONDUCTOR_OUTPUT_CAP_TOKENS` (default 8000; ~4 chars/token heuristic). Measured on Claude Code 2.1.215: −59.9% noisy-turn cache-creation tokens on a 166 KB Read (3 pairs, sd ≈ 30). | Requires Claude Code ≥v2.1.121 — the emitted-capability floor is single-sourced in metadata and doctor D13 warns only when a below-floor version is actually detected. Claude validates the replacement against the tool's output schema (a non-shape-preserving swap is silently discarded). Current Claude Code natively persists large **Bash** output to a ~2 KB stub, so this cap's value accrues to large non-persisted results (multi-line Read, MCP/WebFetch-class). Opt-out: `CONDUCTOR_SKIP_OUTPUT_CAP=1`. `doctor` verifies branch-local activation; `tools/audit-token-economy.js` measures actual reach. See ADR-051/058. |

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

CONDUCTOR ships 11 hooks, all registered in the generated `.claude/settings.json` (written directly by `transform.sh` — there is no `settings.template.json`):

| Hook | Event | Purpose |
|---|---|---|
| `pretool-agent-routing.sh` | `PreToolUse` (Agent calls) | Optionally remap or validate sub-agent dispatch (e.g., block `general-purpose` per CONDUCTOR R1). |
| `pretool-commit-current-work-check.sh` | `PreToolUse` (Bash commit) | Block a commit if `CURRENT_WORK.md` was not updated alongside the change. |
| `pretool-commit-test-coverage-check.sh` | `PreToolUse` (Bash commit) | Block a commit that adds code without matching test coverage. |
| `pretool-large-file-read-guard.sh` | `PreToolUse` (Read) | Warn / guard against reading very large files wholesale (token economy). |
| `pretool-loop-guard.sh` | `PreToolUse` (all tools) | Warn on repeated no-progress actions or a blown session tool budget when loop-engineering is selected. |
| `output-cap.sh` | `PostToolUse` (all tools) | Truncate an oversized tool result (head+tail+marker) before it re-enters context (ADR-051). Opt-out: `CONDUCTOR_SKIP_OUTPUT_CAP=1`. |
| `stop-session-log-check.sh` | `Stop` | Block session end if code commits detected without matching spec update. |
| `stop-r6-review-check.sh` | `Stop` (session end) | Inject reminder to run Stage B `/code-review` slash command if a feature/fix branch has open PR + cool-down. |
| `stop-cache-hit-baseline-check.sh` | `Stop` | Flag prompt-cache baseline regressions at session end. |
| `stop-trajectory-log.sh` | `Stop` | Record a bounded trajectory pointer when self-improvement is selected. |
| `stop-git-hygiene-guard.sh` | `Stop` | Remind on orphan worktrees, local-only commits, or branch sprawl when git-hygiene is selected. |

`transform.sh` registers all 11 in `.claude/settings.json` (5 `PreToolUse` + 1 `PostToolUse` + 5 `Stop`). Users customize paths and conditions in that generated file, or override per-user in `settings.local.json` (gitignored).

The routing registration deliberately matches the current official tool name
`Agent`. Full/strict installs co-emit the 2.1.121-gated output-cap surface, so doctor
D13 warns on older runtimes before CONDUCTOR claims the complete hook set is active.
The historical `Task` name is not added as an unverified fallback, and no separate
rename floor is guessed without a first-party version boundary. See ADR-059.

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
| Hooks registered in settings.json | ✅ | `.claude/settings.json` lists 5 PreToolUse + 1 PostToolUse + 5 Stop |
| Hookify rules have an active engine contract | ✅ | validator requires the project declaration and accepts deliberate per-rule disablement with a warning; doctor probes the local Claude plugin list and checkout path |
| Stop hook blocks on missing spec update | ✅ | commit code without spec → `stop-session-log-check.sh` fires |
| Idempotent re-run | ✅ | second run reports "SKIP (exists)" for every emitted file |
