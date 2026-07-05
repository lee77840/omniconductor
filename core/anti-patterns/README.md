---
catalog_id: anti-patterns
description: "Token-economy anti-pattern catalog — diagnostic reference for adopters losing cache hit rate, paying for tool spam, or carrying bloated prefixes."
type: catalog
applies_to: ["all-tools"]
linked_rules:
  - meta-discipline (token economy section)
  - workflow (W2 docs-first, W4 7-step)
linked_docs:
  - docs/PROMPT-CACHING-GUIDE.md
  - docs/CONTEXT-EDITING-GUIDE.md
  - docs/KPI.md
---

# `core/anti-patterns/` — Token-economy anti-pattern catalog

> What goes wrong when CONDUCTOR is installed without discipline. Each entry is grounded in the Anthropic prompt-caching cost model and the P1.5 baseline measurements (`docs/KPI.md`, 2026-05-07).

CONDUCTOR's universal rules describe the *correct* patterns. This catalog describes the **wrong** ones — what they look like, why they damage token efficiency, how to detect them, and the fix. Adopters who follow the universal rules avoid these by construction; the catalog exists for diagnostic use when efficiency drops.

## Index

| # | Anti-Pattern | Severity | Hit-rate impact | Detection signal |
|---|---|---|---|---|
| 01 | [Dynamic system prompt](dynamic-system-prompt.md) | HIGH | -50% to -90% | hit rate < 30% with stable prefix size |
| 02 | [Large-file Read without range](large-file-read-no-range.md) | HIGH | indirect bloat | full-file Read on > 200-line files |
| 03 | [Single monolithic rule file](single-monolithic-rule-file.md) | HIGH | direct cache-write bloat | rule file > 500 lines, no path scoping |
| 04 | [No sub-agent dispatch](no-sub-agent-dispatch.md) | MEDIUM | indirect main-thread bloat | dispatches/session = 0 on multi-feature work |
| 05 | [Frequent rule-file edits](frequent-rule-file-edit.md) | MEDIUM | -20% to -40% / week | > 3 rule-file commits per week |
| 06 | [Tool-call spam](tool-call-spam.md) | MEDIUM | latency + output spike | tool calls / turn > 1.5 |
| 07 | [Skill / MCP eager-load](skill-eager-load.md) | MEDIUM | prefix bloat, hidden multipliers | 30+ eager skills or broad path triggers |
| 08 | [Verbose output / narration](output-verbosity-narration.md) | MEDIUM | output-cost, not cache-hit | output tokens/turn > 1200 with few tool calls |

Severity legend (estimated impact on cache hit rate, derived from Anthropic prompt-caching cost model + P1.5 baseline):
- **HIGH** ≈ -50% or more
- **MEDIUM** ≈ -20%
- **LOW** ≈ -10% (none in the current catalog; reserved for future entries)

## Diagnostic workflow

When efficiency feels off — costs creeping up, latency climbing, sessions getting bloated — run the catalog end-to-end:

1. **Measure the current state.**
   ```bash
   cd <conductor-repo>
   bash tools/measure-tokens.sh --latest
   ```
   Note the four numbers: cache hit rate, tool calls/turn, output tokens/turn, cache-write/session.

2. **Compare to baseline** (`docs/KPI.md` P1.5):

   | Metric | Healthy | Investigate when |
   |---|---|---|
   | Cache hit rate | ≥ 95% | < 90% — start at Anti-Pattern 01 |
   | Tool calls / turn | ≤ 0.8 | > 1.2 — start at Anti-Pattern 06 |
   | Output tokens / turn | ≤ 800 | > 1200 — Anti-Pattern 04 + 06 + 08 likely |
   | Cache-write / session | ≤ 30M | > 50M — Anti-Pattern 02 + 03 + 07 likely |
   | Dispatches / session | 30-150 | 0 on a multi-feature session — Anti-Pattern 04 |

3. **Match the symptom → catalog entry**.

   | Symptom | Suspected anti-pattern(s) |
   |---|---|
   | Cache hit rate dropped this week, no other change | 01, 05 |
   | Session JSONL ballooning past 100MB | 02, 04, 07 |
   | Latency creeping per turn over the session | 02, 04 |
   | High output cost on apparently simple tasks | 04, 06, 08 |
   | First-turn cost (before user types anything) is large | 03, 07 |
   | Cache hit rate fine inside session but resets each new session | 05 |

4. **Read the matching catalog entry's §3 Detection + §4 Fix.** Apply the fix; re-measure after one full session.

5. **If multiple anti-patterns apply**, address them in severity order (HIGH → MEDIUM). The HIGH entries are usually 80% of the cost.

## Reference points cited across this catalog

- **Anthropic prompt caching docs** — cost model (cache-write 1.25× / 2×, cache-read 0.1×, prefix-match-only).
- **CONDUCTOR P1.5 baseline** (`docs/KPI.md`, 2026-05-07) — 8 sessions on a single active project, 100% cache hit rate ceiling, avg 0.61 tool calls / turn, avg 27.4M cache-write / session.
- **`core/universal-rules/meta-discipline.md` §5** — token economy rules (Read discipline, hidden injection, dispatch budget, cache-friendly prompt order, tool description compression, touched-file rule scoping).
- **`docs/PROMPT-CACHING-GUIDE.md`** — full Claude-adapter caching guide.
- **`docs/CONTEXT-EDITING-GUIDE.md`** — instruction-fidelity-first context reduction (lossless `clear_tool_uses` before lossy `/compact`).

