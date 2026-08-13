# OMNICONDUCTOR Token Economy — 한국어 가이드

OMNICONDUCTOR의 Token Economy는 모델에게 단순히 “짧게 답하라”고 지시하는
기능이 아니다. AI coding agent의 컨텍스트가 커지는 원인을 다음 순서로 줄이는
운영 계층이다.

1. 불필요한 파일 입력을 만들지 않는다.
2. 과도한 tool output이 대화 기록에 저장되지 않게 제한한다.
3. 항상 로드되는 rules·skills·tool schema를 최소화한다.
4. 반복되는 안정된 prefix는 prompt cache가 재사용하기 좋은 순서로 유지한다.
5. 오래된 tool result부터 제거하고 사용자의 원래 지시는 보존한다.
6. 쉬운 작업은 적절한 Tier와 역할로 격리한다.
7. 실제 로컬 세션 수치로 효과와 활성 상태를 검증한다.

핵심은 **사용자 요구사항을 압축해서 토큰을 아끼는 것이 아니라, 이미 사용한
tool result와 저신호 고정 컨텍스트를 먼저 줄이는 것**이다.

## 한눈에 보는 적용 수준

Token Economy 기능은 모두 같은 강도로 동작하지 않는다.

| 분류 | 의미 | 대표 기능 |
|---|---|---|
| **자동 강제** | 설치된 native config 또는 hook이 실제 호출을 제한 | Claude large-read guard, Claude/Codex/Gemini output cap |
| **구조적 절약** | 설치물이 상시 컨텍스트를 작게 유지하도록 구성 | 5 universal rules, opt-in recipes, on-demand skills, bounded Codex kernel |
| **운영 규칙** | 모든 adapter에 같은 원칙을 배포하지만 도구가 기계적으로 강제하지 않을 수 있음 | Grep first, range read, bounded dispatch, output brevity |
| **측정·진단** | 자동 절약 여부를 로컬 증거로 확인 | `doctor`, `measure-tokens.sh`, `audit-token-economy.js` |
| **공급자 가이드** | 사용자가 provider/API 기능을 구성할 때 적용 | Claude prompt caching, context editing |

이 구분을 생략하면 “규칙 파일에 써 있다”와 “실제로 차단된다”를 혼동하게 된다.
OMNICONDUCTOR는 지원되지 않는 native 강제를 가짜 polyfill로 포장하지 않는다.

## 1. 불필요한 Read 예방

큰 파일 전체 Read는 한 번의 호출 비용으로 끝나지 않는다. 결과가 대화 기록에
들어가 이후 turn의 입력 컨텍스트와 attention budget까지 계속 차지한다.

공통 규칙은 다음과 같다.

- symbol이나 section 탐색은 Read보다 `rg`/Grep을 먼저 사용한다.
- Grep의 `-A`/`-B` 문맥으로 충분하면 파일을 다시 열지 않는다.
- 200줄을 넘는 파일은 `offset`/`limit` 범위 읽기를 기본으로 한다.
- 동일한 rules/spec 전체를 반복해서 읽지 않는다.
- 하위 agent에는 파일 내용을 복사하지 않고 정확한 경로와 읽을 범위를 전달한다.

### Claude의 기계적 강제

Claude full/strict 설치는 `pretool-large-file-read-guard.sh`를 등록한다.

- 기본 임계값: 500줄
- 500줄 이상 파일을 `offset`/`limit` 없이 Read하면 호출 거부
- Grep 또는 `limit: 100` 범위 읽기를 안내
- 드문 예외는 `CONDUCTOR_ALLOW_LARGE_READ=1`로 명시적으로 우회

200줄은 전 도구 공통 운영 기준이고, 500줄은 Claude hook의 기본 차단 기준이다.
다른 여섯 도구는 현재 같은 규칙을 받지만 동일한 native Read 차단을 주장하지
않는다.

## 2. Tool-output store-time cap

테스트 로그, 대형 Read, MCP 응답, WebFetch 결과가 수만 토큰이면 다음 turn부터
매번 거대한 history tail을 동반한다. Output cap은 **모델의 최종 답변 길이**가
아니라 **개별 tool result가 대화 기록에 저장되는 크기**를 제한한다.

기본 예산은 8,000 tokens이다.

| 도구 | 설치되는 메커니즘 | 범위와 한계 |
|---|---|---|
| **Claude Code** | `PostToolUse`에서 `updatedToolOutput` 반환 | oversized string leaf를 앞 70% + marker + 뒤 30%로 교체. 약 4 chars/token 휴리스틱. Claude Code 2.1.121 이상 계약. |
| **Codex** | `.codex/config.toml`의 `tool_output_token_limit = 8000` | 모든 tool/function output에 적용되는 native tokenizer budget. 환경변수 override가 아니라 저장된 config 값. |
| **Gemini CLI** | `BeforeTool`에서 `run_shell_command` 재작성 | shell stdout+stderr를 합쳐 head-only 제한. shell 이외 tool에는 적용되지 않음. |
| **Cursor** | 없음 | 검증된 store-time output rewrite surface가 없어 N/A. |
| **GitHub Copilot** | 없음 | lifecycle hook은 있지만 결과 저장 전 교체 계약이 없어 N/A. |
| **Windsurf** | 없음 | 검증된 hook이 전체 response 이후에 실행되어 개별 tool result를 미리 줄일 수 없음. |
| **OpenCode stable v1** | 없음 | v1 plugin은 tool 호출 전 차단은 가능하지만 저장될 tool result를 교체하는 검증 계약은 없음. |

