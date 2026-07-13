# CONDUCTOR

**One workflow framework, every coding agent.**

Write your project's rules, workflow, and discipline ONCE. Install into any AI coding tool you use — Claude Code, Cursor, GitHub Copilot, Gemini CLI, Codex, Windsurf — and get the same Plan → Architecture → Tasks → Implementation → Review → Spec discipline everywhere.

> Born from one year of production iteration at LFamily Labs — the rules, agents, hooks, and memory patterns that survived real shipping pressure.

> **Status (v1.1.0 — 2026-07-13)**: All 6 adapters ship a working `transform.sh` plus one-time, project-saved Tier-model setup — **Claude Code**, **Cursor**, **GitHub Copilot**, **Gemini CLI**, **Codex**, and **Windsurf / Devin Desktop**. Output is emit-verified on all six; **Claude Code + Codex are additionally live-verified** by the automated headless probe (`tools/live-verify.sh`), while current per-tool status remains in [`docs/ADAPTER-LIVE-VERIFICATION.md`](./docs/ADAPTER-LIVE-VERIFICATION.md). Windsurf model routing is explicitly advisory-session because its workflow schema cannot pin the Cascade selector. Manual install ([`docs/MANUAL-INSTALL.md`](./docs/MANUAL-INSTALL.md)) remains a fallback.
>
> **New in 1.1.0**: the first CLI install now asks once for Tier 1/2/3 models, saves a revisioned project mapping, regenerates native roles on explicit reconfiguration, fails closed in unconfigured CI, and distinguishes configured, provider-controlled, and advisory routing. It also includes the six-adapter runtime/ownership and bounded Codex-kernel hardening. Earlier releases: [`CHANGELOG.md`](./CHANGELOG.md).
>
> **Publication boundary**: development is maintained in a private source repository; users receive a deliberately filtered public mirror and npm package. The private source repository must never be made public. See [`docs/PUBLICATION-POLICY.md`](./docs/PUBLICATION-POLICY.md).
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
- **Layer 3 — Tool-native (정직한 한계)**: full/strict 설치는 Claude·Cursor·Copilot·Gemini·Codex의 8개 네이티브 역할 파일을 생성하고, Windsurf에는 확인된 커스텀 에이전트 파일 계약 대신 8개 역할 워크플로를 설치한다. Claude는 전체 가드 훅, Codex는 검증된 `PreToolUse`/`Stop` 부분집합, 나머지는 검증된 Reflector 훅만 생성한다. 지원되지 않는 계약은 가짜로 폴리필하지 않는다 (ADR-004 / ADR-045/049).

### 강제하는 워크플로

1. **Plan → Architecture → Tasks → Implementation → Review → Spec** (skip 금지)
2. **Spec-as-you-go** — 코드 변경 시 `docs/specs/*.md` 동시 업데이트 (Claude/Codex는 Stop hook 검증, 나머지는 룰 reminder)
3. **2-stage 코드 리뷰** — pre-commit + pre-merge
4. **Token economy** — large-file Read 금지 / Grep first / range read
5. **Difficulty routing** — 기존 Tier 1/2/3 난이도를 고정하고, 최초 설치에서 승인한 도구별 모델과 reasoning effort로 변환

최초 `npx omniconductor init`은 설치된 도구들의 추천 Tier 매핑을 한 번에
보여주고 “추천 그대로 / 사용자 지정”을 묻습니다. 선택은
`.conductor/model-routing.json`에 저장되어 재설치부터는 다시 묻지 않으며,
`omniconductor models configure`로 변경합니다. 새 모델이 출시되어도 Tier
판정은 바뀌지 않고, 사용할 수 없어진 정확한 ID는 자동 하향하지 않고
재설정을 요구합니다. 세부 정책은
[`docs/MODEL-ROUTING.md`](docs/MODEL-ROUTING.md)를 참고하세요.

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