The reference project measured in `KPI.md` is one specific monorepo (the originating workspace). Numbers in catalog entries are *estimates anchored to that baseline*. Other projects will see different absolute numbers but the same *direction* — the anti-patterns degrade efficiency on every codebase.

## What is NOT in this catalog

- **Code-correctness anti-patterns** (silent failures, type-design issues) — those live in role-specific reviewer guidance, not in token-economy rules.
- **Workflow anti-patterns** (skipping reviews, batching unsafe edits) — those are in `core/universal-rules/workflow.md` and `quality-gates.md`.
- **Tool-specific quirks** (Cursor-only, Copilot-only) — those live in `adapters/<tool>/`.

This catalog is exclusively about how an installation degrades the **token economy** layer of CONDUCTOR.

## Contributing new entries

A new catalog entry is justified when:

1. The pattern has been observed in production (cite the session / project).
2. The cost model is quantifiable (Anthropic pricing or measure-tokens output).
3. The fix references an existing universal-rule or recipe — not a new ad-hoc rule.
4. Severity is honestly assessed against the rubric in this README.

File template: copy any existing entry; preserve the frontmatter schema; keep the file ≤ 200 lines.

---

# `core/anti-patterns/` — 토큰 경제 안티패턴 카탈로그 (한글 요약)

CONDUCTOR universal rules가 *옳은* 패턴을 기술한다면, 이 카탈로그는 **그 반대** — 무엇이 잘못되는가, 왜 토큰 효율을 망가뜨리는가, 어떻게 감지하고 어떻게 고치는가 — 를 기록한다. universal-rules 를 따르면 이 안티패턴들은 자연스럽게 회피된다. 이 카탈로그는 효율이 떨어졌을 때 *진단용* 으로 사용한다.

## 카탈로그 인덱스

| # | 안티패턴 | 심각도 | hit-rate 영향 | 감지 시그널 |
|---|---|---|---|---|
| 01 | [동적 system prompt](dynamic-system-prompt.md) | HIGH | -50% ~ -90% | prefix 크기는 안정인데 hit rate < 30% |
| 02 | [범위 없는 대형 파일 Read](large-file-read-no-range.md) | HIGH | 간접 bloat | 200줄 이상 파일 전체 Read |
| 03 | [단일 거대 룰 파일](single-monolithic-rule-file.md) | HIGH | 직접적인 cache-write 폭증 | 룰 파일 500줄 초과 + path 스코프 미사용 |
| 04 | [sub-agent dispatch 미사용](no-sub-agent-dispatch.md) | MEDIUM | main thread 누적 bloat | 멀티-피처 세션인데 dispatch = 0 |
| 05 | [잦은 룰 파일 수정](frequent-rule-file-edit.md) | MEDIUM | 주당 -20% ~ -40% | 주 3회 이상 룰 파일 commit |
| 06 | [tool-call 스팸](tool-call-spam.md) | MEDIUM | latency + output 폭증 | tool calls / turn > 1.5 |
| 07 | [Skill / MCP eager-load](skill-eager-load.md) | MEDIUM | prefix bloat, 숨은 multiplier | eager skill 30개 초과 또는 광범위 path trigger |
| 08 | [장황한 출력 / 나레이션](output-verbosity-narration.md) | MEDIUM | cache-hit 아닌 output 비용 | tool call 적은데 output tokens/turn > 1200 |

## 진단 워크플로 (요약)

1. `bash tools/measure-tokens.sh --latest` 실행 → cache hit rate / tool calls per turn / output tokens per turn / cache-write per session 4개 수치 확인.
2. `docs/KPI.md` P1.5 baseline 과 비교 — 어느 수치가 빠졌는지 파악.
3. 위 인덱스의 "감지 시그널" 컬럼으로 의심 안티패턴 매칭.
4. 해당 카탈로그 항목의 §3 (Detection) + §4 (Fix / Alternative) 읽고 적용.
5. 한 세션 분량 작업 후 다시 측정. HIGH 부터 처리하면 보통 비용의 80% 가 잡힌다.

## 카탈로그에 포함되지 *않는* 것

- 코드 정확성 안티패턴 (silent failure, type design 문제) — reviewer role guidance 영역.
- 워크플로 안티패턴 (review skip, 위험한 batch edit) — `core/universal-rules/workflow.md`, `quality-gates.md` 영역.
- Tool 별 quirk — `adapters/<tool>/` 영역.

이 카탈로그는 오직 **토큰 경제** 레이어에서 일어나는 효율 저하만 다룬다.

## 새 항목 추가 기준

1. 실제 운영 중 관찰된 패턴 (세션 / 프로젝트 인용).
2. 비용이 정량화 가능 (Anthropic pricing 또는 measure-tokens 출력 기반).
3. 해결책이 기존 universal-rule / recipe 를 참조 — 새 ad-hoc 룰 만들지 않을 것.
4. 심각도는 README 의 기준표에 솔직하게 평가.

파일 템플릿: 기존 항목 복사. frontmatter 스키마 유지. 200줄 이하 유지.
