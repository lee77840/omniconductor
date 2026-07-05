# Changelog

All notable changes to CONDUCTOR are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [0.3.0] — 2026-07-05

### Added — Self-improvement / Reflector (opt-in, propose-only)
- **`self-improvement` recipe + `reflector` role** — an opt-in loop that reads recent session trajectories + git history and **proposes** atomic "lessons learned" deltas to `docs/REFLECTION-PROPOSALS.md`. Propose-only: nothing is applied without human approval (honors the VISION "nothing learns silently" non-goal). Recipe count **10 → 11**. — **ADR-030**.
- **Cross-tool emission (all six adapters)** — the Reflector loop ships in each tool's native format: a session-end trajectory-log hook (reads `transcript_path` from the hook stdin, upsert-by-session), a `/reflect` command, a reflector agent (or a `.devin/rules/` manual rule on Windsurf), and a deterministic non-LLM prune script. Recipe-gated, manifest-tracked, uninstall-clean. — **ADR-032**.
- **Weekly scheduling** — a portable `run-weekly.sh` (auto-detects the tool's headless CLI: `claude -p` / `codex exec` / `gemini -p` / `cursor-agent -p` / `copilot -p` / `devin -p`) + `SCHEDULING.md` (per-tool cron/launchd + native-scheduler registration, with the cloud-scheduler-can't-read-local-trajectories caveat). — **ADR-033**.

### Changed
- **Compatibility matrix corrected to 2026 first-party reality** — the prior "hooks / sub-agents / model-routing are Claude-only" matrix was materially out of date; all six tools now ship event hooks, sub-agent dispatch, custom named agents, per-task model routing, and commands. `COMPATIBILITY-MATRIX.md` + the VISION capability table re-rated (verified against first-party sources) with an explicit **capability ≠ CONDUCTOR-emission** disclaimer. Windsurf rebranded to **Devin Desktop**; the adapter's rules target moved to `.devin/rules/` (legacy `.windsurf/rules/` still read). — **ADR-031**.
- The Claude trajectory-log hook reads `transcript_path` from the Stop hook's **stdin** (exact provenance) instead of scanning `~/.claude/projects` for the newest transcript.

### Notes
- The remaining workflow guards (`agent-routing`, commit / large-file guards) stay **Claude-only** pending a hook-config-merge redesign — a first-party feasibility study found them Claude-specific or blocked by a single-config-file JSON-merge issue. — **ADR-034**.

## [0.2.0] — 2026-06-28

First release with all six adapters working, an install CLI, and CI. CONDUCTOR
generalizes a production-tested AI-coding workflow (rules / roles / hooks /
recipes / memory pattern) and installs it into six AI coding tools from one
tool-agnostic `core/`.

### Added
- **Six working adapters** — `adapters/<tool>/transform.sh` for **Claude Code, Cursor, GitHub Copilot, Gemini CLI, Codex, Windsurf** (Gemini/Codex/Windsurf new this release). Each supports `--recipes`, `--dry-run`, `--no-prompt`, manifest-tracked `--uninstall`, and emits its tool's native format (Codex → `AGENTS.md`).
- **`omniconductor`** (`bin/omniconductor.js`) — dependency-free `npx omniconductor init --target=<tool>` dispatcher to the adapter scripts, plus `list` / `--dry-run` / `--uninstall`.
- **CI** (`.github/workflows/validate.yml`) — on every push/PR: framework-purity check, a 6-adapter install+validate matrix, and a CLI smoke test.
- **Validator** (`tools/validate-adapter-output.sh`) extended to all six adapters (structural + placeholder + reference-product-leak checks).
- **Kernel generalization (Spec 1)** — folded reusable kernels from the originating production project into `core/`, vendor-neutral:
  - `core/recipes/database-discipline.md` (RLS-everywhere, idempotent migrations, pre-apply prod drift verification) and `core/recipes/design-system.md` (tokens-not-literals) — recipe count 8 → **10**.
  - Recipe-scoped hookify mechanism (`.recipe-scoped` map gated in the Claude adapter) — **ADR-028**.
  - `block-server-secret-in-client` always-on hookify (generalized server-secret-in-client guard) — **ADR-027**.
  - No-False-Completion discipline folded into `quality-gates.md` §4.4/§4.5; commit-time PreToolUse hooks (`pretool-commit-current-work-check`, `pretool-commit-test-coverage-check`, soft `ask`); `block-direct-push-protected-branch` (opt-in).
- **Real example** — `examples/sample-claude-project/` (a real claude install snapshot) + regeneration notes.
- **CHANGELOG.md** (this file).

### Changed
- **License: MIT → Apache 2.0 (code) + CONDUCTOR-name trademark** (© LFamily Labs LLC) — **ADR-029**, supersedes ADR-007. Fully open and free, commercial use included (build & sell your own products with it). The **CONDUCTOR** name is a trademark — forks must rename and keep attribution (NOTICE / TRADEMARKS.md); you cannot pass off a modified copy as the original. Done before any public distribution.
- All P1.7 hooks (`pretool-large-file-read-guard`, `stop-cache-hit-baseline-check`) committed and registered — installs now wire **7** hooks.
- `package.json`: name `omniconductor`, semver `0.2.0`, `bin` + `files` + repo metadata. **Published to npm** — `npx omniconductor init --target=<tool>` works anywhere.
- User-facing docs (`README`, `VISION`, `ROADMAP`) bilingual (한/영) top-up; install commands are `bash adapters/<tool>/transform.sh` (the `npx` CLI is the convenience wrapper).

### Fixed
- **Full doc-freshness audit** brought every count/claim into consistency: rule names (`token-economy`/`model-routing` → folded into `meta-discipline`; `coding-conventions` → recipe), agent count (8 source → **6 roles**), hooks (3 → **7**), recipes (6 → **10**), ADRs (→ **28**), 404 install paths, `npx` → `bash`, and the non-existent `settings.template.json` → generated `settings.json`. Cross-repo references in installed rules qualified as upstream.

### Known limitations
- **Published to npm as `omniconductor`** — `npx omniconductor init --target=<tool>` (or clone + `bash adapters/<tool>/transform.sh`). https://www.npmjs.com/package/omniconductor
- Gemini/Codex/Windsurf adapters are verified for **file emission + structure**, not yet for live runtime consumption by those tools (see `docs/ADAPTER-LIVE-VERIFICATION.md`).
- VSCode extension (`phase-2/`) is a scaffold; not built/listed on a marketplace.

## [0.1.0] — archived
Claude-Code-only scaffold, preserved under `archive/v0.1/` (installable via `archive/v0.1/install.sh`).

---

### Cutting the GitHub release (maintainer — user-triggered)
```bash
git tag -a v0.2.0 -m "CONDUCTOR v0.2.0 — six adapters, CLI, CI"
git push origin v0.2.0
gh release create v0.2.0 --title "v0.2.0" --notes-file <(sed -n '/## \[0.2.0\]/,/## \[0.1.0\]/p' CHANGELOG.md)
```
