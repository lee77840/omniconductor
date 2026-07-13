# Changelog

All notable changes to CONDUCTOR are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [Unreleased]

## [1.1.0] — 2026-07-13

### Added — one-time six-tool model setup

- **First-install model wizard** — `omniconductor init` now presents one summary
  for all selected adapters, accepts the recommended Tier 1/2/3 mappings with one
  confirmation, and asks three values only for adapters the user customizes.
- **Project-saved routing state** — `.conductor/model-routing.json` records a
  revisioned, adapter-validated mapping plus configured-vs-enforced metadata.
  `omniconductor models show/configure` inspects or explicitly changes it;
  installed native roles are regenerated while preserving immutable Tier triggers.
- **Strict automation contract** — unconfigured `--no-prompt` role installs fail
  before managed writes. Non-interactive automation opts in with
  `--accept-model-defaults`. Dry-run remains
  zero-write, recipes-only remains model-independent, and all six public
  `transform.sh` entry points delegate to the same Node setup transaction. Each
  adapter also reloads the saved mapping immediately before writes, so forged child
  markers and inherited model environment values cannot bypass setup or replace it.
- **Provider-native defaults** — Claude recommends Opus/Sonnet/Haiku; Codex
  Sol/Terra/Luna plus high/medium/low effort; Gemini pro/flash/flash-lite; Cursor
  and Copilot saved exact native fields with provider-policy caveats; Windsurf
  Adaptive is explicitly `advisory-session`, never falsely marked enforced.
- **Routing and path safety suite** — customization, missing-config fail-closed
  behavior, transactional role/manifest refresh, forced-failure rollback, crash
  recovery, stale-lock reclamation, installed concurrency, user-edit conflicts,
  manifest traversal, managed-surface containment, symlink/hardlink rejection,
  forged dispatch environment/FD attempts, reinstall, and uninstall-choice retention
  are regression-tested by the local suite and retained in the manual Linux CI
  definition.
- **Local release and real npm-upgrade gate** — `npm run release:verify:local`
  runs the complete regression suite, static checks, exact packed-candidate fresh
  install, all-six validation/doctor/uninstall, published `1.0.1` → candidate
  upgrades for six single-tool projects and a legacy six-tool project, and
  `npm publish --dry-run`. A clean-tree strict mode also verifies the filtered
  public snapshot. It never pushes, dispatches GitHub Actions, or publishes.
- **Manual-only GitHub workflows** — both Actions definitions now accept only
  `workflow_dispatch`; their remote state remains disabled and there is no scheduled
  reactivation. Local validation is required, with optional manual CI only directly
  before a necessary release.

### Fixed — multi-tool runtime hardening
- **Vendor-neutral difficulty routing** — the unchanged Tier 1/2/3 task
  thresholds now live in universal `difficulty_tier` metadata. Before role emission,
  the CLI saves each selected adapter's explicit Tier translation: Claude family
  aliases; Codex Sol/Terra/Luna plus high/medium/low reasoning; Gemini semantic
  aliases; exact Cursor/Copilot native model fields with provider-policy caveats;
  and an honest Windsurf Adaptive session advisory. Model selection never changes
  the immutable task classification.
- **Independent ownership for all six adapters** — authoritative manifests now live at
  `.conductor/manifests/<adapter>.json`; the root manifest is an aggregate projection.
  Sequential installs, repeat installs, scoped uninstall, and `--target=all` no longer
  overwrite another adapter's ownership or remove shared files still in use.
- **Order-independent reinstall/uninstall ownership** — an idempotent reinstall now
  carries forward every still-present owned entry, and every baseline adapter imports
  the original shared docs/profile ownership record. Manifest ownership remains stable
  across repeat installs, and removing adapters in either install or reverse order
  leaves zero managed residue while retaining the original user backup chain.
- **No untracked `.gitignore` mutation** — Reflector trajectory payloads are ignored by
  the managed `.conductor/trajectories/.gitignore`; the installer no longer appends an
  unmanifested block to the adopter's top-level `.gitignore`, preserves a user-owned
  nested ignore file, and removes the exact legacy CONDUCTOR block during migration.