# 5. Claude Code 재시작 → /agents 로 8개 기본 역할 확인
```

### 설치 방법 (3가지)

- **Path A — `npx` (권장, 클론 불필요)**: `npx omniconductor init --target=<tool> <dir>` — 최초 실행에서 Tier 모델을 한 번 설정합니다. `models configure/show` · `list` · `doctor` · `--dry-run` · `--recipes=A,B` · `--mode=<preset>` · `--uninstall` 지원.
- **Path B — 로컬 bash 래퍼**: CONDUCTOR 클론과 Node.js 필요. `bash adapters/<tool>/transform.sh <dir> [--recipes=...] [--dry-run]`은 동일한 Node CLI로 위임되므로 Path A와 같은 최초 Tier 설정·저장 절차를 실행합니다.
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
- **Layer 3 — Tool-native (honest limits)**: full/strict installs emit eight native role files for Claude, Cursor, Copilot, Gemini, and Codex. Windsurf receives eight native role workflows because no project-local custom-agent profile contract has been verified. Claude gets the full guard set; Codex gets the verified `PreToolUse`/`Stop` subset; other adapters emit only hooks whose native contract is verified. Unsupported contracts are never fake-polyfilled (ADR-004 / ADR-045/049).

### Why this exists

- Solo developers and small teams increasingly mix AI coding tools within a single project.
- Switching tools means re-writing rules from scratch — losing the same discipline you spent months building.
- CONDUCTOR lets you write the discipline once and keep it across tools.

### Workflow enforced

1. **Plan → Architecture → Tasks → Implementation → Review → Spec** (no skipping)
2. **Spec-as-you-go**: code change touches matching `docs/specs/*.md` (checked by Stop hooks on Claude/Codex; rule-text reminder elsewhere)
3. **Two-stage code review**: pre-commit + pre-merge PR
4. **Token economy**: no large-file reads, Grep first, range reads
5. **Difficulty routing**: preserve Tier 1/2/3, then compile the one-time saved per-tool model mapping and reasoning effort

The first `npx omniconductor init` shows all selected adapters and asks once whether
to accept the recommended Tier mappings or customize them. The project saves the
choice in `.conductor/model-routing.json`; reinstall reuses it and
`omniconductor models configure` changes it. Provider releases never change Tier
classification, and an unavailable exact model is never silently downgraded. See
[`docs/MODEL-ROUTING.md`](docs/MODEL-ROUTING.md).

### Quick Start (5 minutes, Claude)

> Simplest (no clone): `npx omniconductor init --target=claude .` — recommended
> because it needs no clone. The clone+bash path below requires Node.js and
> delegates to the same CLI, so it performs the identical one-time saved model setup.

```bash
git clone https://github.com/lee77840/omniconductor ~/conductor
cd ~/your-project
bash ~/conductor/adapters/claude/transform.sh . \
  --recipes=monorepo,coding-conventions \
  --dry-run                      # preview
bash ~/conductor/adapters/claude/transform.sh . \
  --recipes=monorepo,coding-conventions
# Restart Claude Code → /agents → confirm 8 base roles loaded
```

Other tools: see [Install paths](#install-paths). Windows: see [Cross-platform](#cross-platform-mac-and-windows).

---

## Tool coverage matrix

Separate two things (per [`docs/COMPATIBILITY-MATRIX.md`](./docs/COMPATIBILITY-MATRIX.md), re-verified against first-party sources 2026-07-04, ADR-031):

- **Tool capability** — capability varies by product and version; the matrix records only verified native surfaces.
- **CONDUCTOR emission** — every full/strict adapter now emits a role entry in the strongest verified native form. Hook coverage remains capability-specific: full on Claude, a verified guard subset on Codex, and verified recipe/runtime hooks elsewhere.

The columns below show **CONDUCTOR emission today**:

| Tool | Adapter (rules) | Hooks | Sub-agents | Difficulty/model translation | Recommended install |
|---|---|---|---|---|---|
| **Claude Code** | ✅ Full, lazy load | ✅ full Stop / PreToolUse set | ✅ 8 roles (+ reflector recipe) | Saved Opus / Sonnet / Haiku | `bash adapters/claude/transform.sh <target>` |
| **Cursor** | ✅ Full, lazy load (`.mdc` globs) | Reflector hook when selected | ✅ 8 `.cursor/agents` profiles | Saved exact Tier models; provider fallback disclosed | `bash adapters/cursor/transform.sh <target>` |
| **GitHub Copilot** | ✅ Full (`applyTo:` scoping) | Reflector hook when selected | ✅ 8 `.github/agents` profiles | Saved exact Tier models; policy risk disclosed | `bash adapters/copilot/transform.sh <target>` |
| **Gemini CLI** | ✅ Full (`GEMINI.md`) | Reflector hook when selected | ✅ 8 `.gemini/agents` profiles | Saved `pro` / `flash` / `flash-lite` recommendation | `bash adapters/gemini/transform.sh <target>` |
| **Codex (OpenAI)** | ✅ Bounded `AGENTS.md` kernel + complete `.codex/conductor/` references | ✅ verified commit/session/review guards | ✅ 8 `.codex/agents` profiles | Saved Sol / Terra / Luna + Tier effort | `bash adapters/codex/transform.sh <target>` |
| **Windsurf** | ✅ Full (`.windsurfrules` + `.devin/rules/*`) | Reflector response hook when selected | ✅ 8 invocable role workflows | Adaptive advisory-session | `bash adapters/windsurf/transform.sh <target>` |

Full per-feature matrix + first-party footnotes: [`docs/COMPATIBILITY-MATRIX.md`](./docs/COMPATIBILITY-MATRIX.md).

> **CLI wrapper**: `npx omniconductor init --target=<tool> <dir>` performs the one-time model setup, then dispatches to the adapter scripts. `models configure/show`, `list`, `--dry-run`, `--recipes=`, and `--uninstall` are available. **`npx omniconductor doctor <dir>`** also distinguishes saved configuration from provider-enforced or advisory routing.

> **What you keep going Claude → other tools**: rule text, docs, workflow phases, the eight-role topology including Tier 3 utility, and the opt-in Reflector loop. Mechanical guard coverage is intentionally not claimed as identical: each adapter emits only contracts verified for that product.

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
npx omniconductor models show .                       # inspect saved Tier mappings
npx omniconductor models configure --target=all .     # change mappings
npx omniconductor init --target=claude . --dry-run --no-prompt   # preview, writes nothing
npx omniconductor init --target=all . --no-prompt --accept-model-defaults  # explicit noninteractive setup
npx omniconductor init --target=claude . --uninstall             # revert
```

> **VSCode Marketplace extension** — a Cmd/Ctrl+Shift+P "install" launcher — is **NOT yet published**. It is optional future work (Phase 2 / v0.3; the source-repository scaffold is under `phase-2/vscode-extension/`, and the procedure is in [`docs/PUBLISH-GUIDE.md`](./docs/PUBLISH-GUIDE.md)). `npx omniconductor` and the bash adapter (Path B) already cover every install — the extension would only add a GUI button, and (per ADR-025) it still needs a local clone to run, so `npx` is the better path. Searching the Marketplace today will **not** find it.

### Path B — local bash wrapper (Node.js required)

Single command per tool after cloning the repository. Each wrapper requires
Node.js and delegates to the same CLI used by Path A, including the one-time
project-saved Tier setup, then runs the adapter with exact argument boundaries.
Output remains idempotent with timestamped backups.

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
| **Linux** (Ubuntu, Debian, Fedora, Arch) | ✅ Supported | bash | Supported by the local validation suite and manual-only GitHub release workflows. |
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
| `git-hygiene` | Any git project — esp. multi-session/agent repos or protected branches | Shared-repo discipline (G1–G7): no unrequested worktrees, push-don't-hoard, merge=delete-branch, backup≠applied (verify by real code), no reckless force/rebase on shared repos, bundle PRs for CI, session-end hygiene check. Claude and Codex add verified non-blocking Stop reminders; other adapters install the checklist. See ADR-037/045. |
| `loop-engineering` | Any agentic loop (generate→verify→fix→re-verify, test-fix, multi-step) | Bounded, externally-verified loops (G1–G6): explicit done-criterion, iteration+token budget, require-progress, escalate-on-stall, **verify externally never by self-judgment**, oscillation guard. Claude and Codex add verified `PreToolUse` reminders in their own hook dialects; other adapters install the rule text. See ADR-038/045. |

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
| `--mode=<m>` | Install preset (v1.0, ADR-044): `full` (default) · `minimal` (rule text + docs only — no agents/hooks/Reflector runtime) · `strict` (abort with exit 3 instead of touching an existing baseline) · `recipes-only` (à la carte: ONLY selected recipes; Gemini appends a hash-tracked block, while Codex appends compact pointers to full `.codex/conductor/recipes/` references; uninstall is lossless) · `reflector-only` (the self-improvement loop standalone — least-conflicting when coexisting with Spec Kit / BMAD, which the installer detects and suggests, never auto-switches). |
| `--dry-run` | Preview only — no files written. |
| `--measure-baseline` | Run `tools/measure-tokens.sh --latest` after install; save CSV; auto-show anti-patterns if cache hit < 95%. |
| `--no-prompt` | Skip interactive prompts. Reuses an existing saved model map; a first role-emitting install must also pass `--accept-model-defaults` or provide a reviewed config. |
| `--accept-model-defaults` | Explicitly accept the recommended Tier mappings during an unconfigured non-interactive install. Required with `--no-prompt` when role-emitting output has no saved model routing yet. |
| `--check-anti-patterns` | Print `core/anti-patterns/README.md` inline and pause 5 seconds. |
| `--uninstall` (alias `--rollback`) | Manifest-based revert on all six adapters (see [Update](#update--maintenance--uninstall)). |
| `--force` | Bypass uninstall safety gates (active rebase/merge, missing manifest). |
| `-h` `--help` | Print usage. |

**Recipe names** (13): `web-mobile-parity`, `i18n`, `monorepo`, `branch-strategy`, `auto-mock-data`, `coding-conventions`, `tdd`, `debugging`, `database-discipline`, `design-system`, `self-improvement`, `git-hygiene`, `loop-engineering`.

#### File overwrite behavior

| File | Already exists |
|---|---|
| `CLAUDE.md` / `GEMINI.md` / `AGENTS.md` / `.github/copilot-instructions.md` | Backed up to `.conductor-backup-YYYYMMDD-HHMMSS`, then overwritten (`--mode=strict`: aborts instead) |
| Tool-native rule files | Backed up + overwritten when CONDUCTOR owns the path |
| Tool-native agent/workflow files | Backed up + overwritten when CONDUCTOR owns the path |
| Verified hook scripts/config | Manifest-managed; user-owned hook config is preserved when safe merge is unavailable |
| `.claude/hookify.*.local.md` | **Preserved** (adopter customizations win) |
| `docs/CURRENT_WORK.md` etc. | **Preserved** (never overwritten) |

---

## Update / Maintenance / Uninstall

### Update Conductor itself

```bash
cd ~/conductor && git pull
```

Then re-run `transform.sh` on each target — installs are idempotent. An unchanged CONDUCTOR file retains its original pre-install backup; a user-edited emitted file is backed up before replacement. Manifest entries record the emitted SHA-256 to make uninstall non-destructive.

### Maintainer release verification

Routine validation is local; GitHub Actions do not run on pushes or pull requests.
The integrated command tests the exact npm tarball as both a fresh six-tool install
and an in-place upgrade from the published previous release, then performs an npm
publish dry run. It never pushes, dispatches CI, or publishes:

```bash
npm run release:verify:local
```

After committing the release candidate, the strict form additionally requires a
clean tree and verifies the exact committed public snapshot:

```bash
CONDUCTOR_RELEASE_REQUIRE_CLEAN=1 npm run release:verify:local
```

The two GitHub workflows remain disabled and manual-only. A maintainer may dispatch
them immediately before a necessary release as an optional extra check; no automatic
reactivation is scheduled. See
[`docs/PUBLICATION-POLICY.md`](docs/PUBLICATION-POLICY.md).

### Re-measure cache hit (1 week after install)

```bash
bash ~/conductor/tools/measure-tokens.sh --latest
```

Compare against the `.conductor/baseline-YYYYMMDD.csv` from `--measure-baseline` at install time. KPI target: cache hit rate ≥ 95% (ADR-014 SLA).

### Uninstall (revert install)

All six adapters ship `--uninstall` with adapter-scoped manifest ownership
(ADR-020/047). Use the adapter that owns the surface you want to remove, or
`omniconductor init --target=all . --uninstall` for the aggregate teardown.

```bash
# Preview
bash ~/conductor/adapters/claude/transform.sh ~/your-project --uninstall --dry-run

# Apply
bash ~/conductor/adapters/claude/transform.sh ~/your-project --uninstall
```

Behavior:
- For each unchanged manifested file: restore its original backup if one exists, otherwise delete it.
- A manifested file whose SHA-256 differs (or a legacy manifest without a checksum) is treated as user-modified and left in place with a warning; any original backup is retained for recovery.
- Adopter-customized files outside the manifest are preserved.
- Manifest-history backup siblings are cleaned up; retained original backups are never deleted when a user-modified file needs them.
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

#### "Hooks not firing"

```bash
ls -la .claude/hooks/        # verify executable bit (-rwxr-xr-x)
chmod +x .claude/hooks/*.sh  # grant if missing
# Restart Claude Code
```

Run `npx omniconductor doctor .` first. For Codex, also run `/hooks` and trust the exact project hook definitions after every install or change. Other tools use their own native hook registries; see the adapter README rather than copying Claude hook JSON or tool names.

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

CONDUCTOR uses one 4-type memory taxonomy across all tools. Claude, Copilot
preview, Codex opt-in, and Windsurf map it to verified managed-memory locations;
Cursor and Gemini use the documented project-local fallback until a stable native
contract is verified. See `core/memory-pattern/README.md` for current paths and
caveats.

- **project_** — facts about the project (stack, structure, env vars).
- **user_** — facts about the user (preferences, defaults).
- **feedback_** — corrections from past mistakes (rule reminders).
- **reference_** — external IDs, credentials pointers, runbooks.

Memory persistence is tool-specific: Claude, Copilot, Codex, and Windsurf have
verified managed mechanisms, while Cursor/Gemini use the documented portable
fallback when a native equivalent is unavailable. See `core/memory-pattern/README.md`.

#### Architecture Decision Records (`docs/DESIGN-DECISIONS.md`)

44 ADRs cover the foundational decisions. Highlights:

| ADR | Topic | Why it matters |
|---|---|---|
| **ADR-001** | 3-layer architecture (Universal / Adapter / Tool-native) | Why Conductor is multi-tool from day 1 |
| **ADR-004** | Historical no-fake-polyfill boundary; native role emission later superseded by ADR-045 | Honesty principle preserved |
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

A: Re-running `transform.sh` is safe. An unchanged emitted file keeps its first pre-CONDUCTOR backup; an edited emitted file is snapshotted before replacement. `--uninstall` preserves any file whose emitted SHA-256 no longer matches, rather than deleting it. `docs/CURRENT_WORK.md` and other doc templates are NEVER overwritten if they already exist.

**Q: Use Conductor before all 6 adapters ship?**

A: Yes — all 6 adapters (Claude / Cursor / Copilot / Gemini / Codex / Windsurf) now ship a `transform.sh`. Install any of them with `bash adapters/<tool>/transform.sh <target>` or `node bin/omniconductor.js init --target=<tool> <target>`; both require Node.js and run the same one-time model-routing transaction. `docs/MANUAL-INSTALL.md` (copy-paste commands) remains the no-Node fallback.

**Q: Telemetry?**

A: None. Installation and `tools/measure-tokens.sh` send no usage data; the latter
reads local Claude Code session JSONL and writes local CSV only. Maintainer release
verification contacts npm solely to fetch the declared previous package (unless a
local tarball is supplied) and to perform the explicit publish dry run.

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
