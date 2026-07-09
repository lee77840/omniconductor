# Changelog

All notable changes to CONDUCTOR are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [Unreleased]

## [0.7.0] — 2026-07-09

### Added — anti-drift guards (audit follow-up #3 + #2 slice 1)
- **CI stale-token + version-stamp check** — `tools/check-stale-tokens.sh` + data file `tools/stale-tokens.txt` (`pattern⇥reason⇥hint⇥allow_regex`, inline `stale-ok:` waivers) as a new CI job. Class A mechanizes the R7 stamps (README status line must stamp the exact `package.json` version — **now re-stamped on every release, patches included**; CHANGELOG must have the section). Class B fails CI on known-false claims (seeded ~15 tokens from the verified drift inventory: `.codex/codex.md`-as-current, unqualified `.windsurf/rules`, "no npx", "❌ No hooks/sub-agents", "Single model per session", …). Process rule: a change that flips a fact adds the now-false claim to the token list in the same PR. — **ADR-039**.
- **Adapter metadata single-source** — `adapters/<tool>/metadata.json` ×6 (outputs / reflector outputs / legacy paths / tier / two-axis capabilities per ADR-031 / live-verification / headless CLI) + `tools/check-adapter-metadata.sh` CI job asserting 8 invariants (paths exist in `transform.sh` and the validator; legacy paths handled in code; verified-status dates single-sourced in `docs/ADAPTER-LIVE-VERIFICATION.md`; headless CLIs known to `run-weekly.sh`; matrix tier rows agree). The bash transforms stay dependency-free — metadata validates them, never drives them (ADR-002/023/025). — **ADR-040**.

