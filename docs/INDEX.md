# CONDUCTOR — Document Index

Single catalog of every asset in this repo. Updated when new documents land.

## Top-level (repo root)

| File | Purpose |
|---|---|
| `README.md` | Project introduction (한/영 bilingual). Install instructions. |
| `VISION.md` | Why CONDUCTOR exists, who it's for, non-goals. |
| `ROADMAP.md` | P0 → P4 phases. |
| `CLAUDE.md` | Lead orchestrator manual for working IN this repo. Sanitization rules. |
| `CURRENT_WORK.md` | Session continuity — what's in progress, what's next. |
| `SESSION_HANDOFF.md` | Reference-adopter ↔ Conductor relationship + cross-repo reference index. |
| `LICENSE` | Apache 2.0 — open + commercial-friendly; the CONDUCTOR name is trademarked so forks cannot pass off as the original (ADR-029). |
| `package.json` | npm package `omniconductor` (version is single-sourced here — see the npm registry / CHANGELOG for current); no runtime deps. |

## `core/` — Layer 1 (universal, tool-agnostic)

| Path | Purpose |
|---|---|
| `core/README.md` | Layer 1 overview. |
| `core/universal-rules/README.md` | The 5 bundle catalog. |
| `core/universal-rules/workflow.md` | W1..W6 (plan-first, docs-first, 7-step, process-over-speed, never-skip). |
| `core/universal-rules/spec-as-you-go.md` | W3 + O1 (same-turn spec, real-time docs sync). |
| `core/universal-rules/quality-gates.md` | Q1..Q4 (pre-commit + pre-merge review, test sync, verify-after). |
| `core/universal-rules/operations.md` | O2 + O3 + P3 (session continuity, completed-task delete, dev/prod sync). |
| `core/universal-rules/meta-discipline.md` | M1 + M2 + M3 + M5 + ambiguity policy. |
| `core/roles/README.md` | The 6 universal-roles catalog. |
| `core/roles/planner.md` | Architecture, gap analysis, ADRs. Opus-tier. |
| `core/roles/builder.md` | Multi-file / cross-cutting code. Opus-tier. |
| `core/roles/reviewer.md` | Plan validation. Opus-tier. Read-only. |
| `core/roles/helper.md` | Single-file work, established patterns. Sonnet-tier. |
| `core/roles/designer.md` | UI / UX, design tokens, accessibility. Sonnet-tier. |
| `core/roles/scribe.md` | Documentation sync after impl. Sonnet-tier. |
| `core/roles/reflector.md` | Reads session trajectories; proposes lesson deltas (propose-only, opt-in). Opus-tier. |
| `core/recipes/README.md` | The 13 opt-in recipes catalog + selection guidance. |
| `core/recipes/self-improvement.md` | Opt-in Reflector loop — propose-only session self-review (ADR-030/032/033). |
| `core/recipes/web-mobile-parity.md` | P1 + P2 (feature + bug parity). |
| `core/recipes/i18n.md` | Multi-locale translation key sync. |
| `core/recipes/monorepo.md` | Workspaces + shared package pattern. |
| `core/recipes/branch-strategy.md` | 3-branch deploy model (main / develop / release). |
| `core/recipes/auto-mock-data.md` | Mock seed autogen on schema change. |
| `core/recipes/coding-conventions.md` | TypeScript naming, Result-pattern, error-handling. |
| `core/recipes/tdd.md` | Test-first Red-Green-Refactor loop. |
| `core/recipes/debugging.md` | Root-cause-first debugging discipline. |
| `core/recipes/database-discipline.md` | Migration-first schema changes + access control + dev/prod parity. |
| `core/recipes/design-system.md` | Design-token adherence, component reuse, accessibility. |
| `core/recipes/git-hygiene.md` | Git hygiene / shared-repo discipline — no orphan worktrees, push-don't-hoard, merge=delete-branch, backup≠applied (ADR-037). |
| `core/recipes/loop-engineering.md` | Bounded, externally-verified agent loops — done-criterion, budget, progress, escalate-on-stall, verify-not-self-judge, oscillation guard (ADR-038). |
| `core/anti-patterns/README.md` | The 8 token-waste anti-pattern catalog index + how to use in code review. |
| `core/anti-patterns/large-file-read-no-range.md` | Reading whole files instead of Grep + range-read. |
| `core/anti-patterns/single-monolithic-rule-file.md` | One giant rule file instead of lazy-loaded bundles. |
| `core/anti-patterns/no-sub-agent-dispatch.md` | Doing everything in the main thread instead of dispatching. |
| `core/anti-patterns/dynamic-system-prompt.md` | Per-turn variable prefixes that bust the cache. |
| `core/anti-patterns/frequent-rule-file-edit.md` | Editing rule files mid-session (cache invalidation). |
| `core/anti-patterns/skill-eager-load.md` | Loading skills / context that isn't needed yet. |
| `core/anti-patterns/tool-call-spam.md` | Many small tool calls instead of batched / structured ones. |
| `core/anti-patterns/output-verbosity-narration.md` | Over-explaining / re-printing files — output tokens cost ~5× input. |
| `core/hooks/README.md` | Hook template overview (10 templates). |
| `core/hooks/pretool-agent-routing.sh.template` | PreToolUse — validate Agent dispatch. |
| `core/hooks/pretool-commit-current-work-check.sh.template` | PreToolUse — block commit when CURRENT_WORK is stale. |
| `core/hooks/pretool-commit-test-coverage-check.sh.template` | PreToolUse — block commit when test coverage out of sync. |
| `core/hooks/pretool-large-file-read-guard.sh.template` | PreToolUse — intercept large-file Read; suggest Grep + range-read. |
| `core/hooks/stop-session-log-check.sh.template` | Stop — block when CURRENT_WORK / specs are stale. |
| `core/hooks/stop-r6-review-check.sh.template` | Stop — remind to run pre-merge review on open PR. |
| `core/hooks/stop-cache-hit-baseline-check.sh.template` | Stop — warn if cache hit rate drops below 95% SLA. |
| `core/hooks/stop-trajectory-log.sh.template` | Stop — upsert a trajectory pointer for the Reflector (self-improvement recipe; opt-in gated). |
| `core/hooks/stop-git-hygiene-guard.sh.template` | Stop — remind on git-hygiene collapse (orphan worktrees / local-only commits / stale branches; git-hygiene recipe). |
| `core/hooks/pretool-loop-guard.sh.template` | PreToolUse — soft-warn on loop oscillation / runaway (same action repeated or session tool-call budget; loop-engineering recipe). |
| `core/workflow/README.md` | Workflow phase overview (P0 deliverable). |
| `core/workflow/PHASES.md` | Plan → Architecture → Tasks → Implementation → Review → Spec. |
| `core/docs-templates/*.md` | CURRENT_WORK / TASKS / REMAINING_TASKS / PLANS / INDEX templates. |
| `core/docs-templates/specs/_example.md` | Spec template. |
| `core/memory-pattern/README.md` | 4-type memory schema (user / feedback / project / reference). |
| `core/memory-pattern/EXAMPLES.md` | Memory entry examples. |

