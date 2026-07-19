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
   - `.cursor/rules/*.mdc` (5 universal rules with `alwaysApply: true`; recipes glob-scoped)
   - `.cursorrules` only if you pass `--legacy-cursorrules` (Cursor < 0.45)
   It does NOT touch `.claude/`, `CLAUDE.md`, or `docs/`.

2. **Open Cursor.** Cursor auto-loads the `alwaysApply` rules at session start and the glob-matched `.mdc` files when you touch matching files.

3. **Use the emitted Cursor roles.** Full/strict installs create eight `.cursor/agents/*.md` profiles. Select planner/builder/reviewer/code-reviewer/utility as the task moves through its phases and difficulty.

4. **Continue using `docs/CURRENT_WORK.md`, `docs/specs/*.md`, etc.** These files are tool-agnostic — Cursor reads them the same way Claude does.

### What you need to manually preserve

- **Two-stage code review.** CONDUCTOR does not emit an unverified commit-blocking
  guard for Cursor. Invoke the emitted `code-reviewer` agent before commit, then use
  Cursor's native review surface or the same agent again for the PR.
- **Spec-as-you-go.** Same — Cursor cannot block. The `.mdc` rule for `docs/specs/**` reminds you when you touch a spec file, but enforcement is on you.
- **Model routing.** Run `omniconductor models configure --target=cursor .` once. CONDUCTOR writes the saved Tier mapping into Cursor's native agent profiles; the provider may still apply account, plan, or administrator fallback.

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

- **Stage A pre-commit blocking.** CONDUCTOR emits the `code-reviewer` agent but does
  not claim a repository-local hook that blocks a Copilot commit. Invoke the agent
  before commit and keep the review result with the task evidence.
- **Model policy.** Run `omniconductor models configure --target=copilot .` once.
  The saved exact model is written into each repository agent, while account, plan,
  client, and organization policy remain authoritative.

---

## Common scenario C — Cursor → Claude Code

**Why this happens**: You want Claude's full verified guard set or its native project
memory while keeping the same eight-role topology already available in Cursor.

### Steps

1. **Run the Claude adapter.**
   ```bash
   bash adapters/claude/transform.sh <target>
   ```
   Generates `CLAUDE.md`, `.claude/agents/*`, `.claude/rules/*`, `.claude/hooks/*`, and `.claude/settings.json`.

2. **Review the generated `.claude/settings.json` and customize if needed.** It is written directly by `transform.sh` with the official Hookify project dependency, a permissions allowlist, and the core hook registry; the Stop hooks for spec-as-you-go and two-stage code review are wired here. Existing valid settings receive only the missing Hookify key and missing core-hook registrations through a reversible merge; existing keys and hook options stay intact. Per-user overrides go in `.claude/settings.local.json` (gitignored). On a new machine, approve/install Hookify once and run `/reload-plugins`. If this project settings file is edited after installation, checksum-safe uninstall preserves the whole edited file; consequently the merged Hookify key/core-hook entries may remain and should be removed manually if they are no longer wanted.

3. **Restart Claude Code.** Verify with `/help` that the new agents are recognized.

4. **Decide whether to remove Cursor files.** You can:
   - Keep both (Cursor for in-IDE chat, Claude for orchestrated work) — multi-tool installs coexist.
   - Remove `.cursor/` and `.cursorrules` if the project is now Claude-only.

### Claude-specific differences

- Full verified Stop/PreToolUse guard set rather than Cursor's narrower emitted hook set.
- Claude's native project memory directory.
- Claude family aliases from the same saved Tier 1/2/3 configuration.
- The role topology and difficulty classification do not change during migration.

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

Updating a universal rule means re-running every adapter you use. Use
`init --target=all` to refresh all six, or target only the adapters installed in
the project. Avoid hand-editing managed output because checksums intentionally
surface local divergence.

---

## Migration cheat sheet

| Going from | To | Command | Manual work |
|---|---|---|---|
| Claude | Cursor | `init --target=cursor` | Native role profiles; spec/review checks without verified Cursor guards remain workflow obligations |
| Claude | Copilot | `init --target=copilot` | Configure Copilot PR review for Stage B |
| Claude | Gemini | `init --target=gemini` | All rules become single bundle; lose per-pattern scoping |
| Claude | Codex | `init --target=codex` | Bounded always-loaded kernel plus complete on-demand references; no glob scoping |
| Claude | Windsurf | `init --target=windsurf` | Rules load from `.windsurfrules` / `.devin/rules`; roles are invocable workflows |
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