- **Native runtime contracts and roles** — all adapters emit eight verified role entry
  points including a distinct post-implementation `code-reviewer` and Tier 3 `utility`. Codex emits native
  agent TOML plus its verified `PreToolUse`/`Stop` subset and never activates Claude's
  unsupported `permissionDecision: "ask"` contract.
- **Fail-closed managed paths and atomic model refresh** — installers reject
  symlinked/hard-linked managed roots and leaves plus untrusted manifest paths before
  mutation. Model changes verify manifest ownership/checksums, journal the old config,
  role files, and manifests under one lock, commit config last, and recover the last
  complete state after failure or process death. Installation holds the same lock
  through every real adapter write, including cross-mode recipes-only updates,
  preventing a concurrent reconfiguration from leaving saved routing and emitted
  roles on different revisions. Doctor derives routing requirements from actual role
  ownership rather than the latest manifest mode label.
- **Bounded Codex project instructions** — native `codex debug prompt-input` inspection
  proved the former 68 KiB `AGENTS.md` was truncated. Codex now gets a 6.7 KiB
  always-loaded kernel and complete manifest-owned rule/recipe references under
  `.codex/conductor/`; validator and doctor enforce 24 KiB/32 KiB safety budgets.
- **Semantic doctor and portable hooks** — doctor now audits every manifest, checksums,
  footprints, hook dialects, agent TOML contracts, Git tracking, project profile, and
  structured CURRENT_WORK drift. Shared hooks are BSD/GNU awk compatible and normalize
  zero counters deterministically.
- **Release-candidate regressions** — five modes across six adapters, 24 multi-tool
  runtime contracts, local native Codex prompt-input verification, and a freshly packed
  npm artifact install/validate/doctor/reinstall/forward-and-reverse-uninstall lifecycle
  are covered.
- **Offline validation latency** — the advisory npm-registry check is retry-free,
  capped at three seconds, and explicitly skippable for deterministic offline runs.
- **Published-version migration compatibility** — upgrading the actual npm `1.0.1`
  package now preserves and snapshots user edits, ignores historical backup files
  during current-output isolation checks, replaces Windsurf files only when legacy
  ownership proves they are managed, and converts the old shared root manifest to
  six authoritative adapter manifests before an all-target upgrade. Previewing that
  legacy migration with `--dry-run` remains byte- and path-zero-write.

## [1.0.1] — 2026-07-09

### Fixed — manifest safety follow-up
- **Checksum-protected uninstall on all six adapters** — normal manifest entries now record the emitted file's SHA-256. `--uninstall` removes or restores only an unchanged emitted file; a user-modified file (and legacy manifest entries without a checksum) is preserved with a warning instead of being deleted.
- **Lossless full-mode re-install** — an unmodified re-install retains the original pre-CONDUCTOR backup rather than replacing it with the prior generated bundle. Backup names are collision-safe within the same second. If a generated file was edited before an update, that edit is backed up before replacement.
- **Owned marked blocks only** — Gemini/Codex replace an existing `conductor:block` only when exactly one matching marker pair is present, the current manifest owns it, and its content hash is unchanged. Foreign, malformed, duplicate, or customized markers abort without changing the host file.
- **Regression coverage** — `tools/test-install-modes.sh` now asserts original-baseline restoration after two full installs, preservation of user edits during uninstall for every adapter, and non-destructive foreign-marker rejection for Gemini/Codex.
- **Private-source/public-mirror policy** — the source repository remains private; a fail-closed filtered snapshot is the only route to the public mirror and npm release. `sync-public.sh HEAD --check` is network-free and runs in CI to reject denied paths or private tokens before merge. See `docs/PUBLICATION-POLICY.md`.

## [1.0.0] — 2026-07-09