## `adapters/` — Layer 2 (per-tool transform)

| Path | Status |
|---|---|
| `adapters/README.md` | Adapter overview. |
| `adapters/claude/README.md` | Claude adapter overview. |
| `adapters/claude/SUPPORTED-FEATURES.md` | Feature matrix. |
| `adapters/claude/transform-spec.md` | P0 transform spec. |
| `adapters/claude/transform.sh` | **✅ Implemented.** core → .claude/{rules,agents,hooks} + CLAUDE.md + settings.json. |
| `adapters/claude/hookify-templates/*` | 17 opt-in hookify templates (`.local.md.template`), 5 recipe-scoped (i18n / database / design-system). |
| `adapters/cursor/transform.sh` | **✅ Implemented (P2).** core → .cursor/rules/*.mdc (+ opt-in legacy .cursorrules). |
| `adapters/copilot/transform.sh` | **✅ Implemented (P3).** core → .github/copilot-instructions.md (default merged bundle) + .github/instructions/*.instructions.md (recipes / `--per-rule`) — covers 5 IDEs. |
| `adapters/<tool>/metadata.json` | **✅ v0.7.0 (ADR-040).** Single source per adapter for outputs / legacy paths / tier / capabilities / live-verification / headless CLI. CI-checked. |
| `adapters/gemini/transform.sh` | **✅ adapter shipped (v0.2).** core → `GEMINI.md` + `.gemini/styleguide.md`. Emit-verified; live runtime pending — see `docs/ADAPTER-LIVE-VERIFICATION.md`. |
| `adapters/codex/transform.sh` | **✅ adapter shipped (v0.2).** core → `AGENTS.md`. Emit-verified + **live-verified** (auto-probe `tools/live-verify.sh`) — current status in `docs/ADAPTER-LIVE-VERIFICATION.md`. |
| `adapters/windsurf/transform.sh` | **✅ adapter shipped (v0.2).** core → `.windsurfrules` + `.devin/rules/*.md` (legacy `.windsurf/rules/` still read). Emit-verified; live runtime pending — see `docs/ADAPTER-LIVE-VERIFICATION.md`. |

## `tools/`

| Path | Purpose |
|---|---|
| `tools/measure-tokens.sh` | **P1 ✅ Implemented.** Claude session JSONL token measurement. Zero telemetry. |
| `tools/check-framework-purity.sh` | Reverse-validation: bans reference-adopter-specific tokens in the framework body (ADR-026). CI job `purity`. |
| `tools/validate-adapter-output.sh` | Per-tool structural validator for adapter output (frontmatter / sections / placeholders). CI job `adapters`. |
| `tools/check-stale-tokens.sh` + `tools/stale-tokens.txt` | **v0.7.0 (ADR-039).** Known-false-claim + version-stamp guard over living docs. CI job `stale-tokens`. |
| `tools/check-adapter-metadata.sh` | **v0.7.0 (ADR-040).** Asserts `adapters/*/metadata.json` agrees with transform.sh / validator / matrix / live-verification doc. CI job `adapter-metadata`. |

## `docs/` — Repo-internal documentation

| File | Purpose |
|---|---|
| `docs/ARCHITECTURE.md` | 3-layer model. |
| `docs/COMPATIBILITY-MATRIX.md` | Feature support per tool. |
| `docs/PHILOSOPHY.md` | Design principles. |
| `docs/DESIGN-DECISIONS.md` | ADR-001 ~ ADR-034. |
| `docs/HOW-IT-WORKS-PER-TOOL.md` | Per-tool install paths + limitations. |
| `docs/MIGRATION.md` | Tool-switching migration guide. |
| `docs/CONTRIBUTING.md` | Adapter contributor guide. |
| `docs/COMPARISON.md` | Comparison with other frameworks. |
| `docs/GO-TO-MARKET.md` | Internal launch strategy. |
| `docs/CONDUCTOR-V0.2-DESIGN.md` | P0.5 comprehensive design (1579 lines, 12 Open Questions). |
| `docs/PROMPT-CACHING-GUIDE.md` | **P1 ✅** Anthropic prompt caching structure + measurement. |
| `docs/CONTEXT-EDITING-GUIDE.md` | Instruction-fidelity-first context reduction — lossless `clear_tool_uses` before lossy `/compact` (Claude-only, ADR-035). |
| `docs/KPI.md` | **P1.5 ✅** Baseline metrics (cache hit 100%, output tokens/turn, etc.). |
| `docs/MANUAL-INSTALL.md` | Path C — fallback manual `cp` / `cat` install for any tool (every tool now also has a `transform.sh`; manual steps are a fallback). |
| `docs/PUBLISH-GUIDE.md` | VSCode Marketplace + Open VSX publish steps (Phase 2 / v0.3+, ADR-025). |
| `docs/IDE-COMPATIBILITY-NOTES.md` | Per-IDE compatibility notes. |
| `docs/IDE-SMOKE-TESTING.md` | Per-IDE smoke-test procedure. |
| `docs/specs/` | Spec documents (spec-as-you-go outputs). |
| `docs/plans/` | Phase / track implementation plans. |
| `docs/data/` | KPI baseline raw CSV data. |
| `docs/INDEX.md` | This file. |

> **Internal-only docs:** `GO-TO-MARKET.md`, `CONDUCTOR-V0.2-DESIGN.md`, `KPI.md`, `docs/data/`, `docs/plans/`, and `docs/audits/` are working docs kept in the **private repo only** — they are intentionally excluded from the public `omniconductor` mirror.

## `docs/audits/` — Competitive analyses

| File | Date | Purpose |
|---|---|---|
| `docs/audits/competitive-analysis-2026-05-09.md` | 2026-05-09 | Baseline 7-dimension scoring vs Superpowers / Plain CLAUDE.md / Cursor Rules. **Superseded by 2026-05-10 morning (frozen reference for methodology).** |
| `docs/audits/competitive-analysis-2026-05-10.md` | 2026-05-10 morning | Re-scoring after Cursor + Copilot adapters + ownership clarity. Aggregate 25.5/35 → 29/35 (+3.5). Public-launch ready verdict. **Superseded by 2026-05-10 evening.** |
| `docs/audits/competitive-analysis-2026-05-10-evening.md` | 2026-05-10 evening | 2nd re-scoring after Tracks A/B/C (per-IDE smoke + format validator + TDD/debugging recipes + VSCode extension Phase 2 scaffold + PUBLISH-GUIDE + ADR-024/025). Aggregate 29 → **31.5/35**. Match-or-exceed Superpowers on 6 of 7 dimensions; Dim 6 trails by 0.5 (publish-gated). |

## `archive/v0.1/`

Legacy Claude-only scaffold. Kept for backward compatibility. Use `adapters/claude/transform.sh` for new installs.

## Phase status snapshot

| Phase | Status | Date |
|---|---|---|
| P0 — Foundation | Complete | 2026-05-03 |
| P0.5 — Comprehensive design + 12 Open Questions | Complete (user-confirmed) | 2026-05-06 |
| P1 — Universal rules + Claude adapter + measurement | Complete | 2026-05-07 |
| P1.5 — KPI baseline measurement | Complete | 2026-05-07 |
| P1.6 — Anti-pattern catalog (7 patterns) | Complete | 2026-05-14 |
| P1.7 — Cache-hit Stop hook + Large-file Read guard | Complete | 2026-05-18 |
| P2 — Cursor adapter | Complete | 2026-05-30 |
| P3 — Copilot ✅ + Gemini ✅ adapters | Done (both ship `transform.sh`; live runtime adopter-pending) | 2026-06-28 |
| P3.5 — Codex ✅ + Windsurf ✅ adapters | Done (both ship `transform.sh`; Codex live-verified 2026-06-28, Windsurf live pending) | 2026-06-28 |
| P4 — Public release | npm `omniconductor` published + public GitHub mirror live (v0.6.0, 2026-07); marketplace listing pending | 2026-07 |