Claude/Gemini hook은 `CONDUCTOR_OUTPUT_CAP_TOKENS`로 기본값을 조정할 수 있고
`CONDUCTOR_SKIP_OUTPUT_CAP=1`로 비활성화할 수 있다. Codex는 generated config의
값을 직접 변경해야 하며 이 환경변수를 사용하지 않는다.

```bash
# full/strict checkout에서 실제 cap 파일/config가 존재하는지 확인
npx omniconductor doctor .
```

`doctor`의 D5는 manifest에 적혀 있다는 사실이 아니라 현재 branch에서 실제
hook/config가 활성화됐는지를 확인한다.

## 3. 항상 로드되는 컨텍스트 최소화

Token Economy는 실행 중 자르는 기능만이 아니라 설치 구조에서 시작한다.

- **5개 universal rule**만 공통 바닥으로 유지한다.
- **17개 recipe**는 프로젝트가 선택한 항목만 설치한다.
- `plan-change`, `verify-change`, `review-change` 등 **portable skill은 on demand**로
  읽는다.
- `propose-skill`, `coordinate-work`는 관련 recipe를 설치했을 때만 활성화한다.
- `minimal`은 agents/hooks/Reflector runtime을 제외한다.
- `recipes-only`는 선택한 recipe만 설치한다.
- Codex는 bounded `AGENTS.md` kernel과 상세 `.codex/conductor/` reference를
  분리한다.
- Cursor의 `.mdc` glob, Copilot의 `applyTo:`처럼 검증된 scoping이 있으면 관련
  파일을 만질 때만 규칙을 적용한다.
- OpenCode는 `opencode.json`의 `instructions` globs로 `.opencode/rules`와 선택
  recipe를 등록하며 root `AGENTS.md`를 중복 소유하지 않는다.
- Gemini처럼 per-pattern lazy loading이 없는 도구는 그 한계를 matrix에 공개한다.

Skill·MCP를 수십 개 eager-load하면 실제로 사용하지 않아도 이름·설명·JSON
Schema가 매 요청의 입력 prefix를 차지할 수 있다. 따라서 progressive disclosure와
deferred tool loading을 우선한다.

## 4. Prompt caching

반복되는 지침은 다음처럼 안정된 순서로 둔다.

```text
1. Universal rules        ┐
2. Project instructions   ├─ stable/cacheable prefix
3. Selected recipes       │
4. Memory index           ┘
---------------- cache boundary ----------------
5. CURRENT_WORK / recent history / tool results / new user message
```

현재 KPI SLA는 steady-state cache reuse **95% 이상**이다. 캐시는 컨텍스트 자체를
삭제하지 않지만 반복 prefix의 처리 비용과 지연을 크게 줄인다.

주의할 점:

- OMNICONDUCTOR installer가 Anthropic SDK의 `cache_control`을 자동 설정하지는 않는다.
- 이 기능은 Claude/Anthropic API용 구성 가이드다.
- rules 순서가 turn마다 바뀌거나 project instructions를 자주 수정하면 cache key가
  깨질 수 있다.

자세한 설정은 [PROMPT-CACHING-GUIDE.md](./PROMPT-CACHING-GUIDE.md)를 참고한다.

## 5. Context editing과 instruction fidelity

긴 세션을 줄일 때 삭제 우선순위는 다음과 같다.

1. 이미 사용한 오래된 tool result
2. 반복 검색 결과와 중복 Read
3. 필요 없어진 thinking/tool input
4. 사용자 지시와 acceptance criteria는 마지막까지 보존

Claude API의 `clear_tool_uses`는 stale tool result만 제거할 수 있어 전체 대화를
요약하는 `/compact`보다 instruction fidelity가 높다. `/compact`가 필요하면 원래
요구사항·완료 조건·남은 TODO를 verbatim으로 보존하도록 명시하고, unrelated task로
넘어갈 때는 `/clear`로 새로 시작한다.

이 역시 installer가 API 코드를 자동 생성하는 기능은 아니다. 전 도구에는 보존
원칙이 rule text로 배포되고, lossless native context editing은 Claude API 범위로
한정한다. 자세한 내용은 [CONTEXT-EDITING-GUIDE.md](./CONTEXT-EDITING-GUIDE.md)를
참고한다.

## 6. Tier routing과 bounded dispatch

