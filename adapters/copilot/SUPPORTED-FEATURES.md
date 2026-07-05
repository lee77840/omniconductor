# GitHub Copilot — supported features

Detailed matrix of which CONDUCTOR features Copilot supports natively.

## Feature support

| Feature | Copilot support | Mechanism | Notes |
|---|---|---|---|
| **Always-loaded baseline** | ✅ Native | `.github/instructions/*.instructions.md` with `applyTo: '**'` | Loaded for every Copilot Chat session in the repo. |
| **Per-pattern rule scoping** | ✅ Native | `applyTo:` front-matter (CSV glob list) | Closest analog to Claude `paths:` and Cursor `globs:`. |
| **Instructions IN the repo** | ✅ Native | `.github/instructions/` is committed to the repo | All collaborators automatically share rules. Strong feature. |
| **Inline completion + chat** | ✅ Native | Copilot's primary feature | |
| **PR review automation** | ✅ Native | Copilot's PR review feature (configurable per repo) | Useful Stage B analog. |
| **MCP servers** | ⚠️ Partial | Copilot has limited MCP support depending on version | CONDUCTOR doesn't depend; project may add own. |
| **Sub-agent dispatch** | ✅ Native (2026) | Custom named agents in `.github/agents/*.agent.md` | See `docs/COMPATIBILITY-MATRIX.md` / ADR-031. |
| **Hooks (agentStop)** | ✅ Native (2026) | `.github/hooks/*.json` | ADR-031. CONDUCTOR currently emits only the Reflector hook (ADR-032); broader hook-set emission is Phase 2. |
| **Per-task model routing** | ✅ Native (2026) | Per-agent `model` in agent front-matter | ADR-031. |
| **Custom slash commands** | ✅ Native (2026) | Prompt files at `.github/prompts/*.prompt.md` | Was unavailable as of late 2025; supported now (ADR-031). |
| **Built-in memory directory** | ❌ | — | DIY at `.memory/` (gitignored). |
| **In-repo doc templates** | ✅ Universal | Plain markdown; Copilot Chat reads on demand | |
| **Spec-as-you-go ABSOLUTE enforcement** | ❌ rule reminder only | Rule in `.instructions.md` with `applyTo: 'docs/specs/**,**/*.md'` reminds when relevant files are touched | Self-policed. |
| **Two-stage code review enforcement** | ⚠️ Partial | Stage A: rule reminder; Stage B: configure Copilot PR review feature | |

## Universal-rule → Copilot `.instructions.md` translation

For each `core/universal-rules/<rule>.md`:

| `core/` front-matter | Copilot `.instructions.md` front-matter |
|---|---|
| `applies_to: ["**/*.ts", "**/*.tsx"]` | `applyTo: '**/*.ts,**/*.tsx'` (CSV) |
| `always_loaded: true` | `applyTo: '**'` (matches everything) |

Copilot accepts:
```
---
applyTo: '<csv-glob-list>'
---

# Rule body in plain markdown
```

## What Copilot DOES NOT support

> **2026 reconciliation (first-party verified):** most limitations previously listed here are stale. Copilot now natively supports hooks (`.github/hooks/*.json`), sub-agent dispatch with custom named agents (`.github/agents/*.agent.md`), per-task model routing (per-agent `model`), and project-level commands via prompt files (`.github/prompts/*.prompt.md`) — see `docs/COMPATIBILITY-MATRIX.md` / ADR-031.

Still true:

- No built-in memory directory — DIY at `.memory/` (gitignored).
- CONDUCTOR does not yet emit a Claude-parity hook set for Copilot. It currently emits only the self-improvement Reflector hook (ADR-032, opt-in — see below); broader hook-set emission (commit-blocking, spec enforcement) is Phase 2. Until then, pair with project pre-commit git hooks.

## Strengths to lean into

- **`.github/instructions/` shared with the team automatically** — no per-developer setup. This is Copilot's strongest feature for CONDUCTOR.
- **PR review feature** — partial Stage B replacement. Configure to auto-review on PR open.

## Self-improvement (Reflector) — opt-in

With `--recipes=self-improvement`, the Copilot adapter emits the Reflector loop (ADR-032):

- **Hook**: `.github/hooks/conductor-reflect.json` — registers `.conductor/reflect/trajectory-log.sh` on the `agentStop` event. Written only if absent; if a hook config already exists, the adapter emits a manual-merge log entry instead of overwriting.
- **Command**: `.github/prompts/reflect.prompt.md` — the `/reflect` prompt that distills the trajectory log into lesson candidates.
- **Agent**: `.github/agents/reflector.agent.md` — named reflector agent for the distillation pass.
- **Scripts**: `.conductor/reflect/trajectory-log.sh` (session trajectory capture) and `.conductor/reflect/prune-lessons.sh` (lesson-file size pruning).

The loop is propose-only — lessons are proposed for human review, never auto-applied to rules. The hook no-ops unless `.conductor/reflect/` exists, so installs without the recipe are unaffected (opt-in gate).

## Verification (deferred to P3)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `.instructions.md` files load in Copilot Chat | ⏳ P3 | Open project; check Copilot Chat shows file references. |
| `applyTo:` per-pattern scoping works | ⏳ P3 | Open file matching `applyTo:`; verify rule loads. |
| PR review uses CONDUCTOR rules | ⏳ P3 | Open PR; check review references `coding-conventions`. |
