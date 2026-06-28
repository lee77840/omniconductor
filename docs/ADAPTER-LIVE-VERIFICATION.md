# Adapter Live-Verification Guide

> What the automated checks DO and DON'T cover, and a manual checklist to close the gap.

CONDUCTOR's CI + `tools/validate-adapter-output.sh` verify that each adapter **emits
the correct files** (right paths, the 5 universal rules present, no unsubstituted
placeholders, no reference-product leakage). They do **NOT** verify that the target
tool actually *loads and follows* those files in a live session — that requires the
tool installed and a real prompt. This guide is that last mile.

Status legend: ✅ = automated (CI/validator) · 🧪 = needs a live session (this guide).

| Adapter | File emission | Live rule-loading |
|---|---|---|
| Claude Code | ✅ | 🧪 (well-exercised in practice) |
| Cursor | ✅ | 🧪 |
| GitHub Copilot | ✅ | 🧪 (per-IDE — see `docs/IDE-SMOKE-TESTING.md`) |
| Gemini CLI | ✅ | 🧪 **(not yet run)** |
| Codex | ✅ | 🧪 **(not yet run)** |
| Windsurf | ✅ | 🧪 **(not yet run)** |

## Per-tool procedure

For each tool: (1) install into a throwaway project, (2) open the tool there, (3) run
the probe prompt, (4) record PASS/FAIL.

### Common setup
```bash
mkdir /tmp/cdt-<tool> && cd /tmp/cdt-<tool> && git init -q
bash <conductor>/adapters/<tool>/transform.sh . --no-prompt --recipes=coding-conventions
# (or: node <conductor>/bin/omniconductor.js init --target=<tool> . --no-prompt --recipes=coding-conventions)
```

### Probe prompt (same for every tool)
> "What workflow and rules are you operating under in this project? List the universal rules you can see, and tell me the first thing you must do before writing code."

**PASS criteria** — the tool's answer references CONDUCTOR's rules: the Plan-first /
spec-as-you-go / quality-gates discipline, and "read `docs/CURRENT_WORK.md` first" (or
equivalent). A generic answer that ignores the installed file = FAIL (tool didn't load it).

### Tool-specific load points
| Tool | File the tool must auto-load | Check |
|---|---|---|
| Gemini CLI | `GEMINI.md` (project root) + `.gemini/styleguide.md` | Does Gemini cite GEMINI.md content? Does it apply the styleguide on a code task? |
| Codex | `AGENTS.md` (project root) | Does Codex load AGENTS.md on session start? (AGENTS.md is the cross-agent convention) |
| Windsurf | `.windsurfrules` + `.windsurf/rules/*.md` | Does Windsurf show the rules in its Rules panel? Does it follow them? |
| Claude Code | `CLAUDE.md` + `.claude/rules/*.md` + agents/hooks | Rules panel + a Stop-hook fires on a stale-docs commit |
| Cursor | `.cursor/rules/*.mdc` | Settings → Rules tab shows the 5 rules |
| Copilot | `.github/copilot-instructions.md` (or `.github/instructions/*`) | Per-IDE — see `docs/IDE-SMOKE-TESTING.md` |

### Recording results
Record each tool's outcome in `docs/COMPATIBILITY-MATRIX.md` (a "Live-verified" column):
`✅ verified <date>` / `⚠️ partial (note)` / `❌ tool ignored the file`.

A tool that emits correctly (CI green) but FAILS live-loading is a **documentation /
file-location** issue, not an emission bug — check the tool's current rules-file
convention (they change), update the adapter's output path, re-run CI, then re-test.

## Why this is separate from CI
Running six AI coding tools headlessly in CI is impractical (each needs auth + a model).
So CONDUCTOR's CI guarantees *correct output*; this guide is the human-in-the-loop
guarantee of *correct consumption*. Treat the three new adapters (Gemini/Codex/Windsurf)
as "emission-verified, live-pending" until a session here is recorded.