### Fixed (residual doc drift the 0.6.1 point-fix missed — found by re-verification + the new checker itself)
- **5 non-Claude adapter READMEs** rewritten to the ADR-031 capability-vs-emission framing (were still "❌ No sub-agent / No hooks / single model" as tool limitations, with pre-P1 rule names in the install trees, "npx not yet available", and a **Codex tier contradiction (README said T3, matrix says T2)**); Reflector emission (`--recipes=self-improvement`) now documented per adapter.
- **`core/**` reference tables** — `.codex/codex.md` → `AGENTS.md` and `.windsurf/rules/` → `.devin/rules/` in universal-rules/recipes READMEs, spec-as-you-go, anti-pattern examples; meta-discipline cross-tool enforcement table de-staled.
- **docs/** — ARCHITECTURE (adapter output map, always-loaded row, orchestrator paragraph), INDEX (package row, adapter rows, Codex live-verified, P4 row: npm published), MANUAL-INSTALL (all-6-adapters decision table, "until adapter ships" headers, "No hooks, no sub-agents" limitations), MIGRATION (modern `.mdc` flow, guard-hook phrasing), HOW-IT-WORKS (Gemini/Windsurf lost-feature tables), VISION (`.devin/rules/` tree).
- **First machine-scan catches** (missed by two human sweeps + a 3-agent verification pass): `adapters/codex/transform-spec.md` body still specced `.codex/codex.md`, `VISION.md` tree, and two "(planned / roadmap — not yet available): npx …" blocks in adapter READMEs — including a claude README pointer to the retired v0.1 archive installer.

### Changed
- Version-stamp policy: patch releases now re-stamp the README status line (supersedes the 0.6.1 "feature-baseline stamp" stance) — enforced by CI. — **ADR-039**.
- README's "New in" blockquote now carries only the current release (older summaries drift and were an unguarded second changelog); history lives here.

### Notes
- **npm registry skips 0.6.1**: 0.6.1 was tagged + released on GitHub but never `npm publish`-ed; the registry goes 0.6.0 → 0.7.0 directly. Everything in 0.6.1 is contained in 0.7.0.

## [0.6.1] — 2026-07-09

### Fixed (documentation + adapter output truth-source; from an external audit)
- **Manifest version bug** — all 6 adapters hardcoded `"version": "v0.2.0"` in the emitted `.conductor-manifest.json`; now read dynamically from `package.json` (installs stamp the real version). Fixes bogus install-history / rollback / bug-report data.
- **Adapter capability strings** — Codex/Gemini/Windsurf/Copilot emitted output claimed the tool has "no hooks / no sub-agents / single model"; corrected to the ADR-031 *capability vs CONDUCTOR-emission* framing (the tools support these; CONDUCTOR emits rule text + the Reflector loop, full emission Phase 2).
- **Doc drift to v0.6.0 reality** — README/ROADMAP/COMPARISON/HOW-IT-WORKS/ARCHITECTURE/VISION/COMPATIBILITY-MATRIX/ADAPTER-LIVE-VERIFICATION/SUPPORTED-FEATURES: all 6 tools have working adapters (not "adapter-less"), npm package exists (no "no npx"), Codex output is `AGENTS.md` (not `.codex/codex.md`), Windsurf emits `.devin/rules/` (not "pending"), Codex is live-verified (single-sourced across docs), Claude hook count reconciled (10 hooks / 5 PreToolUse + 5 Stop).
- **npm completeness** — `package.json` `files` now ships the docs the README links to (COMPATIBILITY-MATRIX, ADAPTER-LIVE-VERIFICATION, PUBLISH-GUIDE, DESIGN-DECISIONS, COMPARISON), so npm-installed users don't hit dead links.

## [0.6.0] — 2026-07-07

### Added
- **`loop-engineering` recipe + `pretool-loop-guard` PreToolUse hook** — opt-in discipline for bounded, externally-verified agent loops (G1–G6): explicit done-criterion, iteration+token budget, require-progress, escalate-on-stall, **verify externally never by self-judgment**, oscillation/infinite-loop guard. Grounded in a 5-source verification pass (Huang/DeepMind "Cannot Self-Correct Yet", CRITIC, Reflexion, "When Agents Do Not Stop", Anthropic *Building Effective Agents* — verify hierarchy rules/tests > visual > LLM-judge). The Claude hook is a non-blocking `permissionDecision: ask` soft-warn that self-gates on the recipe, detects same-action-repeat / runaway tool-call budget, is fail-open, and honors `CONDUCTOR_SKIP_LOOP_GUARD` / `CONDUCTOR_LOOP_REPEAT_MAX` / `CONDUCTOR_LOOP_BUDGET` / `CONDUCTOR_LOOP_COOLDOWN_SECONDS`. Recipe count **12 → 13**, hook templates **9 → 10**. Hook is Claude-only (ADR-034); other tools use the rule text. — **ADR-038**.

## [0.5.0] — 2026-07-07

### Added
- **`git-hygiene` recipe + `stop-git-hygiene-guard` Stop hook** — opt-in shared-repo discipline (G1–G7): no unrequested worktrees, push-don't-hoard, merge=delete-branch, backup≠applied (verify by real code), no reckless force/rebase on shared repos, bundle PRs for CI, session-end hygiene check. Prevents the failure where merged work *looks* lost (orphan worktrees / local-only commit hoarding / stale merged branches) and burns reconciliation time. Recipe body installs on all six tools; the Stop-hook reminder is Claude-only (ADR-034), non-blocking, self-gated on the recipe. Recipe count **11 → 12**, hook templates **7 → 9** (the 0.3.0 `stop-trajectory-log` count was also un-synced). — **ADR-037**.

## [0.4.1] — 2026-07-06

### Fixed (docs)
- **README status line** corrected to **v0.4.0** and the instruction-fidelity token-economy work re-labelled from "unreleased" to shipped (it landed in 0.4.0) — the 0.4.0 npm package page had still shown v0.3.0.
- **Public GitHub Releases backfilled** (v0.3.0, v0.4.0) so the repo's Latest release matches the npm version.

## [0.4.0] — 2026-07-05

### Added — Token-economy: instruction-fidelity-first
- **Lossless-before-lossy context reduction** — `meta-discipline.md` §5.7 rewritten to prefer clearing stale tool results (never touches user instructions) over lossy summarization, with four mandatory compaction safeguards (durable instructions in CLAUDE.md, explicit `/compact` preservation, `/clear` between tasks, re-verify after compaction). New `docs/CONTEXT-EDITING-GUIDE.md` (Claude-only) documents the API context-editing mechanism + memory tool, primary-source cited. — **ADR-035**.
- **Output brevity** — new `meta-discipline.md` §5.9 + **Anti-Pattern 08 (`output-verbosity-narration`)**: answer-first, no re-printed file bodies, right-sized format (output is ~5× input), with an explicit fidelity guard. Anti-pattern count **7 → 8**. — **ADR-036**.
- **Referenced-fact currency rule** — `spec-as-you-go.md` §2.2: when a change alters a fact other docs state (a count / list / table / version / cross-reference), grep for the old value and update **every** place in the same turn, or record a new fact that has no home.
- **npm now ships the guides** — `docs/PROMPT-CACHING-GUIDE.md` + `docs/CONTEXT-EDITING-GUIDE.md` added to the package `files` allowlist (the token-economy rules reference them).

### Changed
- **`meta-discipline.md` §5.5** — concrete Tool Search Tool `defer_loading` guidance (>85% tool-context reduction); mirrored into Anti-Pattern 07.
- **`meta-discipline.md` §6** — current model lineup/pricing snapshot; §6.4 recast as a fidelity rule (cheaper models guess missing params where Opus asks). — **ADR-036**.
- **Anti-Pattern 04 (`no-sub-agent-dispatch`)** — honest caveat: dispatch saves the *lead's* context and improves fidelity via isolation, but *raises* total tokens (~4×/15×). — **ADR-036**.
- **Anti-Pattern 03 (`single-monolithic-rule-file`)** — adds the fidelity axis (attention-budget / context-rot dilution, "minimal ≠ short", cache-vs-attention placement). — **ADR-036**.
- **README brought to current 0.4.0 state** — tool-coverage matrix corrected to *tool-capability vs CONDUCTOR-emission* (all six tools ship hooks / sub-agents / model routing; only emission is Claude-only today — ADR-031); status line, recipe counts, and the self-improvement + token-economy features surfaced.
- **Public-facing URLs** — README clone commands and `package.json` `repository` / `homepage` / `bugs` now point to the public repo (`omniconductor`) instead of the private working repo, so npm and public-README users get working links.

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
