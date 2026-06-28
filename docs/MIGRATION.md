# MIGRATION — switching tools mid-project

How to keep your CONDUCTOR discipline when you change which AI coding tool you use on a project.

---

## Common scenario A — Claude Code → Cursor

**Why this happens**: You started with Claude Code for deep refactor work. Now you're on a streak of UI iteration and you want Cursor's in-IDE pair-programming.

### Steps

1. **Run the Cursor adapter.** From the project root:
   ```bash
   bash adapters/cursor/transform.sh <target>
   ```
   This generates:
   - `.cursorrules` (always-loaded baseline)
   - `.cursor/rules/*.mdc` (5 universal rules with appropriate `globs:`)
   It does NOT touch `.claude/`, `CLAUDE.md`, or `docs/`.

2. **Open Cursor.** Cursor auto-loads `.cursorrules` at session start and the matching `.mdc` files when you touch matching files.

3. **(Optional) Add CONDUCTOR's orchestrator manual to your Cursor session prompt template.** Cursor lacks sub-agent dispatch, so the human plays orchestrator. The `.cursorrules` file already includes the manual; you can paste relevant sections into your first prompt for a complex task.

4. **Continue using `docs/CURRENT_WORK.md`, `docs/specs/*.md`, etc.** These files are tool-agnostic — Cursor reads them the same way Claude does.

### What you need to manually preserve

- **Two-stage code review.** Cursor cannot block your commit. Run the review prompts manually before each commit using Cursor's chat: paste the diff, ask the chat to review against `coding-conventions` and `spec-as-you-go`. Then commit.
- **Spec-as-you-go.** Same — Cursor cannot block. The `.mdc` rule for `docs/specs/**` reminds you when you touch a spec file, but enforcement is on you.
- **Model routing.** Cursor uses one model per session. Pick the right model in the Cursor UI when starting a complex task; you cannot switch mid-session via a `model:` argument.

### What you keep automatically

- All universal rule text (meta-discipline, operations, quality-gates, spec-as-you-go, workflow).
- All doc templates in `docs/`.
- The Plan → Architecture → Tasks → Implementation → Review → Spec workflow definition.
- Memory pattern (move `~/.claude/projects/<encoded>/memory/` content to your DIY memory directory if you want).

---

## Common scenario B — Claude Code → GitHub Copilot

**Why this happens**: You're collaborating in a corporate environment that mandates Copilot, or you want Copilot's PR review automation tied to GitHub.

### Steps

1. **Run the Copilot adapter.**
   ```bash
   bash adapters/copilot/transform.sh <target>
   ```
   Generates `.github/copilot-instructions.md` (and `.github/instructions/*.instructions.md` in `--per-rule` mode) with `applyTo:` front-matter.

2. **Commit the `.github/instructions/` directory.** Copilot reads instructions from the repo, so all collaborators automatically get the same rule context.

3. **Use Copilot's PR review feature for Stage B.** It is the closest analog to CONDUCTOR's `/code-review` slash command. Configure it to automatically request review on your PRs.

### What you need to manually preserve

- **Sub-agent dispatch and Stage A pre-commit review.** Copilot doesn't block commits. Run review prompts manually in Copilot Chat before commit.
- **Per-call model routing.** Copilot Chat lets you pick model in UI; not programmatic.

---

## Common scenario C — Cursor → Claude Code

**Why this happens**: You started with Cursor and discovered the multi-file refactor needs are too painful without sub-agents.

### Steps

1. **Run the Claude adapter.**
   ```bash
   bash adapters/claude/transform.sh <target>
   ```
   Generates `CLAUDE.md`, `.claude/agents/*`, `.claude/rules/*`, `.claude/hooks/*`, and `.claude/settings.json`.

2. **Review the generated `.claude/settings.json` and customize if needed.** It is written directly by `transform.sh` with a permissions allowlist + hooks registry; the Stop hooks for spec-as-you-go and two-stage code review are wired here. Per-user overrides go in `.claude/settings.local.json` (gitignored).

3. **Restart Claude Code.** Verify with `/help` that the new agents are recognized.

4. **Decide whether to remove Cursor files.** You can:
   - Keep both (Cursor for in-IDE chat, Claude for orchestrated work) — multi-tool installs coexist.
   - Remove `.cursor/` and `.cursorrules` if the project is now Claude-only.

### What you GAIN

- Sub-agent dispatch.
- Stop hook ABSOLUTE enforcement of spec-as-you-go.
- PreToolUse routing.
- Per-call model routing.
- Built-in memory directory.

### What needs no migration

- All `docs/` content stays identical.
- All universal rule TEXT is the same; only the file format and location differ.

---

## Common scenario D — Run multiple tools on the same project

**Why this happens**: Most realistic — you use Claude for big refactors, Cursor for UI work, Copilot for PR review automation, all on the same repo.

### Steps

```bash
bash adapters/claude/transform.sh <target>
bash adapters/cursor/transform.sh <target>
bash adapters/copilot/transform.sh <target>
```

All three generate non-overlapping files (see `docs/HOW-IT-WORKS-PER-TOOL.md` for paths). They coexist.

### Discipline note

Updating a universal rule means re-running every adapter you use, OR editing each tool's adapter output by hand. P3 may add a `--target=all` flag to re-run every adapter at once; until then, repeat the install command per tool.

---

## Migration cheat sheet

| Going from | To | Command | Manual work |
|---|---|---|---|
| Claude | Cursor | `init --target=cursor` | Self-police spec + review (no hooks) |
| Claude | Copilot | `init --target=copilot` | Configure Copilot PR review for Stage B |
| Claude | Gemini | `init --target=gemini` | All rules become single bundle; lose per-pattern scoping |
| Claude | Codex / Windsurf | `init --target=codex` / `--target=windsurf` | Same as Gemini, plus more manual orchestrator role |
| Cursor / Copilot / Gemini / Codex / Windsurf | Claude | `init --target=claude` | Copy + customize settings.json; restart Claude Code |
| Anything | Anything (add tool) | `init --target=<new>` | New files generated; existing tool files untouched |

## Things that NEVER need migration

- `docs/CURRENT_WORK.md`
- `docs/REMAINING_TASKS.md`
- `docs/specs/*.md`
- `docs/PLANS.md` / `docs/TASKS.md` / `docs/INDEX.md`
- The Plan → Architecture → Tasks → Implementation → Review → Spec workflow
- Your accumulated memory entries (just point your new tool's prompt at them)

The whole point of CONDUCTOR is that the *project's* discipline is portable. The tool changes; the project doesn't have to.
