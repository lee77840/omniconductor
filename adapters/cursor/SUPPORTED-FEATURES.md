# Cursor — supported features

Detailed matrix of which CONDUCTOR features Cursor supports natively.

## Feature support

| Feature | Cursor support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `.cursorrules` at project root | Auto-loaded in every chat session in the project. |
| **Per-pattern rule scoping** | ✅ Native | `.cursor/rules/*.mdc` with `globs:` front-matter | Closest analog to Claude's `paths:` lazy-loading. |
| **Custom slash commands (project)** | ⚠️ Partial | `.cursor/commands/*.md` (where Cursor version supports) | Not as flexible as Claude slash commands; usable but limited. |
| **MCP servers** | ✅ Native | Cursor settings | Not used by CONDUCTOR; project may add own. |
| **In-IDE chat / completion** | ✅ Native | Cursor's primary feature set | Inline completion + chat — Cursor's strength. |
| **Runtime compatibility diagnosis** | ✅ Offline | metadata `runtime_contract` + doctor D13 | Project hooks require Cursor ≥1.7 only when `.cursor/hooks.json` is emitted; account/policy eligibility remains provider-controlled. |
| **Sub-agent dispatch** | ✅ Emitted | Eight named agents in `.cursor/agents/*.md` | Includes separate reviewer, code-reviewer, and Tier 3 utility roles. |
| **Hooks (stop)** | ✅ Native (2026) | `.cursor/hooks.json` + `.cursor/hooks/stop-r6-review-check.sh` | Full/strict emits verified review continuation; commit soft-confirmations remain rule fallbacks because Cursor's verified shell decision does not expose `ask`. Reflector is recipe-gated. |
| **Per-task model routing** | ✅ Configured native | Emitted agents use the saved Tier model | Cursor may still apply account, plan, Max Mode, or administrator fallback; `doctor` does not misreport that as guaranteed. |
| **Custom agent personas** | ✅ Native (2026) | `.cursor/agents/*.md` named agents | Previously a `.cursorrules` paste-in workaround; now first-class. |
| **Portable Agent Skills** | ✅ Emitted | `.agents/skills/*/SKILL.md` | Full/minimal/strict emit three instruction-only procedures; Cursor supports automatic matching and explicit invocation. |
| **Skill proposal inbox** | ✅ Opt-in | `.agents/skills/propose-skill/SKILL.md` + `.conductor/skill-proposals/` | Emitted only with `self-improvement`; native auto-suggestion is verification-required and the portable inbox remains authoritative. |
| **Extension/MCP trust audit** | ✅ Read-only | `omniconductor audit extensions --target=cursor` | Scans project-local Cursor configuration without executing it or exposing values. |
| **Provider package** | 📦 Direct fallback | no guessed manifest | Cursor documents plugin installs but not a stable public authoring manifest in the verified source; use the packaged direct preview or adapter installer. |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/` (gitignored). |
| **In-repo doc templates** | ✅ Native | Plain markdown; Cursor reads on demand | Universal across all adapters. |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule text in `.cursorrules` + `.cursor/rules/spec-as-you-go.mdc` | Self-policed. Pair with pre-commit git hook for mechanical enforcement. |
| **Two-stage code review enforcement** | ❌ rule reminder only | Rule text reminds; user runs review prompts manually in Cursor chat | |
| **Tool-output cap (store-time)** | ❌ N/A | — | Cursor's only verified hook contract is the Reflector's `stop` event; Cursor hook events are post-hooks (observe-only), so no verified store-time output-rewrite surface exists to cap tool results before they're stored. CONDUCTOR does not fake enforcement here. See ADR-051. |

## Cursor-specific extensions

CONDUCTOR's Cursor adapter MAY install:

- `.cursor/commands/*.md` — project commands for common workflows (e.g., `/plan`, `/review`, `/sync-spec`). These are partial analogs of Claude slash commands.

## Universal-rule → Cursor `.mdc` translation

For each `core/universal-rules/<rule>.md`:

| `core/` front-matter | Cursor `.mdc` front-matter |
|---|---|
| `applies_to: ["**/*.ts"]` | `globs:\n  - "**/*.ts"` |
| `always_loaded: true` | (merge into `.cursorrules` instead of separate `.mdc`) |
| `priority: 1` | (informational — no Cursor equivalent) |

Cursor `.mdc` accepts:
```
---
description: brief description
globs:
  - "<glob1>"
  - "<glob2>"
alwaysApply: false
---

# Rule body
```

`alwaysApply: true` overrides `globs:` and forces always-on. CONDUCTOR uses this for `spec-as-you-go.mdc` and `token-economy.mdc` (always-on is the safer behavior even though their `applies_to:` in `core/` is `**`).

## Difficulty translation

CONDUCTOR preserves Tier 1 (conceptual/complex), Tier 2 (routine), and Tier 3
(trivial) in every role. First setup saves three Cursor model values and regenerates
the role files. A provider fallback does not change the declared Tier.

## What Cursor DOES NOT support (and CONDUCTOR doesn't fake)

> **2026 reconciliation:** Cursor supports hooks, project agents, and project commands/skills. CONDUCTOR writes the user-approved mapping while distinguishing configuration from account/plan enforcement — see ADR-031/048/049.

What remains true on the CONDUCTOR side:

- CONDUCTOR emits eight native role profiles, including Tier 3 utility, plus verified review-stop continuation. Unsupported commit soft-confirmations remain rule text.
- Until then, commit-blocking enforcement still relies on project-level pre-commit git hooks, and orchestration discipline remains partly a human practice.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Cursor adapter emits the Reflector loop (ADR-032):

- **Hook**: `.cursor/hooks.json` — schema-composes `.conductor/reflect/trajectory-log.sh` on `stop` beside the baseline review guard, preserving arbitrary existing user entries.
- **Command**: `.cursor/skills/reflect/SKILL.md` — the `/reflect` command that distills the trajectory log into lesson candidates.
- **Agent**: `.cursor/agents/reflector.md` — named reflector agent for the distillation pass.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification (deferred to P2)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `.cursorrules` loads on session start | ⏳ P2 | Open project; new chat; verify rule indicator shows `.cursorrules`. |
| `.mdc` rules load on file-pattern match | ⏳ P2 | Touch a file matching `globs:`; verify rule indicator. |
| Project commands work | ⏳ P2 | Type `/<command>` in chat; verify expansion. |