Tier routing은 단순히 “싼 모델을 쓴다”는 정책이 아니다.

- Tier 1: 개념적·복잡한 작업
- Tier 2: 일반 구현
- Tier 3: 단순 조회·작은 수정

프로젝트가 승인한 도구별 모델과 reasoning effort를
`.conductor/model-routing.json`에 저장하고 재설치에서도 유지한다. 쉬운 작업은
helper·scribe·utility 역할로 격리해 고비용 main context의 성장을 줄일 수 있다.

Dispatch brief는 약 2,000 tokens 이내로 제한한다. 파일 본문 대신 경로, 범위,
완료 조건만 전달한다. 역할이 역할을 다시 호출하는 nested dispatch는 각 계층에
context를 중복시키므로 flat-with-leader 구조를 사용한다.

모델 라우팅은 비용과 context isolation을 개선하지만, 같은 작업이 반드시 더 적은
총 토큰으로 끝난다고 보장하지는 않는다. 품질 위험이 높으면 비용보다 fidelity를
우선해 Tier를 올린다.

## 7. 로컬 측정과 진단

### 빠른 세션 측정

```bash
bash tools/measure-tokens.sh --latest
bash tools/measure-tokens.sh --latest --export-csv=/tmp/after.csv
```

Claude Code JSONL에서 다음을 읽는다.

- input/output tokens
- cache hit/reuse
- tool-call 수
- CSV baseline 대비 변화

### 여러 세션 감사

```bash
node tools/audit-token-economy.js \
  --sessions="$HOME/.claude/projects/<encoded-project-directory>" \
  --thresholds=4000,6000,8000,12000
```

감사 결과에는 다음이 포함된다.

- threshold별 초과 tool result 수
- 예상 제거 가능 tokens
- 실제 CONDUCTOR truncation marker 수
- prompt-cache reuse
- branch와 sub-agent role 분포
- cap이 설치되지 않았거나 저비용 역할이 전혀 사용되지 않은 징후

추정치는 `ceil(serialized characters / 4)` 휴리스틱이므로 청구 금액과 동일한
수치가 아니다. threshold 선택과 controlled comparison을 위한 방향성 증거다.

모든 측정은 로컬 파일만 읽으며 telemetry를 전송하지 않는다.

## 8. 권장 확인 순서

```bash
# 1. 설치 전에 변경 미리보기
npx omniconductor init --target=all . --dry-run --no-prompt --accept-model-defaults

# 2. 실제 설치 후 native cap/hook/config 확인
npx omniconductor doctor .

# 3. 한 세션 baseline 저장
npx omniconductor init --target=claude . --measure-baseline

# 4. 일주일 또는 대표 작업 묶음 이후 재측정
bash tools/measure-tokens.sh --latest --export-csv=/tmp/after.csv

# 5. 차이가 나쁘면 안티패턴 진단
npx omniconductor init --target=claude . --check-anti-patterns --dry-run
```

진단 카탈로그의 한글 요약은
[`core/anti-patterns/README.md`](../core/anti-patterns/README.md)에 있다.

## 9. 자주 생기는 오해

- **“8,000-token cap이 모델 답변을 자른다.”** 아니다. 개별 tool result의
  store-time 크기를 제한한다.
- **“일곱 도구 모두 같은 hook으로 강제된다.”** 아니다. 실제 cap은 Claude,
  Codex, Gemini shell에만 존재한다.
- **“Prompt caching이 컨텍스트 토큰을 삭제한다.”** 아니다. 반복 prefix의 처리
  비용과 latency를 줄인다.
- **“Context editing이 자동으로 설치된다.”** 아니다. Claude API 사용자를 위한
  검증된 구성 가이드다.
- **“Tier 3이면 무조건 품질을 희생한다.”** 아니다. Tier 난이도 정의는 불변이고,
  프로젝트가 승인한 모델/effort 매핑을 사용한다. 애매하면 한 Tier 올린다.
- **“측정값이 곧 npm/provider 청구서다.”** 아니다. 로컬 JSONL과 휴리스틱 기반의
  비교·진단 지표다.

## 관련 문서

- 공통 규칙: [`core/universal-rules/meta-discipline.md`](../core/universal-rules/meta-discipline.md)
- 안티패턴 카탈로그: [`core/anti-patterns/README.md`](../core/anti-patterns/README.md)
- 도구별 기능: [`COMPATIBILITY-MATRIX.md`](./COMPATIBILITY-MATRIX.md)
- 모델 라우팅: [`MODEL-ROUTING.md`](./MODEL-ROUTING.md)
- Prompt caching: [`PROMPT-CACHING-GUIDE.md`](./PROMPT-CACHING-GUIDE.md)
- Context editing: [`CONTEXT-EDITING-GUIDE.md`](./CONTEXT-EDITING-GUIDE.md)
- 설계 근거: `DESIGN-DECISIONS.md` ADR-035, ADR-036, ADR-051, ADR-058
