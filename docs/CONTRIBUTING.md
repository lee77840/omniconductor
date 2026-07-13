# CONTRIBUTING — CONDUCTOR

How to add a new tool adapter, fix a bug, or improve a universal rule.

---

## Quick start

1. Fork the repo.
2. Create a branch off `main`: `feat/<short-description>` or `fix/<short-description>` or `chore/<short-description>` or `adapter/<tool-name>`.
3. Make your changes following the conventions below.
4. Open a PR against `main`. Describe WHAT changed and WHY.

Validation is local-first. Run the verification steps below and the integrated
`npm run release:verify:local` gate. GitHub workflow definitions are retained only
as disabled, manual release checks; pushes and pull requests do not invoke them.

---

## What you can contribute

### A. New tool adapter

The most valuable contribution. Adds support for an AI coding tool not currently covered.

### B. Bug fix in an existing adapter

A `transform.sh` produces wrong output, breaks on certain projects, or generates files at the wrong path.

### C. Improvement to a universal rule

You found a real production incident that the existing rule didn't catch. Update `core/universal-rules/<rule>.md` with the new clause + 1-line citation of the incident pattern.

### D. New universal rule

Rare. Discuss in an issue first — universal rules add load to every adapter and every user.

### E. Documentation improvement

Always welcome. Especially translations (한/영 first; we are open to other languages but cannot maintain them — community-maintained translations get a `community-translation` label).

---

## Adding a new tool adapter

This is the most common substantial contribution. Steps:

### Step 1 — Verify the tool isn't already supported

Check `adapters/<tool>/` and `docs/COMPATIBILITY-MATRIX.md`. If a stub exists but the implementation is incomplete, see Step 4.

### Step 2 — Open an issue first

Title: `Adapter request: <tool name>`. Body must include:
- Tool name + canonical URL.
- The tool's rules-file format (file paths, supported scoping, front-matter syntax).
- The tool's sub-agent / hooks / model-routing capabilities (or absence).
- Why CONDUCTOR users want this tool (1-2 sentences).

Wait for maintainer ack before writing code (avoid duplicate work).

### Step 3 — Add adapter directory

```
adapters/<tool>/
├── README.md                 # Tier (T1/T2/T3) with reasoning
├── SUPPORTED-FEATURES.md     # Detailed feature support breakdown
├── transform-spec.md         # What transform.sh must do
└── transform.sh              # The actual transformer (Bash)
```

Use any existing adapter directory as a template (`adapters/cursor/` is a good Tier-1 reference).

### Step 4 — Adapter contract

Your `transform.sh` MUST:

- **Input**: read from `core/` directory (relative paths from the conductor repo root).
- **Output**: write tool-native files at the conventional path for that tool, into a target directory passed as argument.
- **Idempotent**: safe to re-run. Existing files at target paths must NOT be overwritten — skip and report.
- **Dry-run**: support a `--dry-run` flag that prints what WOULD be written without touching disk.
- **No telemetry**: no network calls except when the user explicitly initialized the tool's auth. (CONDUCTOR itself is telemetry-free per ADR-008.)
- **Bash 4+ compatible**: assume macOS Bash (older) and modern Linux Bash. Use POSIX-friendly constructs where possible.

Verification before opening PR:

```bash
# In a fresh sandbox project:
mkdir /tmp/test-conductor-<tool>
cd /tmp/test-conductor-<tool>
git init
/path/to/conductor/adapters/<tool>/transform.sh
# Verify: files at expected paths, content matches universal rules.
# Open the project in <tool>. Verify rules load as expected.
# Document any quirks discovered in adapters/<tool>/notes.md.
```

### Step 5 — Update docs

The same PR must also:
- Add a row to `docs/COMPATIBILITY-MATRIX.md` for the new tool.
- Add a section to `docs/HOW-IT-WORKS-PER-TOOL.md`.
- Update the README.md tier table (top section).

If you don't update these docs, the PR will be requested-changes for missing test-coverage-sync (we treat docs as test coverage for the framework).

---

## Code style

### Bash scripts

- `set -euo pipefail` at the top of every script.
- Use `[[ ]]` for conditionals, not `[ ]`.
- Quote all variable expansions: `"$VAR"`, never `$VAR`.
- Local variables: `local foo` inside functions.
- One responsibility per function.
- Comments explain WHY, not WHAT.

### Markdown

- ATX headings (`#`, `##`, `###`).
- Tables for any 2+ column comparison.
- Code blocks with language hint.
- No trailing whitespace.
- One blank line between sections.

### File naming

- Adapter scripts: `transform.sh` (lowercase).
- Adapter docs: `README.md`, `SUPPORTED-FEATURES.md`, `transform-spec.md`, `notes.md` (uppercase except `notes.md`).
- Universal rules: lowercase, hyphenated: `coding-conventions.md`, `spec-as-you-go.md`.

### Commit message format

```
<type>: <short summary in present tense, lowercase, no trailing period>

<optional body explaining WHY>

<optional footer with breaking changes / refs>
```

`<type>` is one of: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`. Examples:

- `feat(adapter/cursor): add transform.sh and rule scoping spec`
- `fix(adapter/claude): handle missing core/universal-rules gracefully`
- `docs: update COMPATIBILITY-MATRIX.md for windsurf P3.5 status`

---

## PR checklist

Before requesting review:

- [ ] Branch is off `main` and named `feat/*`, `fix/*`, `chore/*`, or `adapter/*`.
- [ ] Adapter PRs include `transform.sh` + `transform-spec.md` + `SUPPORTED-FEATURES.md` + `README.md` + matrix update + HOW-IT-WORKS section.
- [ ] Verified locally on a fresh sandbox project (paste verification commands + output in PR body).
- [ ] No telemetry / no network calls added.
- [ ] No license change.
- [ ] Bilingual user-facing docs (한/영) where headline material was bilingual already.

---

## Reviewer workflow (for maintainers)

For each PR:

1. **Adapter contract verification** — does `transform.sh` match the spec in `adapters/<tool>/transform-spec.md`?
2. **Idempotency check** — run twice on the same target; second run should report "skipped, already exists".
3. **Path collision check** — install alongside other adapters; verify no collisions.
4. **Doc sync check** — matrix + HOW-IT-WORKS updated.
5. **Code style** — Bash strict mode, quoted expansions, and no shellcheck warnings when shellcheck is available locally.

Do NOT merge if:
- Adapter introduces telemetry.
- Adapter requires a runtime not already in the foundation set (Bash, basic POSIX utilities).
- Doc updates are missing.

---

## Code of Conduct

CONDUCTOR is opinionated but the community is collaborative. Be specific in critique; be generous in interpretation. Disagreements about which tools deserve T1 vs T2 are welcome — those are real product decisions and we want the conversation. Personal attacks are not.

If a PR is rejected, the maintainer owes the contributor a clear reason and (if applicable) a concrete path forward. "Not aligned with roadmap" is not a sufficient reason; cite the specific clause from `VISION.md` / `docs/PHILOSOPHY.md` / `docs/DESIGN-DECISIONS.md` that the PR conflicts with.

---

## Questions

Open an issue. We do not have Discord / Slack yet (post-v1.0). All discussion is in GitHub issues for the audit trail.