### Added — install modes (audit follow-up #4; the final pre-1.0 feature)
- **`--mode=full|minimal|strict|recipes-only|reflector-only` on all six adapters** (npx CLI forwards it; manifest stamps `"mode"`). `full` = unchanged default. `minimal` = discipline text + docs only (no agents/hooks/Reflector runtime). `strict` = abort (exit 3) instead of touching an existing baseline. `recipes-only` = à la carte (requires `--recipes=`). `reflector-only` = the self-improvement loop standalone — the least-conflicting install for projects already on Spec Kit / BMAD. — **ADR-044**.
- **Marked append-blocks for single-file tools (Gemini/Codex)** — à-la-carte modes APPEND `<!-- conductor:block … -->` to an existing `GEMINI.md`/`AGENTS.md` instead of overwriting; the manifest tracks `type: block` + content `sha256` + `created_file`, and `--uninstall` strips the block only when unmodified (a customized block is left in place with a warning). Windsurf needed no blocks — its rules are per-file under `.devin/rules/`.
- **Framework detection** — the installer detects Spec Kit (`.specify/`) / BMAD (`_bmad`/`.bmad-core`) and *suggests* an à-la-carte mode. Suggest only; never auto-switches.
- **`tools/test-install-modes.sh`** — per-tool mode-behavior harness (strict abort incl. secondary rules surfaces, à-la-carte emission sets, **byte-lossless block round-trips (checksum-asserted)**, cross-mode block cleanup, customized-block preservation, zero-valid-recipes failure); CI job `install-modes` runs it for all six adapters.
- **`install.ala_carte` in adapter metadata** — the block-vs-per-file à-la-carte strategy is single-sourced in `metadata.json` (new M9 consistency check + a column in the generated outputs table). npm-registry lag now surfaces as a non-fatal `WARN[A3]` in the stale-token check.

### Changed
- ROADMAP P4 marked **Done** — v1.0.0 is the public release (beta feedback + marketplace listing move post-1.0). COMPARISON's "pre-1.0" maturity framing retired (tokenized per the ADR-039 process rule).
- Claude adapter: `INSTALLED_HOOKS` initialized before mode branches; recipes step creates `.claude/rules/` itself (à-la-carte no longer depends on step 1).

### Milestone
- **v1.0.0** — all five features from the 2026-07-09 audit-follow-up plan are shipped (#3 stale-token CI + #2 metadata single-source in 0.7.0; #1 doctor + #5 live-verify + #2 slice 2 doc generation in 0.8.0; #4 install modes here). The anti-drift system is closed-loop: metadata is the single source, CI regenerates and verifies the docs, doctor checks installs, live-verify records reality.

## [0.8.0] — 2026-07-09

### Added — metadata consumers (audit follow-up #1 + #5 + #2 slice 2)
- **`omniconductor doctor <target>` (3rd CLI command)** — read-only installed-project health check anchored on `.conductor-manifest.json`. Seven groups: manifest validity · version drift (install stamp vs running CLI) · file integrity · stale legacy paths (from adapter `metadata.json`, `--legacy-cursorrules` aware) · hook validity (`.json` parses, `.sh` executable + `bash -n`) · doc-link liveness · stale-claim scan (reuses `tools/stale-tokens.txt` semantics). OK/WARN/FAIL → exit 0/1/2, `--json` for machines. CI runs a positive + negative doctor smoke per adapter. Prior-art differentiated by scope (per-project asset health), not name. — **ADR-041**.
- **Generated doc regions from metadata (`tools/generate-adapter-docs.js`)** — the live-verification status table (`docs/ADAPTER-LIVE-VERIFICATION.md`) and a new "Adapter outputs at a glance" table (`docs/COMPATIBILITY-MATRIX.md`) are now rendered from `adapters/*/metadata.json`; `--check` fails CI on drift. All remaining hand-written live-verification dates/CLI versions on living surfaces replaced with date-free pointers to the generated table (milestone history keeps "first live-verified" dates). — **ADR-042**.
- **`tools/live-verify.sh` — automated live rule-loading verification** — per tool: throwaway install → headless probe (read-only) → deterministic grade (≥3/5 universal rule names + CURRENT_WORK; no LLM judge) → writes `live_verification` into `metadata.json` and regenerates the doc tables. Honest SKIP when a CLI isn't installed; >90-day freshness WARN; local-first (CI can't hold six authenticated CLIs). **First run: Claude Code newly live-verified (5/5 rules, Claude Code 2.1.205) and Codex re-verified (4/5, codex-cli 0.144.0), both 2026-07-09.** — **ADR-043**.

### Changed
- Claude adapter manifest now stamps `"adapter": "claude"` (the other five adapters already stamped theirs) — doctor uses it; footprint inference covers pre-0.8 installs.
- `bin/omniconductor.js` usage/comments: `doctor` added; stale "ADR-018" citation corrected to ADR-002/023/025.

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
