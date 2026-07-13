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
| **Sub-agent dispatch** | ✅ Emitted | Eight named agents in `.github/agents/*.agent.md` | Includes separate reviewer, code-reviewer, and Tier 3 utility roles. |
| **Hooks (agentStop)** | ✅ Native (2026) | `.github/hooks/*.json` | CONDUCTOR emits the verified Reflector hook; other guard translations remain excluded until their contracts are verified. |
| **Per-task model routing** | ✅ Configured native (2026) | Saved Tier model in each repository agent | Availability remains dependent on plan, client, and organization policy. |
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
- CONDUCTOR emits eight repository agents, including Tier 3 utility. Hook emission remains limited to the verified self-improvement Reflector lifecycle hook; pair with repository CI or pre-commit hooks for other mechanical gates.

## Difficulty translation

Every repository agent carries the invariant CONDUCTOR Tier and its project-saved
model. Initial setup recommends an available current triplet when it can be verified,
or clearly records syntax-only validation. Repository or organization policy may
still restrict the requested model; CONDUCTOR never silently changes the Tier.

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
