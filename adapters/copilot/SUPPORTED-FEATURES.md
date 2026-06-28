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
| **Sub-agent dispatch** | ❌ | — | Single chat per task. Human orchestrates. |
| **Hooks (PreToolUse, Stop)** | ❌ | — | No commit-blocking. Pair with project pre-commit git hooks. |
| **Per-call model routing** | ❌ | — | Model picker in UI; no programmatic routing. |
| **Custom slash commands** | ❌ | — | No project-level slash commands as of late 2025. |
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

- Sub-agent dispatch (per ADR-004 — not faked).
- Hooks for commit-blocking.
- Per-call model routing.
- Custom slash commands (project-level).
- Built-in memory directory.

## Strengths to lean into

- **`.github/instructions/` shared with the team automatically** — no per-developer setup. This is Copilot's strongest feature for CONDUCTOR.
- **PR review feature** — partial Stage B replacement. Configure to auto-review on PR open.

## Verification (deferred to P3)

| Feature claim | Verified-by-real-install | Verification command / observation |
|---|---|---|
| `.instructions.md` files load in Copilot Chat | ⏳ P3 | Open project; check Copilot Chat shows file references. |
| `applyTo:` per-pattern scoping works | ⏳ P3 | Open file matching `applyTo:`; verify rule loads. |
| PR review uses CONDUCTOR rules | ⏳ P3 | Open PR; check review references `coding-conventions`. |
