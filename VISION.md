# VISION — CONDUCTOR

## The problem

> **한글:** AI 코딩 도구가 우후죽순 늘어났습니다. 2026년의 개발자 한 명이 Claude Code (깊은 리팩터), Cursor (IDE 내 페어 프로그래밍), GitHub Copilot (인라인 자동완성 + PR 리뷰), Gemini CLI (저렴한 대용량 컨텍스트 탐색), Codex (셸 기반 작업), Windsurf 를 동시에 쓸 수 있습니다. 그런데 도구마다 룰·컨텍스트 포맷이 제각각입니다. **도구를 바꾸는 순간 그동안 쌓은 규율이 사라집니다.** Claude 용으로 쓴 룰은 Cursor 에서 자동 로드되지 않고, 스스로 훈련해 온 Plan → Architecture → Tasks 워크플로는 다른 에이전트를 여는 순간 증발합니다. 6개월간 다듬은 취향이 통째로 날아갑니다. 이것이 CONDUCTOR 가 푸는 문제입니다.

AI coding tools have multiplied. A single developer in 2026 might use:

- **Claude Code** for deep refactors and multi-file work (Anthropic's CLI agent).
- **Cursor** for in-IDE pair programming with native completion + chat.
- **GitHub Copilot** for inline autocomplete and PR review.
- **Gemini CLI** for cheap large-context exploration.
- **Codex** (OpenAI) for shell-driven tasks.
- **Windsurf** when collaborating with someone who prefers it.

Each tool has its own rules-and-context format:

| Tool | Rules file | Rule scoping | Sub-agents | Hooks |
|---|---|---|---|---|
| Claude Code | `CLAUDE.md` + `.claude/rules/*.md` + `.claude/agents/*.md` | glob-based via paths front-matter | ✅ Agent tool | ✅ PreToolUse / Stop / etc. |
| Cursor | `.cursorrules` + `.cursor/rules/*.mdc` | `globs:` front-matter on `.mdc` | ✅ (2.4+) | ✅ (v1.7) |
| GitHub Copilot | `.github/instructions/*.instructions.md` + AGENTS.md | `applyTo:` front-matter | ✅ | ✅ (CLI + agent) |
| Gemini CLI | `GEMINI.md` + AGENTS.md (opt-in) | nested-file hierarchy | ✅ | ✅ (v0.26) |
| Codex | `AGENTS.md` | nested-file hierarchy | ✅ | ✅ |
| Windsurf / Devin Desktop | `.devin/rules/*.md` (legacy `.windsurf/rules/`) | directory-based | ✅ (Devin Local) | ⚠️ no session/stop events |

> As of 2026, sub-agents and hooks are **no longer Claude-only** — every tool ships them (first-party verified 2026-07-04; see `docs/COMPATIBILITY-MATRIX.md`). CONDUCTOR's problem is unchanged, because what still diverges is the **format**: each tool has a different rules file + scoping syntax, and a rule written for one does not auto-load in another. That portability gap — not a raw capability gap — is what CONDUCTOR closes. (2026년 기준 sub-agent·hook 은 더 이상 Claude 전용이 아니며 모든 도구가 지원합니다. 그럼에도 여전히 **포맷**이 제각각이라 CONDUCTOR 가 푸는 문제는 그대로입니다.)

**Switch tools → lose your discipline.** The rules you wrote for Claude don't auto-load in Cursor. The Plan → Architecture → Tasks workflow you trained yourself to follow disappears the moment you open a different agent. Six months of accumulated taste — gone.

This is the problem CONDUCTOR solves.

## The solution

> **한글:** 프로젝트의 규율을 도구 독립적인 포맷으로 **단 한 번** 작성하세요. 도구별로 명령어 하나만 실행하면, CONDUCTOR 가 해당 도구에 맞는 파일을 올바른 경로·올바른 포맷으로 생성합니다 (`core/` 에 룰을 한 번 쓰면 → `.claude/` / `.cursor/rules/` / `.github/instructions/` / `GEMINI.md` / `.codex/codex.md` / `.windsurfrules` 로 변환). 같은 Plan → Architecture → Tasks 워크플로가, 그날 개발자가 어떤 도구를 쓰든 프로젝트의 모든 에이전트를 동일하게 지배하게 됩니다.

Write your project's discipline ONCE in a tool-agnostic format. Run a single command per tool, and CONDUCTOR generates the right files at the right paths in the right format for that specific tool.

```
core/                    ← write rules here, ONCE
  ├── workflow/
  ├── universal-rules/
  ├── docs-templates/
  └── memory-pattern/

  ↓  bash adapters/<tool>/transform.sh <target>   (6 adapters today; an npx wrapper is planned)

target-project/
  ├── .claude/             (if --target=claude)
  ├── .cursor/rules/       (if --target=cursor)
  ├── .github/instructions/ (if --target=copilot)
  ├── GEMINI.md             (if --target=gemini)
  ├── AGENTS.md             (if --target=codex)
  └── .windsurf/rules/      (if --target=windsurf)
```

The same Plan → Architecture → Tasks workflow now governs every agent in the project, regardless of which tool the developer happens to be using that day.

## Audience

> **한글:** **주 대상**은 AI 코딩 도구로 프로덕션 소프트웨어를 출시하는 1인 개발자와 2~3인 팀입니다. 이들은 룰을 직접 다시 쓰는 당사자이고, 위에서 강제되는 조직 표준이 없기 때문에 도구 전환의 고통을 가장 절실히 느낍니다. 또한 하나의 도구로 표준화하기보다 전술적으로 도구를 골라 씁니다 (빠른 UI 반복은 Cursor, 깊은 리팩터는 Claude). **부 대상**은 서로 다른 AI 도구를 쓰는 기여자들이 모두 같은 프로젝트 컨벤션을 따르길 바라는 오픈소스 메인테이너입니다.

**Primary**: solo developers and 2-3-person teams shipping production software with AI coding tools.

These users feel the tool-switching pain most acutely because they personally do the rule-rewriting and they do not have an org-wide standard imposed from above. They also pick tools tactically (Cursor for fast UI iteration, Claude for deep refactors) instead of standardizing on one.

**Secondary**: open-source maintainers who want contributors using different AI tools to all follow the same project conventions.

## Non-goals

> **한글:** CONDUCTOR 는 의도적으로 다음이 **아닙니다**: 프로젝트 관리 도구가 아니며 (티켓·스프린트·칸반 없음, CURRENT_WORK.md 는 보드가 아니라 텍스트 파일 하나), 엔터프라이즈 팀 관리 제품이 아니며 (SSO·관리자 UI·감사 로그 없음, 1인/소규모 범위), 스스로 학습하는 에이전트가 아니며 (메모리는 사용자가 쓴 것만 쌓이고, 조용히 학습하지 않음. 옵트인 Reflector 가 세션 궤적에서 메모리/룰 변경을 *제안* 할 수 있으나, 사람 승인 없이는 아무것도 적용되지 않습니다 — 제안은 조용한 학습이 아닙니다), 모델 라우터 제품이 아니며 (라우팅은 룰 텍스트일 뿐 실제 추론 프록시를 돌리지 않음), 텔레메트리 벤더가 아니며 (phone-home·사용 통계 없음, 디스크 위 파일뿐), 모든 도구 기능의 상위 집합이 아닙니다 (sub-agent 는 Claude 에만 존재하며, Cursor 에서 셸 프로세스로 가짜 흉내 내지 않고 Layer 3 가 그 한계를 솔직히 인정합니다).

CONDUCTOR is intentionally NOT:

- **A project management tool.** No tickets, no sprints, no Kanban. CURRENT_WORK.md is a single text file, not a board.
- **An enterprise team-management product.** No SSO, no admin UI, no audit log. Solo / small-team scope only.
- **A self-improving / agentic auto-learner.** Memory accumulates only what the user (or the orchestrator on the user's behalf) writes. Nothing learns silently. An opt-in Reflector may *propose* memory/rule deltas from session trajectories, but nothing is applied without human approval — proposing is not silent learning.
- **A model-router product.** Model routing is a *rule* text that travels via CONDUCTOR; the actual routing happens inside Claude Code (and only Claude Code). We do not run an inference proxy.
- **A telemetry vendor.** No phone-home, no usage stats, no opt-in tracking. Files on disk only.
- **A super-set of every tool's features.** Sub-agent dispatch only exists in Claude. We refuse to fake it on Cursor by spawning shell processes — that is fragile and confusing. Layer 3 acknowledges these gaps openly.

## Why this can win

1. **Bilingual (한/영) is a moat.** All major competitors (GSD, SpecKit, BMAD, Cursor Rules) are English-first. Korean solo devs are a meaningful early-adopter pool with high willingness to share what works.
2. **Production-pedigree.** Born from a real shipping project at LFamily Labs — every rule earned through an incident, not theorized in a blog post.
3. **Honest about limits.** We will not pretend Cursor can do sub-agents. Other multi-tool projects gloss over this; CONDUCTOR's documentation calls it out explicitly. That builds trust.
4. **Opinionated, light.** GSD has 60+ skills and is a maximalist superset. CONDUCTOR has 5 universal rules + 8 sub-agent definitions and is intentionally a small, opinionated kernel.

## Why this might fail

- **Fragmentation accelerates faster than adapters can keep up.** If 12 new tools launch in 2026, we can't write 12 new adapters.
  Mitigation: `docs/CONTRIBUTING.md` makes adding a new adapter a well-documented community contribution.
- **Tools converge on a common format.** If GitHub, Anthropic, OpenAI, Google all agree on `.airules/*.mdc` (unlikely soon), CONDUCTOR's transform layer becomes redundant.
  Mitigation: even with a common format, the *opinionated* universal-rules content + workflow definitions remain valuable.
- **Solo-dev market is too narrow.** Maybe everyone settles on one tool.
  Mitigation: even single-tool users benefit from the rule + agent + workflow library.

## Success in 12 months

By 2027-05:

- 6 tool adapters working end-to-end.
- 50+ GitHub stars, 5+ community-contributed adapter PRs.
- The originating LFamily Labs product ships v1.0 using CONDUCTOR as its production scaffold (eat-our-own-dogfood case study).
- One Korean and one English Show HN / launch tweet.
- Free and open under Apache 2.0 (commercial use included); the CONDUCTOR name is a trademark of LFamily Labs LLC. File-on-disk, no telemetry.
