# MANUAL INSTALL — CONDUCTOR

> Companion to `README.md`. Step-by-step manual install for every supported tool, on Mac and Windows.

This document is the fallback when the per-tool `transform.sh` adapter is not yet available, when you want to understand exactly what the adapter does, or when you are in a constrained environment (no bash, locked-down corporate machine, etc.) and need to copy files by hand.

For each tool there are two paths:

- **Adapter (recommended)** — a single `bash transform.sh <target>` invocation. Available now for Claude Code, Cursor, GitHub Copilot.
- **Manual file copy (fallback)** — explicit `cp` / `cat` commands and frontmatter cheat sheet. Available for every tool, including the ones whose adapters have not shipped.

> **Read first**: [`README.md`](../README.md) Quick Start. The Claude adapter has a guided wizard that handles 90% of installs. Manual install is for the remaining 10%.

---

## Conventions used in this document

- `~/conductor` = where you cloned the Conductor repo.
- `<target>` = your project directory (e.g. `~/Projects/my-app`).
- "Mac" = macOS native shell (zsh by default, bash also OK).
- "Windows / Git Bash" = [Git for Windows](https://git-scm.com/download/win) Bash terminal. POSIX-compatible.
- "Windows / WSL2" = Ubuntu running under WSL2. Same commands as Mac.
- "Windows / PowerShell" = native PowerShell. **Currently unsupported** (P3+ port). Use Git Bash or WSL2 for now.

> **GNU vs BSD `sed` warning**: macOS ships BSD `sed` which requires `-i ''` for inline edits, while GNU `sed` (Linux / Git Bash / WSL2) uses `-i` with no argument. Manual-install commands below avoid `sed -i` for portability — they use `cat > new-file` + `mv` instead.

---

## Quick Decision: which tool, which path

| Tool | Adapter ready | Recommended install |
|---|---|---|
| Claude Code | ✅ | `bash adapters/claude/transform.sh <target>` (see README) |
| Cursor | ✅ (P2 in flight) | `bash adapters/cursor/transform.sh <target>` |
| GitHub Copilot | ✅ (P2 in flight) | `bash adapters/copilot/transform.sh <target>` |
| Gemini CLI | ❌ | manual copy (this doc) |
| Codex (OpenAI) | ❌ | manual copy (this doc) |
| Windsurf | ❌ | manual copy (this doc) |

> Adapter ship status as of 2026-05-10. Cursor and Copilot adapters are in active development under separate dispatches. If `adapters/<tool>/transform.sh` exists and is executable, prefer it; otherwise follow the manual section for that tool.

---

## Frontmatter conversion cheat sheet

Universal rules in `core/universal-rules/*.md` use Conductor-canonical YAML frontmatter:

```yaml
---
applies_to: ["**/*.ts", "**/*.tsx"]
always_loaded: false
tier: T1
---
```

Each tool consumes a different syntax. When you copy a rule file into a tool-native location by hand, rewrite the frontmatter using the table below.

| Conductor field | Claude Code | Cursor (`.mdc`) | Copilot (`.instructions.md`) | Gemini / Codex / Windsurf |
|---|---|---|---|---|
| `applies_to: ["a", "b"]` | `paths: ["a", "b"]` | `globs: a, b` (CSV) | `applyTo: 'a, b'` (CSV string) | (drop — single bundled file) |
| `always_loaded: true` | drop `paths:` (auto-loads) | `alwaysApply: true` | `applyTo: '**'` | (drop — file always loads) |
| `always_loaded: false` | `paths: [...]` required | `alwaysApply: false` + `globs:` | `applyTo: '<csv>'` | not representable |
| `tier: T1/T2/T3` | (informational) | (informational) | (informational) | (informational) |

> Conductor's universal rules (`meta-discipline`, `operations`, `quality-gates`, `spec-as-you-go`, `workflow`) are all `always_loaded: true` — make sure the tool-specific equivalent is set. Skipping this is the most common manual-install mistake.

---

## Tool 1 — Cursor (manual, until P2 adapter ships)

### Prerequisites

- Cursor installed.
- The Conductor repo cloned to `~/conductor`.

### Mac / Linux / Windows-WSL2

```bash
cd <target>

# 1. Create Cursor rule directory
mkdir -p .cursor/rules

# 2. Copy each universal rule with .mdc extension
for f in ~/conductor/core/universal-rules/*.md; do
  base=$(basename "$f" .md)
  cp "$f" ".cursor/rules/${base}.mdc"
done

# 3. Append always-loaded rules to .cursorrules baseline
#    (all 5 universal rules are always-loaded; bundle them for older Cursor versions)
cat ~/conductor/core/universal-rules/meta-discipline.md \
    ~/conductor/core/universal-rules/spec-as-you-go.md \
    > .cursorrules

# 4. Copy doc templates (skip if you already have docs/CURRENT_WORK.md etc.)
mkdir -p docs/specs
[ -f docs/CURRENT_WORK.md ]    || cp ~/conductor/core/docs-templates/CURRENT_WORK.md    docs/
[ -f docs/REMAINING_TASKS.md ] || cp ~/conductor/core/docs-templates/REMAINING_TASKS.md docs/
[ -f docs/PLANS.md ]           || cp ~/conductor/core/docs-templates/PLANS.md           docs/
[ -f docs/TASKS.md ]           || cp ~/conductor/core/docs-templates/TASKS.md           docs/
[ -f docs/INDEX.md ]           || cp ~/conductor/core/docs-templates/INDEX.md           docs/
[ -f docs/specs/_example.md ]  || cp ~/conductor/core/docs-templates/specs/_example.md  docs/specs/
```

### Windows / Git Bash

Same commands, but adjust paths:

```bash
# Clone repo to a Windows path
git clone https://github.com/lee77840/conductor_lfamily /c/conductor
cd /c/Users/me/Projects/my-app

# Then run the same loop
for f in /c/conductor/core/universal-rules/*.md; do
  base=$(basename "$f" .md)
  cp "$f" ".cursor/rules/${base}.mdc"
done
```

> Git Bash translates `C:\Users\me\foo` to `/c/Users/me/foo`. Use forward slashes in commands.

### Frontmatter rewrite (after copy)

For each `.cursor/rules/*.mdc` you just produced, edit the YAML at the top of the file:

```yaml
# BEFORE (Conductor canonical)
---
applies_to: ["**/*.ts", "**/*.tsx"]
always_loaded: false
---

# AFTER (Cursor)
---
globs: **/*.ts, **/*.tsx
alwaysApply: false
---
```

For the universal rules (`meta-discipline.mdc`, `operations.mdc`, `quality-gates.mdc`, `spec-as-you-go.mdc`, `workflow.mdc`) — all `always_loaded: true` upstream — use:

```yaml
---
alwaysApply: true
---
```

### Verification

1. Restart Cursor.
2. Open the Cursor command palette → "Show Loaded Rules" (or check the chat sidebar).
3. Confirm the 5 universal rules (`meta-discipline`, `operations`, `quality-gates`, `spec-as-you-go`, `workflow`) show up, all marked "always".
4. If you also copied the `coding-conventions` recipe, open a `.ts` file → confirm it loads on file context.

### Uninstall

```bash
rm -rf .cursor/rules
rm -f .cursorrules
# docs/* are yours — keep or delete manually
```

---

## Tool 2 — GitHub Copilot (manual, until P2 adapter ships)

GitHub Copilot supports custom instructions via `.github/instructions/*.instructions.md` files, which are picked up by the Copilot extension across **VSCode, Cursor, Windsurf, JetBrains, Neovim** simultaneously (one install covers all five IDEs that have the Copilot extension).

### Mac / Linux / Windows-WSL2

```bash
cd <target>

# 1. Create instructions directory
mkdir -p .github/instructions

# 2. Copy + rename to .instructions.md
for f in ~/conductor/core/universal-rules/*.md; do
  base=$(basename "$f" .md)
  cp "$f" ".github/instructions/${base}.instructions.md"
done

# 3. Build always-loaded baseline (all 5 universal rules)
cat ~/conductor/core/universal-rules/meta-discipline.md \
    ~/conductor/core/universal-rules/spec-as-you-go.md \
    > .github/instructions/all.instructions.md
```

### Windows / Git Bash

Same commands. Substitute `~/conductor` → `/c/conductor` if your clone lives on `C:`.

### Frontmatter rewrite

Open each `.github/instructions/*.instructions.md` and rewrite:

```yaml
# BEFORE
---
applies_to: ["**/*.ts", "**/*.tsx"]
---

# AFTER
---
applyTo: '**/*.ts, **/*.tsx'
---
```

For `all.instructions.md` (always-loaded baseline):

```yaml
---
applyTo: '**'
---
```

> **Copilot CSV pitfall**: the `applyTo:` value MUST be a single quoted string. Array form `applyTo: ['a', 'b']` is silently ignored.

### Verification

1. Restart your IDE.
2. Open Copilot Chat.
3. Edit a `.ts` file and ask "what are the project's TypeScript naming conventions?" — if you copied the `coding-conventions` recipe, the answer should match `coding-conventions.instructions.md`.
4. Confirm Copilot's "Used N references" footer shows the matching `*.instructions.md` file.

### Uninstall

```bash
rm -rf .github/instructions
```

---

## Tool 3 — Gemini CLI (fallback manual install)

> **An adapter now exists** — prefer `bash adapters/gemini/transform.sh <target>`; the manual steps below are a fallback.

Gemini CLI uses a single `GEMINI.md` file (or `~/.gemini/instructions.md` for global). No frontmatter, no globs — everything is one bundle, always loaded.

### Mac / Linux / Windows-WSL2

```bash
cd <target>

# Concatenate all universal rules into GEMINI.md
cat ~/conductor/core/universal-rules/*.md > GEMINI.md

# Optional: add recipes
cat ~/conductor/core/recipes/coding-conventions.md \
    ~/conductor/core/recipes/monorepo.md \
    >> GEMINI.md

# Doc templates (same as Cursor section)
mkdir -p docs/specs
[ -f docs/CURRENT_WORK.md ] || cp ~/conductor/core/docs-templates/CURRENT_WORK.md docs/
# ... (repeat for REMAINING_TASKS, PLANS, TASKS, INDEX, specs/_example)
```

### Windows / Git Bash

Same. Or use PowerShell `Get-Content`:

```powershell
Get-ChildItem C:\conductor\core\universal-rules\*.md |
  Get-Content |
  Set-Content GEMINI.md
```

### Frontmatter rewrite

**None needed**. Gemini ignores YAML frontmatter — it's harmless filler in the bundle. If you want a clean file, delete the `---...---` blocks at the top of each section after concatenation.

### Verification

1. Restart Gemini CLI.
2. Run `gemini list-context` (or check the session preamble) — `GEMINI.md` content should appear.
3. Ask "what is the spec-as-you-go rule?" — answer should cite the universal rule.

### Limitations

- No lazy load — every rule is loaded every turn (token cost higher than Claude/Cursor/Copilot).
- No hooks, no sub-agents (per ADR-004 honesty principle).

### Uninstall

```bash
rm -f GEMINI.md
```

---

## Tool 4 — Codex (OpenAI) (fallback manual install)

> **An adapter now exists** — prefer `bash adapters/codex/transform.sh <target>`; the manual steps below are a fallback.

Codex CLI reads `AGENTS.md` (and historically `.codex/codex.md` — both supported as of 2026-05).

### Mac / Linux / Windows-WSL2

```bash
cd <target>

# Concatenate universal rules
cat ~/conductor/core/universal-rules/*.md > AGENTS.md

# Recipes (optional)
cat ~/conductor/core/recipes/coding-conventions.md >> AGENTS.md

# Doc templates (same pattern as Gemini)
mkdir -p docs/specs
[ -f docs/CURRENT_WORK.md ] || cp ~/conductor/core/docs-templates/CURRENT_WORK.md docs/
# ... (repeat as above)
```

### Windows / Git Bash

Same commands. PowerShell users: see Gemini section's `Get-Content` example.

### Frontmatter rewrite

None — Codex ignores YAML frontmatter. Optional cleanup: strip `---...---` blocks after concat.

### Verification

1. Restart Codex.
2. Verify the session preamble mentions `AGENTS.md`.

### Limitations

- Single bundled file, no per-pattern routing.
- No hooks, no sub-agents.

### Uninstall

```bash
rm -f AGENTS.md
```

---

## Tool 5 — Windsurf (fallback manual install)

> **An adapter now exists** — prefer `bash adapters/windsurf/transform.sh <target>`; the manual steps below are a fallback.

Windsurf reads `.windsurfrules` (always-loaded) plus `.codeium/instructions/*.md` for directory-scoped rules (varies by Windsurf version — verify your version's docs).

### Mac / Linux / Windows-WSL2

```bash
cd <target>

# Always-loaded baseline (all 5 universal rules)
cat ~/conductor/core/universal-rules/meta-discipline.md \
    ~/conductor/core/universal-rules/operations.md \
    ~/conductor/core/universal-rules/quality-gates.md \
    ~/conductor/core/universal-rules/spec-as-you-go.md \
    ~/conductor/core/universal-rules/workflow.md \
    > .windsurfrules

# Directory-scoped (best effort — verify your Windsurf version supports this)
mkdir -p .codeium/instructions
for f in ~/conductor/core/universal-rules/operations.md \
         ~/conductor/core/universal-rules/quality-gates.md \
         ~/conductor/core/universal-rules/meta-discipline.md; do
  cp "$f" ".codeium/instructions/$(basename "$f")"
done
```

### Windows / Git Bash

Same. PowerShell — same pattern as Gemini.

### Frontmatter rewrite

Windsurf rule format is **NOT VERIFIED for v0.2** — check the Windsurf docs for your installed version. As a safe default, leave Conductor frontmatter in place (it is unlikely to harm; worst case Windsurf treats it as text).

### Verification

1. Restart Windsurf.
2. Open Windsurf settings → confirm `.windsurfrules` is detected.
3. Ask the Windsurf assistant about a rule that should be loaded — answer should reflect the rule.

### Limitations

- Per-pattern routing support is version-dependent — likely degrades to "all loaded all the time".
- No hooks, no sub-agents.

### Uninstall

```bash
rm -f .windsurfrules
rm -rf .codeium/instructions
```

---

## Common pitfalls & FAQ

### "I copied the files but the rules don't load"

Most likely causes (in order):

1. **You forgot to restart the IDE.** Every tool reads rule files at session start.
2. **Frontmatter syntax is wrong.** Cursor's `globs:` is CSV (no quotes around the list); Copilot's `applyTo:` is a single quoted string. Check the cheat sheet above.
3. **You put rules in the wrong directory.** Cursor wants `.cursor/rules/`; Copilot wants `.github/instructions/`. A `.cursorrules` file in the project root is also valid for Cursor as a baseline.
4. **The file extension is wrong.** Cursor needs `.mdc` (not `.md`); Copilot needs `.instructions.md` (not `.md`).

### "I need to update Conductor — do I re-copy everything?"

Yes — that is exactly what `bash transform.sh <target>` does. Manual install means you re-do the manual steps after `git pull` in `~/conductor`. This is the main reason to use the adapter when one is available.

### "Can I mix manual install with the adapter?"

Yes. Every tool now has an adapter, but you can still mix (e.g. run `adapters/claude/transform.sh` for Claude and do the manual `cp` steps for Gemini if you prefer). The two write to different directories (`.claude/` vs `GEMINI.md`) so there is no conflict.

### "Windows native PowerShell support?"

Currently unsupported (tracked under ADR-023 as P3+ work). Workarounds:

- **Git Bash for Windows** — POSIX shell on top of MSYS2. Bundled with Git for Windows. Use `bash transform.sh ...` exactly like on Mac.
- **WSL2 (Ubuntu)** — full Linux environment. `bash transform.sh ...` works identically to Mac/Linux.

### "Encoding issues on Windows (CRLF vs LF)?"

Configure git to keep files in LF on disk:

```bash
git config --global core.autocrlf input    # Mac/Linux/WSL
git config --global core.autocrlf false    # Windows-Git-Bash if you commit cross-platform projects
```

Conductor source files are LF + UTF-8. Mixed-line-endings will break the bash scripts (you'll see `\r: command not found` errors).

### "Where do recipes go in manual install?"

Same path as universal rules, but you only copy the recipe files relevant to your project. For example, for a TypeScript monorepo with i18n, copy:

```
core/recipes/coding-conventions.md
core/recipes/monorepo.md
core/recipes/i18n.md
```

into the same tool-specific directory (`.cursor/rules/` for Cursor, etc.).

---

## See also

- [`README.md`](../README.md) — adapter-based install Quick Start (5 minutes).
- [`docs/COMPATIBILITY-MATRIX.md`](./COMPATIBILITY-MATRIX.md) — which features each tool supports natively.
- [`docs/HOW-IT-WORKS-PER-TOOL.md`](./HOW-IT-WORKS-PER-TOOL.md) — under-the-hood explanation per tool.
- [`docs/DESIGN-DECISIONS.md`](./DESIGN-DECISIONS.md) ADR-023 — marketplace + cross-platform strategy.
- [`adapters/<tool>/SUPPORTED-FEATURES.md`](../adapters/) — per-tool feature degradation summary.
