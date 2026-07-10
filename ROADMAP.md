# ROADMAP — CONDUCTOR

> Last updated: 2026-07-09. Estimated dates assume CONDUCTOR work resumes at ~50% of weekly capacity (the reference project retains priority through its 2026 launch).

> **한글:** 최종 수정 2026-07-09. 아래 예상 일정은 CONDUCTOR 작업이 주간 가용 시간의 약 50% 수준으로 재개된다는 가정입니다 (the reference project 가 2026년 출시까지 우선순위를 유지합니다). CONDUCTOR 는 사이드 프로젝트이므로, the reference project 가 집중을 요구하면 후속 단계는 죄책감 없이 멈춥니다 — 로드맵은 목표일 뿐 계약이 아닙니다.

## Phase summary

> **한글:** 단계 요약. P0 (기반 리셋) · P1 (Universal 룰 + Claude 어댑터) · P1.5 (KPI 베이스라인 측정) · P1.6 (안티패턴 카탈로그) · P1.7 (캐시히트 Stop 훅 + 대용량 파일 Read 가드 훅) · P2 (Cursor 어댑터) · P3 (Copilot + Gemini 어댑터) · P3.5 (Codex + Windsurf 어댑터) 까지 모두 **완료**되었습니다 — 이제 6개 어댑터 전부 `transform.sh` 를 제공하고, npm 에 [`omniconductor`](https://www.npmjs.com/package/omniconductor) 로 배포되어 `npx omniconductor init --target=<tool> <dir>` 가 동작합니다 (출력은 emit-verified; 도구별 라이브 검증 현황은 `docs/ADAPTER-LIVE-VERIFICATION.md` 의 생성 테이블 참고 — `tools/live-verify.sh` 가 자동 갱신). **P4 의 v1.0 공식 출시도 완료**되었습니다 (2026-07-09; 남은 후속: 커뮤니티/베타 피드백 수집 + 마켓플레이스 리스팅). 아래 표의 각 단계는 영문 그대로 두며, 상세 산출물·종료 조건은 각 단계 섹션을 참고하세요.

| Phase | Name | Target end | Status |
|---|---|---|---|
| **P0** | Foundation reset | 2026-05-04 | **Done** |
| **P1** | Universal rules + Claude adapter | 2026-05-07 | **Done** |
| **P1.5** | KPI baseline measurement | 2026-05-07 | **Done** |
| **P1.6** | Anti-pattern catalog | 2026-05-14 | **Done** |
| **P1.7** | Cache-hit Stop hook + Large-file Read guard hook | 2026-05-18 | **Done** |
| **P2** | Cursor adapter + matrix validation | 2026-05-30 | **Done** |
| **P3** | Remaining T1+T2 adapters (Copilot ✅, Gemini ✅) | 2026-06-28 | **Done** (both ship `transform.sh`) |
| **P3.5** | T3 adapters (Codex ✅, Windsurf ✅) | 2026-06-28 | **Done** (both ship `transform.sh`; Codex first live-verified 2026-06-28) |
| **P4** | Public release v1.0 | 2026-07-09 | **Done (v1.0.0 shipped)** — git tags + GitHub Releases + public mirror; launch activities (beta feedback, Show HN/Reddit posts, marketplace listing) moved post-1.0 |

---

## P0 — Foundation reset (2026-05-03 → 2026-05-04)

**Goal**: direction-setting + thorough documentation before any transform code is written.

### Deliverables

- [x] Archive v0.1 cleanly (`archive/v0.1/`) with `git mv` to preserve history.
- [x] `README.md` rewritten for multi-tool positioning (bilingual 한/영).
- [x] `VISION.md` — the why, the audience, the non-goals.
- [x] `ROADMAP.md` — this file.
- [x] `docs/ARCHITECTURE.md` rewritten for the 3-layer model.
- [x] `docs/COMPATIBILITY-MATRIX.md` — per-tool feature support matrix.
- [x] `docs/PHILOSOPHY.md` rewritten for multi-tool stance.
- [x] `docs/DESIGN-DECISIONS.md` — ADR-001 through ADR-008.
- [x] `docs/HOW-IT-WORKS-PER-TOOL.md` — section per tool: install path, what works, what is lost.
- [x] `docs/MIGRATION.md` — how to switch tools mid-project.
- [x] `docs/CONTRIBUTING.md` — adapter contribution guide.
- [x] `docs/COMPARISON.md` rewritten with multi-tool angle.
- [x] `docs/GO-TO-MARKET.md` — internal launch strategy.
- [x] `core/` skeleton with READMEs explaining intent (workflow / universal-rules / docs-templates / memory-pattern).
- [x] `adapters/<tool>/` skeleton for all 6 tools with README + SUPPORTED-FEATURES.md + transform-spec.md.
- [x] `package.json` updated to `0.2.0-foundation`, multi-tool description.

### Stop condition

Single commit on `main`: `feat: CONDUCTOR v0.2 foundation reset (multi-tool architecture)`. No code written. Foundation visible to any future contributor at first glance.

---

## P1 — Universal rules + Claude adapter (2026-05-04 → 2026-05-07) ✓ Done

**Goal**: get the Claude adapter producing v0.1-equivalent output from `core/` source-of-truth.

### Deliverables

- [x] Fill all 5 universal rule placeholders under `core/universal-rules/` from sanitized reference-project originals (operations / coding-conventions / token-economy / spec-as-you-go / model-routing).
- [x] Fill `core/workflow/PHASES.md` with detailed entry/exit criteria per phase.
- [x] Fill `core/docs-templates/*.md` (CURRENT_WORK / REMAINING_TASKS / PLANS / TASKS / INDEX / specs/_example.md).
- [x] Build `adapters/claude/transform.sh` that reads `core/` and emits the v0.1 file structure into a target directory.
- [x] Verify diff between v0.1 install output and v0.2 Claude adapter install output is empty (or only documented improvements).
- [x] `adapters/claude/transform.sh` dry-run verified (.claude/rules 8, .claude/agents 6, .claude/hooks 3, docs 5, CLAUDE.md synthesized).

### Stop condition

Met: `bash adapters/claude/transform.sh /tmp/conductor-test-target --recipes=i18n,monorepo,coding-conventions` produces working scaffold.

---

---

## P1.5 — KPI baseline measurement (2026-05-07) ✓ Done

**Goal**: measure pre-Conductor token economics on the reference project to establish a quantitative optimization baseline.

### Deliverables

- [x] `tools/measure-tokens.sh` Python-backed JSONL parser (jq replaced — multi-byte/large-file safe).
- [x] `docs/KPI.md` — baseline metrics from 8 sessions / 37,763 turns.
- [x] `docs/data/baseline-2026-05-07.csv` — per-session raw data.

### Key findings

- **Cache hit rate: 100%** — Claude Code's built-in caching is already fully active. The old ≥60% target was based on a wrong assumption (caching was never disabled).
- **Output tokens/turn: 667** — dominant cost driver (~$378 across all sessions at Sonnet pricing).
- **Tool calls/turn: 0.61** — 61% of turns contain at least one tool call; top reduction lever.
- **Uncached input/turn: 11** — already optimal; further reduction has negligible cost impact.

### Stop condition

Met: `docs/KPI.md` baseline recorded. KPI targets revised (see P1.6/P1.7 and ADR-014/015).

---

## P1.6 — Anti-pattern catalog (2026-05-07 → 2026-05-14, ~1 week) ✓ Done

**Goal**: document the 7 most costly token-waste anti-patterns observed in the reference-project baseline, so Conductor can detect and prevent them.

**Effort**: Medium (~3–4 hours active work, spread over a week of observation).

> **Note**: the catalog shipped with different (clearer) filenames than originally planned. Actual delivered files below.

### Deliverables

- [x] `core/anti-patterns/` directory with 7 files (as shipped):
  - `large-file-read-no-range.md` — reading entire files instead of Grep + range-read
  - `single-monolithic-rule-file.md` — one giant rule file instead of lazy-loaded bundles
  - `no-sub-agent-dispatch.md` — doing everything in the main thread instead of dispatching
  - `dynamic-system-prompt.md` — injecting per-turn variable prefixes that bust the cache
  - `frequent-rule-file-edit.md` — editing rule files mid-session (cache invalidation)
  - `skill-eager-load.md` — loading skills / context that isn't needed yet
  - `tool-call-spam.md` — many small tool calls instead of batched / structured ones
- [x] Each file: pattern name / detection signal / measured cost / fix recipe / example.
- [x] `core/anti-patterns/README.md` — catalog index + how to use in code review.

### Stop condition

Met: all 7 anti-pattern files complete. A reviewer can identify and fix any pattern using only the catalog (no external knowledge required).

---

## P1.7 — Cache-hit Stop hook + Large-file Read guard (2026-05-14 → 2026-05-18, ~4 days) ✓ Done

**Goal**: enforce the revised KPI targets automatically via hooks. Prevent anti-patterns from being introduced silently.

**Effort**: Medium (~4–6 hours).

### Deliverables

- [x] `core/hooks/stop-cache-hit-baseline-check.sh.template` — Stop hook: after each session, warn if cache hit rate drops below 95%. Reads last JSONL file via `measure-tokens.sh --latest`.
- [x] `core/hooks/pretool-large-file-read-guard.sh.template` — PreToolUse hook: intercepts Read calls on large files; reminds agent to use Grep + range-read instead.
- [x] Update `adapters/claude/transform.sh` to emit both new hooks (all 7 hook templates now installed AND registered in the generated `.claude/settings.json`).
- [x] ~~`docs/HOOKS-GUIDE.md`~~ — **Dropped / folded.** No standalone guide was created; hook configuration now lives in the generated `.claude/settings.json` plus the README "Hooks" sections. Not pending.
- [x] Sync both hooks to the reference project's `.claude/hooks/` (양방향 동기화 ADR-016).

### KPI targets enforced by these hooks

| Metric | Baseline | Target | Enforced by |
|---|---|---|---|
| Output tokens/turn | 667 | ≤ 500 (-25%) | output-narration anti-pattern catalog |
| Cache-write/session | ~27.4M | ≤ 200K cap to monitor | context-bloat + uncached-prefix patterns |
| Tool calls/turn | 0.61 | ≤ 0.42 (-30%) | large-file-guard hook + full-file-read pattern |
| Cache hit rate | 100% | ≥ 95% (SLA) | stop-cache-hit-check hook |

### Stop condition

Both hook templates installable via transform.sh. The reference project's `.claude/hooks/` updated. `docs/HOOKS-GUIDE.md` complete.

---

## P2 — Cursor adapter + matrix validation (2026-05-18 → 2026-05-30, ~12 days) ✓ Done

**Goal**: prove the transform model works for a non-Claude tool, validate the compatibility matrix against reality.

**Entry condition**: P1.6 + P1.7 complete.

### Deliverables

- [x] Build `adapters/cursor/transform.sh`.
- [x] Output: `.cursor/rules/*.mdc` (one per universal rule, with appropriate `globs:` front-matter) + `.cursorrules` (project-wide always-loaded text).
- [x] Real install on a sample project. Open in Cursor, verify rules apply via the rule indicator UI.
- [x] Document any Cursor-specific quirks discovered in adapter notes.
- [x] Update `docs/COMPATIBILITY-MATRIX.md` with verified-vs-theoretical column.
- [ ] Baseline re-measurement for Cursor environment: run `tools/measure-tokens.sh` after 1 week of use. Verify cache hit ≥ 95% or trigger anti-pattern diagnosis.

### Stop condition

Met: `bash adapters/cursor/transform.sh <target>` works on a fresh project and Cursor visibly loads the rules. Quirks documented.

---

## P3 — Remaining T1+T2 adapters (2026-05-25 → 2026-06-28) — Done

**Goal**: cover the meaningful AI coding tool population.

### Deliverables

- [x] `adapters/copilot/transform.sh` → `.github/instructions/*.instructions.md` with `applyTo:` front-matter. (1 install covers VSCode + Cursor + Windsurf + JetBrains + Neovim.)
- [x] `adapters/gemini/transform.sh` → `GEMINI.md` (concatenated) + `.gemini/styleguide.md`. (Done — emit-verified; live runtime adopter-pending, see `docs/ADAPTER-LIVE-VERIFICATION.md`.)
- [x] Cross-tool spot-check: install all into the same sample project, verify no path collisions (Claude `.claude/` + Cursor `.cursor/` + Copilot `.github/instructions/` + Gemini `GEMINI.md` coexist).

### Stop condition

Claude / Cursor / Copilot / Gemini adapters produce installable output and the validator passes on all (Done). Live runtime consumption by Gemini remains adopter-pending.

---

## P3.5 — T3 adapters (2026-06-15 → 2026-06-28) — Done

**Goal**: cover the long tail.

### Deliverables

- [x] `adapters/codex/transform.sh` → `AGENTS.md` (single bundled file). (Done — emit-verified; **first live-verified 2026-06-28** — current status in `docs/ADAPTER-LIVE-VERIFICATION.md`.)
- [x] `adapters/windsurf/transform.sh` → `.windsurfrules` + `.devin/rules/*.md` (legacy `.windsurf/rules/`). (Done — emit-verified; live runtime adopter-pending.)

### Stop condition

All 6 tool adapters ship a `transform.sh` and pass `tools/validate-adapter-output.sh` (Done; CI in `.github/workflows/validate.yml` runs all 6). `docs/COMPATIBILITY-MATRIX.md` finalized. Per-tool live-verification status is single-sourced in the generated table in `docs/ADAPTER-LIVE-VERIFICATION.md` (auto-updated by `tools/live-verify.sh`).

---

## P4 — Public release v1.0 (2026-06-25 → 2026-07-09) — Done (launch activities → post-1.0)

**Goal**: ship to npm, post launch.

### Deliverables

- [x] Install distribution finalized — bash adapters + `npx omniconductor init --target=<tool> <dir>` CLI, **published to npm as [`omniconductor`](https://www.npmjs.com/package/omniconductor)**. Optional VSCode-extension launcher stays Phase 2 (ADR-025).
- [x] GitHub repo public (`lee77840/omniconductor`).

### Post-1.0 follow-ups (open — not gating the 1.0 version)

- [ ] Beta with 5 friends (2 Korean solo devs, 3 English solo devs) — dogfooding feedback round.
- [ ] Launch: Show HN + Reddit r/ClaudeAI + Twitter/X. Bilingual blog post.
- [ ] The reference project referenced as the flagship case study (it launches independently on its own timeline).
- [ ] Marketplace listing (VSCode Marketplace + Open VSX) — ADR-023 Phase 2.

### Success metric (30 days post-launch)

- 50+ GitHub stars
- 5+ community-contributed adapter PRs (or improvements to existing adapters)
- Zero paid features. Zero telemetry.

---

## KPI targets (post-P1.7 baseline)

These replace the pre-measurement assumptions. All targets apply to projects using the Conductor Claude adapter.

| Metric | Baseline (reference project, 2026-05-07) | Target | Lever |
|---|---|---|---|
| Output tokens / turn | 667 | ≤ 500 (-25%) | output-narration anti-pattern elimination |
| Tool calls / turn | 0.61 | ≤ 0.42 (-30%) | large-file-guard hook + full-file-read pattern |
| Cache-write / session | ~27.4M tokens | monitor; reduce context bloat | context-bloat + uncached-prefix patterns |
| Cache hit rate | 100% | ≥ 95% (SLA) | anti-pattern catalog + stop-cache-hit-check hook |
| Uncached input / turn | 11 | no change (already optimal) | — |

**Notes**:
- Cache hit rate ≥ 60% goal is retired — Claude Code enables caching automatically; 100% is the observed baseline.
- ≥ 95% target accounts for new users who may inadvertently introduce cache-busting anti-patterns. Conductor's hooks catch these early.
- Output tokens and tool calls are the primary cost + latency levers. Cache-write reduction is secondary (cost is 1.25× input, write is amortized over the session).

---

## Pause discipline

CONDUCTOR is a side-project. The reference project ships on its own timeline. **If the reference project needs full attention, P1.6/P1.7 and P2 pause without guilt.** The roadmap is a target, not a contract. Foundation (P0) is the only date-locked phase because once foundation is done it stays done — no further calendar pressure.

## Out-of-scope (post-v1.0)

The following are NOT on the roadmap and are explicitly deferred:

- GUI installer (CLI-only is intentional simplicity)
- Telemetry / usage analytics
- Hosted dashboard
- Paid tier
- Plugin marketplace
- Auto-rule-learning from git history
- Direct LLM integration (CONDUCTOR is files-on-disk; the LLM lives in your tool)
