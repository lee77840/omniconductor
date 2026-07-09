# CONDUCTOR

**One workflow framework, every coding agent.**

Write your project's rules, workflow, and discipline ONCE. Install into any AI coding tool you use — Claude Code, Cursor, GitHub Copilot, Gemini CLI, Codex, Windsurf — and get the same Plan → Architecture → Tasks → Implementation → Review → Spec discipline everywhere.

> Born from one year of production iteration at LFamily Labs — the rules, agents, hooks, and memory patterns that survived real shipping pressure.

> **Status (v0.8.0 — 2026-07-09)**: All 6 adapters ship a working `transform.sh` — **Claude Code** (full: rules + hooks + sub-agents + per-call model routing), **Cursor**, **GitHub Copilot** (one install covers 5 IDEs), **Gemini CLI** (`GEMINI.md` + `.gemini/styleguide.md`), **Codex** (`AGENTS.md`), **Windsurf / Devin Desktop** (`.windsurfrules` + `.devin/rules/*.md`). Published to npm as [`omniconductor`](https://www.npmjs.com/package/omniconductor). Output is emit-verified (format-validator + CI on all 6); **Claude Code + Codex are additionally live-verified** by the automated headless probe (`tools/live-verify.sh`), the rest are live-pending — current per-tool status in the generated table in [`docs/ADAPTER-LIVE-VERIFICATION.md`](./docs/ADAPTER-LIVE-VERIFICATION.md). Manual install ([`docs/MANUAL-INSTALL.md`](./docs/MANUAL-INSTALL.md)) remains a fallback.
>
> **New in 0.8.0**: the anti-drift system now has consumers — **`npx omniconductor doctor`** (read-only install health check, ADR-041), **generated doc tables** from adapter metadata (ADR-042), and **`tools/live-verify.sh`** (automated headless live-verification — Claude Code + Codex verified with it, ADR-043). Earlier releases (anti-drift guards, loop-engineering, git-hygiene, token economy, the Reflector loop): [`CHANGELOG.md`](./CHANGELOG.md).
>
> Marketplace listing (VSCode Marketplace + Open VSX) remains **Phase 2** (post-0.6) — see ADR-023.

---

## Table of contents

- [한국어 / Korean](#한국어)
- [English](#english)
- [Tool coverage matrix](#tool-coverage-matrix)
- [Install paths (3 options)](#install-paths)
- [Cross-platform: Mac and Windows](#cross-platform-mac-and-windows)
- [Recipes catalog (13)](#recipes-catalog)
- [`transform.sh` options reference](#transformsh-options-reference)
- [Update / Maintenance / Uninstall](#update--maintenance--uninstall)
- [Token measurement & KPI baseline](#token-measurement--kpi-baseline)
- [Troubleshooting](#troubleshooting)
- [Memory pattern + ADR index](#memory-pattern--adr-index)
- [FAQ](#faq)

---

## 한국어

### 무엇

`CONDUCTOR` 는 6개의 AI 코딩 도구 (Claude Code / Cursor / GitHub Copilot / Gemini CLI / Codex / Windsurf) 모두에서 동일한 워크플로 + 룰 + 문서 템플릿을 강제하는 프레임워크입니다.

핵심 아이디어:

- **Layer 1 (`core/`) — Universal**: 도구 독립적인 워크플로 정의, 룰 텍스트, 문서 템플릿, 4-type 메모리 패턴
- **Layer 2 (`adapters/<tool>/`) — Adapter**: `core/` 의 universal 자료를 각 도구의 네이티브 포맷으로 변환 (`.claude/` / `.cursor/rules/*.mdc` / `.github/instructions/*.instructions.md` / `GEMINI.md` / `AGENTS.md` / `.windsurfrules`)
- **Layer 3 — Tool-native (정직한 한계)**: 2026년 기준 6개 도구 모두 hooks·sub-agent·per-call model routing 을 **지원**한다 (ADR-031). 다만 CONDUCTOR 어댑터가 이를 실제로 **emit 하는 건 현재 Claude 뿐** (나머지는 Phase 2). "도구가 못 함"이 아니라 "CONDUCTOR emission gap" 임을 정직하게 문서화 — ADR-004 / ADR-031. (Windsurf 는 session/stop hook 이벤트가 없는 유일한 실제 예외.)

### 강제하는 워크플로

1. **Plan → Architecture → Tasks → Implementation → Review → Spec** (skip 금지)
2. **Spec-as-you-go** — 코드 변경 시 `docs/specs/*.md` 동시 업데이트 (Claude 는 Stop hook 으로 강제, 다른 도구는 룰 reminder)
3. **2-stage 코드 리뷰** — pre-commit + pre-merge
4. **Token economy** — large-file Read 금지 / Grep first / range read
5. **Model routing** — Opus / Sonnet / Haiku 자동 분류 (Claude 전용 자동 enforcement, 다른 도구는 룰 텍스트 reminder)

### 빠른 시작 — 5분

> 가장 간단(클론 불필요): `npx omniconductor init --target=claude .` — 아래는 클론+bash 방식입니다.

```bash
# 1. CONDUCTOR 클론
git clone https://github.com/lee77840/omniconductor ~/conductor

# 2. 적용할 프로젝트로 이동
cd ~/your-project

# 3. dry-run 으로 미리보기
bash ~/conductor/adapters/claude/transform.sh . \
  --recipes=monorepo,coding-conventions \
  --dry-run

# 4. 실제 적용
bash ~/conductor/adapters/claude/transform.sh . \
  --recipes=monorepo,coding-conventions

# 5. Claude Code 재시작 → /agents 로 6 에이전트 확인
```

### 설치 방법 (3가지)

- **Path A — `npx` (권장, 클론 불필요)**: `npx omniconductor init --target=<tool> <dir>` — `<tool>` = `claude` / `cursor` / `copilot` / `gemini` / `codex` / `windsurf`. `list` · `doctor` (설치 상태 진단, 읽기 전용) · `--dry-run` · `--recipes=A,B` · `--uninstall` 지원.
- **Path B — bash 어댑터**: CONDUCTOR 클론 후 `bash adapters/<tool>/transform.sh <dir> [--recipes=...] [--dry-run]`.
- **Path C — 수동 복사**: 스크립트 없이 `cp`/`cat` 으로. [`docs/MANUAL-INSTALL.md`](./docs/MANUAL-INSTALL.md) 참조.
- **Windows**: Git Bash 또는 WSL2 — [Cross-platform](#cross-platform-mac-and-windows) 참조.

### Recipe 카탈로그 (13개, opt-in)

5개 universal rule 은 항상 설치되고, recipe 는 프로젝트에 맞게 골라 담습니다 (`--recipes=`).

| Recipe | 설치 시점 |
|---|---|
| `coding-conventions` | TypeScript/TSX — 네이밍·Result 패턴·에러 처리 규약 |
| `monorepo` | npm/pnpm workspaces (apps + packages) |
| `i18n` | 2개 이상 로케일 — 새 텍스트는 모든 로케일 동시 |
| `branch-strategy` | main/develop/release 3-브랜치 모델 |
| `web-mobile-parity` | 웹+모바일 로직 공유 — 버그·기능 양쪽 반영 |
| `auto-mock-data` | DB 스키마 변경 시 mock seed 자동생성 |
| `tdd` | 테스트 프레임워크 + Red-Green-Refactor |
| `debugging` | 재현→원인→수정→회귀테스트 (증상 패치 금지) |
| `database-discipline` | 관계형 DB — 마이그레이션 우선·접근제어·dev/prod 패리티 |
| `design-system` | 디자인 토큰 시스템 — 토큰 우선·컴포넌트 재사용·접근성 |
| `self-improvement` | 세션 회고 Reflector (propose-only, 사람이 승인) |
| `git-hygiene` | git 프로젝트 (특히 멀티세션/공유 repo) — worktree·push·브랜치 위생 |
| `loop-engineering` | 에이전트 루프 (fix→verify 반복) — 종료조건·예산·**외부검증** |

### 업데이트 / 제거

- **업데이트**: CONDUCTOR 클론을 `git pull` 후 어댑터 재실행 (또는 `npx omniconductor` 최신 버전).
- **제거**: `bash adapters/<tool>/transform.sh <dir> --uninstall` — manifest 기반으로 CONDUCTOR 가 넣은 파일만 복원/삭제 (직접 커스터마이즈한 건 보존).

### 상세 레퍼런스 (영문)

도구별 지원 매트릭스, `transform.sh` 전체 옵션, 토큰 측정, 트러블슈팅, FAQ 는 아래 영문 섹션을 참조하세요: [Tool coverage matrix](#tool-coverage-matrix) · [transform.sh options](#transformsh-options-reference) · [Troubleshooting](#troubleshooting) · [FAQ](#faq).

---

## English

### What

CONDUCTOR enforces the same workflow, rules, and documentation discipline across **six AI coding tools**: Claude Code, Cursor, GitHub Copilot, Gemini CLI, Codex, Windsurf.

Three layers:

- **Layer 1 (`core/`) — Universal**: tool-agnostic workflow definitions, rule text, doc templates, 4-type memory pattern.
- **Layer 2 (`adapters/<tool>/`) — Adapter**: per-tool transform script that reads `core/` and writes tool-native files.
- **Layer 3 — Tool-native (honest limits)**: as of 2026 **all six tools ship hooks, sub-agents, and per-call model routing** (ADR-031) — but CONDUCTOR's adapters currently *emit* them for **Claude only** (the rest is Phase 2). The honest limit is CONDUCTOR's emission gap, not a tool limitation, and nothing is fake-polyfilled. See ADR-004 / ADR-031. (Windsurf / Devin Desktop is the one real exception — no session/stop hook events.)

### Why this exists

- Solo developers and small teams increasingly mix AI coding tools within a single project.
- Switching tools means re-writing rules from scratch — losing the same discipline you spent months building.
- CONDUCTOR lets you write the discipline once and keep it across tools.

### Workflow enforced

1. **Plan → Architecture → Tasks → Implementation → Review → Spec** (no skipping)
2. **Spec-as-you-go**: code change touches matching `docs/specs/*.md` (auto-blocked by Stop hook on Claude; rule-text reminder elsewhere)
3. **Two-stage code review**: pre-commit + pre-merge PR
4. **Token economy**: no large-file reads, Grep first, range reads
5. **Model routing**: Opus / Sonnet / Haiku triage (Claude auto-enforced; rule text only elsewhere)

### Quick Start (5 minutes, Claude)

> Simplest (no clone): `npx omniconductor init --target=claude .` — the clone+bash steps below are equivalent.

```bash
git clone https://github.com/lee77840/omniconductor ~/conductor
cd ~/your-project
bash ~/conductor/adapters/claude/transform.sh . \
  --recipes=monorepo,coding-conventions \
  --dry-run                      # preview
bash ~/conductor/adapters/claude/transform.sh . \
  --recipes=monorepo,coding-conventions
# Restart Claude Code → /agents → confirm 6 agents loaded
```

Other tools: see [Install paths](#install-paths). Windows: see [Cross-platform](#cross-platform-mac-and-windows).

---

## Tool coverage matrix

Separate two things (per [`docs/COMPATIBILITY-MATRIX.md`](./docs/COMPATIBILITY-MATRIX.md), re-verified against first-party sources 2026-07-04, ADR-031):

- **Tool capability** — as of 2026, **all six tools ship hooks, sub-agents, custom named agents, per-task model routing, and commands.** The old "these are Claude-only" view is out of date. (Windsurf / Devin Desktop is the one partial: it has hooks but no session/stop events.)
- **CONDUCTOR emission** — what an adapter actually *compiles to today*. Claude emits the full set; every tool also emits the opt-in Reflector loop (ADR-032/033). Emitting the rest of the hook / agent set on the five non-Claude adapters is **Phase 2**.

The columns below show **CONDUCTOR emission today** (⚠️ = the tool supports it, adapter emission is Phase 2 — a CONDUCTOR gap, not a tool limitation):

| Tool | Adapter (rules) | Hooks | Sub-agents | Model routing | Recommended install |
|---|---|---|---|---|---|
| **Claude Code** | ✅ Full, lazy load | ✅ emitted (Stop / PreToolUse) | ✅ emitted (6 named agents; 7 with `self-improvement`) | ✅ emitted (per-call `model:`) | `bash adapters/claude/transform.sh <target>` |
| **Cursor** | ✅ Full, lazy load (`.mdc` globs) | ⚠️ tool ✅ · emit Phase 2 | ⚠️ tool ✅ · Claude-only by design (ADR-004) | ⚠️ tool ✅ · emit Phase 2 | `bash adapters/cursor/transform.sh <target>` |
| **GitHub Copilot** | ✅ Full (`applyTo:` scoping) | ⚠️ tool ✅ · emit Phase 2 | ⚠️ tool ✅ · Claude-only by design | ⚠️ tool ✅ · emit Phase 2 | `bash adapters/copilot/transform.sh <target>` — 1 install covers VSCode + Cursor + Windsurf + JetBrains + Neovim |
| **Gemini CLI** | ✅ Full (`GEMINI.md`) | ⚠️ tool ✅ · emit Phase 2 | ⚠️ tool ✅ · Claude-only by design | ⚠️ tool ✅ · emit Phase 2 | `bash adapters/gemini/transform.sh <target>` (+ `.gemini/styleguide.md` opt-in) |
| **Codex (OpenAI)** | ✅ Full (`AGENTS.md`) | ⚠️ tool ✅ · emit Phase 2 | ⚠️ tool ✅ · Claude-only by design | ⚠️ tool ✅ · emit Phase 2 | `bash adapters/codex/transform.sh <target>` |
| **Windsurf / Devin Desktop** | ✅ Full (`.windsurfrules` + `.devin/rules/*`) | ⚠️ partial (no session/stop events) · emit Phase 2 | ⚠️ tool ✅ (Devin Local) · Claude-only by design | ⚠️ tool ✅ · emit Phase 2 | `bash adapters/windsurf/transform.sh <target>` |

Full per-feature matrix + first-party footnotes: [`docs/COMPATIBILITY-MATRIX.md`](./docs/COMPATIBILITY-MATRIX.md).

> **CLI wrapper**: `npx omniconductor init --target=<tool> <dir>` (published to npm) — or `node bin/omniconductor.js init --target=<tool> <dir>` from a local clone — dispatches to these same adapter scripts, with `list`, `--dry-run`, `--recipes=`, and `--uninstall`. **`npx omniconductor doctor <dir>`** (v0.8+) health-checks an existing install read-only — manifest validity, version drift, file integrity, stale legacy paths, hook validity, doc links, stale claims — exit 0/1/2 (`--json` for machines).

> **What you keep going Claude → other tools**: all rule text, doc templates, the 4-type memory pattern, the workflow phases, and the opt-in Reflector loop (emitted on all six). **What is still Claude-only in CONDUCTOR's *emission* today**: auto-blocking hooks, per-call model routing, sub-agent dispatch — a Phase-2 emission gap, **not** a tool limitation (the tools support them; Windsurf is the one real exception, for Stop-style hooks). The discipline is portable; the enforcement is becoming portable as adapter emission catches up.

---

## Install paths

There are three install paths. **`npx omniconductor` (Path A) is the easiest — no clone needed.**

### Path A — `npx omniconductor` (npm — recommended, works today)

No clone required. Published to npm as [`omniconductor`](https://www.npmjs.com/package/omniconductor):

```bash
# Install CONDUCTOR's workflow into your project — for any of the 6 tools:
npx omniconductor init --target=claude ~/your-project --recipes=coding-conventions,tdd
# targets: claude | cursor | copilot | gemini | codex | windsurf

npx omniconductor list                                # list the 6 adapters
npx omniconductor init --target=claude . --dry-run --no-prompt   # preview, writes nothing
npx omniconductor init --target=claude . --uninstall             # revert
```

> **VSCode Marketplace extension** — a Cmd/Ctrl+Shift+P "install" launcher — is **NOT yet published**. It is optional future work (Phase 2 / v0.3; scaffold under [`phase-2/vscode-extension/`](./phase-2/vscode-extension/), procedure in [`docs/PUBLISH-GUIDE.md`](./docs/PUBLISH-GUIDE.md)). `npx omniconductor` and the bash adapter (Path B) already cover every install — the extension would only add a GUI button, and (per ADR-025) it still needs a local clone to run, so `npx` is the better path. Searching the Marketplace today will **not** find it.

### Path B — bash adapter (Phase 1 — recommended today)

Single command per tool. Adapter detects the target's existing state, runs an interactive wizard for adopter cases, and writes idempotent output with timestamped backups.

#### Mac / Linux

```bash
git clone https://github.com/lee77840/omniconductor ~/conductor
cd ~/your-project

# Pick your tool:
bash ~/conductor/adapters/claude/transform.sh   . --recipes=monorepo,coding-conventions
bash ~/conductor/adapters/cursor/transform.sh   . --recipes=monorepo,coding-conventions
bash ~/conductor/adapters/copilot/transform.sh  . --recipes=monorepo,coding-conventions
```

#### Windows / Git Bash (recommended for Windows)

```bash
# 1. Install Git for Windows: https://git-scm.com/download/win
# 2. Open Git Bash terminal
git clone https://github.com/lee77840/omniconductor /c/conductor
cd /c/Users/me/Projects/my-app

bash /c/conductor/adapters/claude/transform.sh . --recipes=monorepo,coding-conventions
```

> Git Bash translates `C:\Users\me\foo` to `/c/Users/me/foo`. Use forward slashes in commands.

#### Windows / WSL2

```bash
# Inside WSL2 Ubuntu — same commands as Mac/Linux
wsl
git clone https://github.com/lee77840/omniconductor ~/conductor
cd ~/your-project
bash ~/conductor/adapters/claude/transform.sh . --recipes=monorepo,coding-conventions
```

#### Windows / native PowerShell

> **Currently unsupported (Phase 3+, see ADR-023)**. PowerShell port is a near-rewrite of the bash adapters due to differing `sed` / `cat` / `mkdir` semantics. Use Git Bash or WSL2 instead.

### Path C — Manual file copy (no script, fully manual)

All 6 tools have a working adapter (Path A/B), so this path is a fallback — for adopters in constrained environments (no bash / no Node) or those who want to see every file before it lands. Step-by-step `cp` / `cat` commands per tool, with frontmatter conversion cheat sheet, are in:

→ **[`docs/MANUAL-INSTALL.md`](./docs/MANUAL-INSTALL.md)**

---

## Cross-platform: Mac and Windows

### Supported platforms

| Platform | Status | Shell | Notes |
|---|---|---|---|
| **macOS** (zsh, bash) | ✅ Reference platform | zsh / bash | Native bash 3.2 works; bash 5.x via Homebrew also supported. |
| **Linux** (Ubuntu, Debian, Fedora, Arch) | ✅ Supported | bash | Primary dev + validation environment (`tools/validate-adapter-output.sh`; automated CI is a roadmap item). |
| **Windows / Git Bash** | ✅ Supported | bash from MSYS2 | Bundled with Git for Windows. |
| **Windows / WSL2 (Ubuntu)** | ✅ Supported | bash | Treat as Linux. |
| **Windows / PowerShell** | ❌ Phase 3+ (ADR-023) | — | Use Git Bash or WSL2. |

### Common gotchas

- **GNU vs BSD `sed`**: macOS ships BSD `sed`, which requires `-i ''` for in-place edits; Linux/Git-Bash use GNU `sed -i`. Conductor adapters avoid `sed -i` entirely (use `cat > new` + `mv` instead) to side-step this.
- **CRLF vs LF on Windows**: Conductor source files are LF + UTF-8. If `git config core.autocrlf=true` rewrites `.sh` files to CRLF, bash will error with `\r: command not found`. Set:

  ```bash
  git config --global core.autocrlf input
  ```

- **`python3` requirement**: macOS 12+ ships Python 3 by default; Linux distros generally have it; Windows / Git Bash needs explicit install (`pacman -S python` in MSYS2, or use the Windows Python installer). Used by `tools/measure-tokens.sh` only — not required for the install itself.
- **Path quoting**: spaces in target paths work, but always quote: `bash adapters/claude/transform.sh "/c/Users/My Name/Projects/app"`.

---

## Recipes catalog

13 opt-in recipes layer project-specific discipline on top of the 5 universal rule bundles. Universal rules always install; recipes are pick-and-mix.

| Recipe | Install when | Adds |
|---|---|---|
| `coding-conventions` | TypeScript / TSX project | PascalCase components, camelCase files, no `any`, Result pattern, `logError()` |
| `monorepo` | npm/pnpm/yarn workspaces with apps + packages | Folder freeze, no duplicate logic across apps, workspace boundary rules |
| `i18n` | 2+ locales | All locales required in same PR for new text (partial = INCOMPLETE) |
| `branch-strategy` | main / develop / release 3-branch | No direct push to main/release, PR + CI required, hotfix path |
| `web-mobile-parity` | Web + mobile sharing logic | Bug fixes check both surfaces; features ship together |
| `auto-mock-data` | Frequent DB schema changes | Mock-seed SQL auto-generation on schema change |
| `tdd` | Test framework present + want Red-Green-Refactor | Test-first loop: failing test before implementation, refactor under green |
| `debugging` | Any project (root-cause-first discipline) | Reproduce → isolate → root-cause → fix → regression-test; no symptom patching |
| `database-discipline` | Relational store + migrations + dev/prod split | Migration-first schema changes, access-control on new tables, dev/prod parity |
| `design-system` | Design-token system in use | Tokens over raw hex, component reuse, accessibility + spacing scale adherence |
| `self-improvement` | Want periodic, human-approved review of your sessions | A **Reflector** reads recent session trajectories + git and **proposes** lessons-learned to `docs/REFLECTION-PROPOSALS.md` (propose-only; you apply). Emits a session-end trajectory hook, a `/reflect` command, a reflector agent, a deterministic prune, and a weekly runner + scheduling guide — on all six tools. See ADR-030/032/033. |
| `git-hygiene` | Any git project — esp. multi-session/agent repos or protected branches | Shared-repo discipline (G1–G7): no unrequested worktrees, push-don't-hoard, merge=delete-branch, backup≠applied (verify by real code), no reckless force/rebase on shared repos, bundle PRs for CI, session-end hygiene check. Claude adds a non-blocking Stop-hook reminder; other tools use the rule text. See ADR-037. |
| `loop-engineering` | Any agentic loop (generate→verify→fix→re-verify, test-fix, multi-step) | Bounded, externally-verified loops (G1–G6): explicit done-criterion, iteration+token budget, require-progress, escalate-on-stall, **verify externally never by self-judgment**, oscillation guard. Grounded in the research that self-correction without an external check is unreliable. Claude adds a non-blocking PreToolUse loop-guard (repeat/runaway detection); other tools use the rule text. See ADR-038. |

#### Decision tree

```
TypeScript?               YES → coding-conventions
Monorepo (apps/+packages)? YES → monorepo
2+ locales?               YES → i18n
Web + mobile?             YES → web-mobile-parity
3-branch git?             YES → branch-strategy
DB schema churn?          YES → auto-mock-data
Test framework + TDD?     YES → tdd
Want root-cause debugging? YES → debugging
Relational DB + migrations? YES → database-discipline
Design-token system?      YES → design-system
Want weekly session self-review? YES → self-improvement
Use git (esp. shared/multi-session)? YES → git-hygiene
Agent loops / iterative fix-verify?  YES → loop-engineering
```

#### Recommended combos

| Project type | Recipes |
|---|---|
| Greenfield experiment | None — universal-rules only |
| Solo SaaS, web, single locale | `coding-conventions` |
| Web + mobile (single language) | `web-mobile-parity, coding-conventions` |
| Multi-locale SaaS | `i18n, coding-conventions` |
| Monorepo SaaS | `monorepo, coding-conventions` |
| Full-stack (monorepo + multi-locale + web/mobile) | `monorepo, i18n, web-mobile-parity, coding-conventions` |

---

## `transform.sh` options reference

```
Usage: bash adapters/<tool>/transform.sh <target-project> [options]
```

| Option | Description |
|---|---|
| `<target-project>` | Project directory to install into (required). `.` for current dir. |
| `--recipes=A,B,C` | Comma-separated recipes from the 13 in `core/recipes/`. |
| `--dry-run` | Preview only — no files written. |
| `--measure-baseline` | Run `tools/measure-tokens.sh --latest` after install; save CSV; auto-show anti-patterns if cache hit < 95%. |
| `--no-prompt` | Skip wizard, apply defaults (CI-safe). Combine with `--recipes` and `--measure-baseline` as needed. |
| `--check-anti-patterns` | Print `core/anti-patterns/README.md` inline and pause 5 seconds. |
| `--uninstall` (alias `--rollback`) | Manifest-based revert (see [Update](#update--maintenance--uninstall)). Available on Claude adapter (Cursor / Copilot adapters: per-adapter spec). |
| `--force` | Bypass uninstall safety gates (active rebase/merge, missing manifest). |
| `-h` `--help` | Print usage. |

**Recipe names** (13): `web-mobile-parity`, `i18n`, `monorepo`, `branch-strategy`, `auto-mock-data`, `coding-conventions`, `tdd`, `debugging`, `database-discipline`, `design-system`, `self-improvement`, `git-hygiene`, `loop-engineering`.

#### File overwrite behavior

| File | Already exists |
|---|---|
| `CLAUDE.md` / `.cursorrules` / `.github/instructions/all.instructions.md` | Backed up to `.conductor-backup-YYYYMMDD-HHMMSS`, then overwritten |
| `.claude/rules/*.md` / `.cursor/rules/*.mdc` / `.github/instructions/*.instructions.md` | Backed up + overwritten |
| `.claude/agents/*.md` | Backed up + overwritten |
| `.claude/hooks/*.sh` | Overwritten |
| `.claude/hookify.*.local.md` | **Preserved** (adopter customizations win) |
| `docs/CURRENT_WORK.md` etc. | **Preserved** (never overwritten) |

---

## Update / Maintenance / Uninstall

### Update Conductor itself

```bash
cd ~/conductor && git pull
```

Then re-run `transform.sh` on each target — installs are idempotent. Existing files get fresh timestamped backups before overwrite (manifest tracks every emitted file, see ADR-020).

### Re-measure cache hit (1 week after install)

```bash
bash ~/conductor/tools/measure-tokens.sh --latest
```

Compare against the `.conductor/baseline-YYYYMMDD.csv` from `--measure-baseline` at install time. KPI target: cache hit rate ≥ 95% (ADR-014 SLA).

### Uninstall (revert install)

The Claude adapter ships with `--uninstall` (manifest-based revert, ADR-020). Cursor / Copilot adapters: see their respective `SUPPORTED-FEATURES.md`.

```bash
# Preview
bash ~/conductor/adapters/claude/transform.sh ~/your-project --uninstall --dry-run

# Apply
bash ~/conductor/adapters/claude/transform.sh ~/your-project --uninstall
```

Behavior:
- For each manifested file: restore backup if one exists, otherwise delete.
- Adopter-customized files (anything not in the manifest) are preserved.
- `.conductor-backup-*` siblings cleaned up.
- Best-effort `rmdir` of empty `.claude/{rules,agents,hooks}/`.

---

## Token measurement & KPI baseline

`tools/measure-tokens.sh` parses Claude Code session JSONL files and reports cache hit rate, input/output token counts, and tool call totals.

```bash
brew install jq                              # macOS dependency
bash ~/conductor/tools/measure-tokens.sh --latest

# Export for before/after comparison
bash ~/conductor/tools/measure-tokens.sh --latest --export-csv=/tmp/before.csv
# (1 week later, after Conductor install)
bash ~/conductor/tools/measure-tokens.sh --latest --export-csv=/tmp/after.csv
```

#### KPI targets (1 week after install)

| Metric | Target |
|---|---|
| Input tokens / task | -40% |
| File Reads / task | -50% |
| Cache hit rate | 100% baseline → ≥ 95% SLA (per ADR-014; the old ≥60% goal is retired — caching is on by default) |
| Tool calls / task | -30% |

> Zero telemetry — all results stay local. No external transmission.

---

## Troubleshooting

#### "Permission denied: transform.sh"

```bash
chmod +x ~/conductor/adapters/<tool>/transform.sh
bash ~/conductor/adapters/<tool>/transform.sh . --recipes=coding-conventions
```

#### "CLAUDE.md / .cursorrules already exists"

Auto-backed-up to `.conductor-backup-YYYYMMDD-HHMMSS`. Diff against the new file to merge customizations:

```bash
diff CLAUDE.md.conductor-backup-* CLAUDE.md
```

#### "recipe not found" warning

Check recipe name spelling. Available: `web-mobile-parity`, `i18n`, `monorepo`, `branch-strategy`, `auto-mock-data`, `coding-conventions`, `tdd`, `debugging`, `database-discipline`, `design-system`, `self-improvement`, `git-hygiene`, `loop-engineering`.

#### "Tool doesn't recognize the new rules"

Restart the IDE / CLI completely. Rule files are read at session start; live reload is rare.

#### "Hooks not firing" (Claude only)

```bash
ls -la .claude/hooks/        # verify executable bit (-rwxr-xr-x)
chmod +x .claude/hooks/*.sh  # grant if missing
# Restart Claude Code
```

All six tools now ship hooks (Windsurf / Devin Desktop is partial — no session/stop events; ADR-031). CONDUCTOR *emits* hook configs for **Claude only** today (non-Claude hook emission is Phase 2), so the files under `.claude/hooks/` are Claude-specific — but hooks as a capability are not.

#### "Disable one hook"

```bash
rm .claude/hooks/<name>.sh
# OR remove the entry from .claude/settings.json hooks section
```

#### Windows-specific: `\r: command not found`

CRLF line endings. Fix:

```bash
git config --global core.autocrlf input
git checkout -- .       # re-checkout with LF
```

---

## Memory pattern + ADR index

#### 4-type memory pattern (`core/memory-pattern/`)

CONDUCTOR uses a 4-type memory directory structure that tools without built-in memory directories (Cursor, Copilot, Gemini, Codex, Windsurf) can adopt as a docs convention:

- **project_** — facts about the project (stack, structure, env vars).
- **user_** — facts about the user (preferences, defaults).
- **feedback_** — corrections from past mistakes (rule reminders).
- **reference_** — external IDs, credentials pointers, runbooks.

Claude Code uses `~/.claude/projects/.../memory/`; other tools use `docs/memory/` or equivalent — see `core/memory-pattern/README.md`.

#### Architecture Decision Records (`docs/DESIGN-DECISIONS.md`)

43 ADRs cover the foundational decisions. Highlights:

| ADR | Topic | Why it matters |
|---|---|---|
| **ADR-001** | 3-layer architecture (Universal / Adapter / Tool-native) | Why Conductor is multi-tool from day 1 |
| **ADR-004** | Sub-agents stay Claude-only — no fake polyfill | Honesty principle |
| **ADR-006** | Bilingual (한/영) rule support | Conductor's korean-first roots |
| **ADR-014** | Cache hit rate ≥ 95% SLA | The measurable success criterion |
| **ADR-016** | Reference-adopter ↔ Conductor bidirectional sync | Where production patterns come from |
| **ADR-020** | `--uninstall` + manifest tracking | Why install is reversible |
| **ADR-021** | Cursor adapter (`adapters/cursor/transform.sh`) | Adapter design for `.cursor/rules/*.mdc` |
| **ADR-022** | Copilot adapter (single-format, 5-IDE coverage) | Why one Copilot install covers VSCode + Cursor + Windsurf + JetBrains + Neovim |
| **ADR-023** | Marketplace strategy + cross-platform | Phase 1 (now: bash + npm) → Phase 2 (post-0.3: VSCode extension) |
| **ADR-030** | Self-improvement is opt-in, propose-only | Nothing learns silently — the Reflector proposes, you approve |
| **ADR-035/036** | Instruction-fidelity-first token economy | Reduce tokens without distorting your instructions (context editing, output brevity, `docs/CONTEXT-EDITING-GUIDE.md`) |

Full list and bodies: [`docs/DESIGN-DECISIONS.md`](./docs/DESIGN-DECISIONS.md).

**What changed between versions:** see [`CHANGELOG.md`](./CHANGELOG.md) — every release and its Added / Changed entries, newest first.

---

## FAQ

**Q: Why no marketplace install today?**

A: ADR-023 — the bash adapter is the validated source of truth. A marketplace extension is Phase 2 (post-0.3); the wrapper depends on the adapter being stable in adopter projects first.

**Q: Cursor adopters — do I install from VSCode Marketplace or Open VSX?**

A: Open VSX. Cursor is a VSCode fork but cannot pull from Microsoft's marketplace due to ToS (see ADR-023). When the Phase 2 extension ships, it will be cross-published to both registries so you install with one click regardless.

**Q: My project uses Go / Python / Rust, not TypeScript.**

A: Skip `coding-conventions` (TypeScript-specific). The 5 universal rule bundles and the other 12 recipes are stack-agnostic.

**Q: Windows native PowerShell?**

A: Phase 3+ (ADR-023). Use Git Bash (ships with Git for Windows) or WSL2.

**Q: How do I add custom project-specific rules?**

A: Put them in `AGENT.md` at your target's root (Conductor never overwrites this). Or hand-edit `CLAUDE.md` and `diff` against `CLAUDE.md.conductor-backup-*` after re-installs.

**Q: Mix Conductor with Superpowers / other frameworks?**

A: See `docs/COMPARISON.md` for the conflict-resolution decision tree (3 patterns: Conductor-only / cherry-pick recipes only / both with reconciliation). Running both unmoderated breaks the 95% cache-hit SLA — pick one primary framework.

**Q: Idempotent re-install? Will it clobber my edits?**

A: Re-running `transform.sh` is safe. Every overwrite creates a timestamped backup (`.conductor-backup-YYYYMMDD-HHMMSS`); your prior state is recoverable. `docs/CURRENT_WORK.md` and other doc templates are NEVER overwritten if they already exist.

**Q: Use Conductor before all 6 adapters ship?**

A: Yes — all 6 adapters (Claude / Cursor / Copilot / Gemini / Codex / Windsurf) now ship a `transform.sh`. Install any of them with `bash adapters/<tool>/transform.sh <target>` (or `node bin/omniconductor.js init --target=<tool> <target>`). `docs/MANUAL-INSTALL.md` (copy-paste commands) remains as a fallback only.

**Q: Telemetry?**

A: None. `tools/measure-tokens.sh` reads local Claude Code session JSONL only and writes local CSV. No external network calls anywhere in Conductor.

---

## Contributing

See [`docs/CONTRIBUTING.md`](./docs/CONTRIBUTING.md).

The 3-layer architecture (ADR-001) means:
- New rule → edit `core/universal-rules/` once; all adapters benefit on next install.
- New tool → add `adapters/<tool>/transform.sh` modeled on existing adapters; `core/` untouched.
- New recipe → drop into `core/recipes/`; appears in `--recipes=` automatically.

---

### License

Apache License 2.0 — free and open for any use, including commercial. Only the **CONDUCTOR** name is reserved: it is a trademark of LFamily Labs LLC (take the code, not the name). See `LICENSE`, `NOTICE`, and `TRADEMARKS.md`.

### Credits

Born from one year of production iteration at LFamily Labs. The rules, agents, hooks, and memory patterns that survived real shipping pressure. The bidirectional sync between Conductor and its reference adopter is documented in ADR-016.
