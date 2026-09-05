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

### 체감 개선을 확인하는 순서

1. `omniconductor doctor <project>`로 활성 프로젝트 지침과 CURRENT_WORK 비대화를
   먼저 확인합니다. 16 KiB 이상의 알려진 프로젝트 지침, 32 KiB 이상의 상태 문서는
   범위를 줄일 후보이지, 자동 삭제 대상으로 취급하지 않습니다.
2. `omniconductor audit instructions <project>`의 managed kernel과 project exposure를
   따로 봅니다. OpenCode/Windsurf가 함께 읽는 루트 AGENTS.md와 사용자 추가 지침은
   kernel 숫자만으로 설명할 수 없습니다. 전역 지침·도구 목록·히스토리는 미측정입니다.
3. Claude 사용량은 같은 session/message의 스트리밍 행을 합산하지 않고 카운터별
   최댓값으로 정규화합니다. ID가 없어 호출 수를 검증할 수 없으면 개인 절감 보고서의
   자동 요청 수 계산을 거부합니다. 이전보다 작아진 수치는 측정 오류 수정일 수 있습니다.
4. OpenCode는 다음 명령으로 **기존 DB**를 읽습니다. 새 세션, 로그인, 유료 호출이
   필요하지 않습니다. Python 3/sqlite3가 필요하고, 원본 DB와 WAL의 안정된 복사본만
   SQLite로 엽니다. 원문 대화는 결과에 포함하지 않습니다.

```powershell
omniconductor audit opencode "C:\Projects\app" --database="C:\path\opencode.db" --since=2026-09-01 --until=2026-09-08 --json
```

명시한 경로의 DB 스키마를 fingerprint로 확인합니다. 관측된
`message(time_created,data)` / `session.directory` / 숫자형 `data.cost` 계약을
사용하며, 다른 스키마는 추정 SQL로 강행하지 않습니다. 메인·자식 세션, 역할·공급자·모델,
캐시 포함 입력 100K 이상 비중, 같은 조건의 작업별 중앙값을 제공합니다. 세션의
parent_id가 없거나 부모가 다른 프로젝트면 작업 귀속을 검증하지 못했다고 표시합니다.
DB 비용은 청구 크레딧이 아닙니다. 비용 필드가 없는 호출을 무료로 단정하지 않습니다.
작업별 집계 단위는 루트 세션의 대리값이며, 실제 업무 완료나 품질 통과를 판정하지 않습니다.
기간 필터가 세션의 일부만 포함할 수 있으므로 전후 비교에서는 같은 선정 기준을 유지해야 합니다.
입력은 캐시와 별도, 출력은 reasoning과 별도로 집계하며 reasoning의 관측 범위도 표시합니다.
이 분리는 [OpenCode 사용량 정규화 코드](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/session.ts)의
관례를 따릅니다. 스키마가 같더라도 공급자 원본 카운터의 정확성까지 보증하지는 않습니다.
DB+WAL 256 MiB, 전체 50,000개 메시지, 파싱할 JSON 64 MiB, 검사 실행 30초가 상한이며,
초과·변경 중인 DB·복구 journal은 실패로 표시합니다. 더 작은 내보내기 DB가 필요할 수 있습니다.

OpenCode 안의 GitHub Copilot 연결은 `--target=opencode` 대상입니다. 저장된 모델
매핑의 공급자가 실제 사용하는 연결과 맞는지도 확인하세요. `openai/...` 기본값을
Copilot 연결로 자동 해석하지 않습니다. 사용권·모델 가용성은 설치 성공만으로 보장하지 않습니다.

5. 셀프 인프루브 예약 실행은 `.conductor/reflect/run-weekly.sh`를 사용합니다.
   같은 근거·모델·brief의 재실행은 모델 호출을 건너뜁니다. 최근 14일/12세션 메타데이터,
   git/state fallback, 32 KiB 근거 상한, 기본 120초/출력 1 MiB 제한이 있습니다.
   저장된 Tier 1 매핑을 쓰며, 제안은 여전히 사람 승인 전 적용되지 않습니다.
   수동 스킬 호출에는 runner의 반복 방지·시간 제한이 자동 적용되지 않습니다.

이 한도는 공급자 전체 입력·출력 토큰이나 청구 금액의 강제 상한이 아닙니다.
전체 규칙을 매 요청에 넣는 가상 기준 대비 작은 초기 kernel의 구조적 차이를
실제 전체 세션 절감률로 표시하지 않습니다. 품질을 유지한 비용·시간 개선은 같은 작업,
공급자·모델, 완료 기준을 맞춘 전후 표본이 있어야 주장할 수 있습니다.

Token Economy 기능은 모두 같은 강도로 동작하지 않는다.

| 분류 | 의미 | 대표 기능 |
|---|---|---|
| **자동 강제** | 설치된 native config 또는 hook이 실제 호출을 제한 | Claude large-read guard, Claude/Codex/Gemini output cap |
| **구조적 절약** | 설치물이 상시 컨텍스트를 작게 유지하도록 구성 | 7개 도구 bounded kernel, byte-identical on-demand rule/recipe references, on-demand skills |
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

- 7개 도구 모두 **약 1,700~2,100-token bounded kernel**만 항상 활성화한다
  (기본 recipe 2개를 포함한 2026-08-20 macOS fixture, `bytes/4` 휴리스틱).
- 5개 universal rule 원문은 adapter별 `conductor/rules/` 아래에 **바이트 그대로**
  보존하고, 커널의 activity table이 요구할 때 정확한 파일만 읽는다.
- **17개 recipe**는 프로젝트가 선택한 항목만 설치한다.
- `plan-change`, `verify-change`, `review-change` 등 **portable skill은 on demand**로
  읽는다.
- `propose-skill`, `coordinate-work`는 관련 recipe를 설치했을 때만 활성화한다.
- `minimal`은 agents/hooks/Reflector runtime을 제외한다.
- `recipes-only`는 선택한 recipe만 설치한다.
- Claude/Cursor/Copilot은 검증된 `paths`/`globs`/`applyTo`에 작은 recipe
  pointer만 두고 전체 recipe는 별도 reference로 유지한다.
- Gemini/Codex는 bounded root kernel에서 명시적 Read 경로로 라우팅한다.
- Windsurf/OpenCode는 검증된 상시 surface에 작은 kernel/pointer만 등록하고
  전체 원문은 등록하지 않는다.
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
1. Bounded runtime kernel ┐
2. Project instructions  ├─ stable/cacheable prefix
3. Recipe routing index  │
4. Memory index          ┘
---------------- cache boundary ----------------
5. Matching full reference / CURRENT_WORK / history / tool results / new message
```

현재 KPI는 **cache-read token share 95% 이상**이다. 공식은 모든 reporter에서
`cache_read / (cache_read + cache_write + uncached_input)`로 동일하다. 캐시는 컨텍스트 자체를
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

### OpenCode + GitHub Copilot의 AI credits 경계

OpenCode의 공식 provider 연결로 GitHub Copilot 구독을 사용할 수 있지만, 실제
모델 호출의 과금 단위와 가격은 GitHub가 소유한다. 현재 GitHub usage-based billing은
input, output, cache read/write token과 선택 모델을 AI credits로 환산하며, third-party
coding agent 사용도 과금 범위에 포함한다. 따라서 “문서 4개 수정”이라는 파일 수만으로
200~300 credits가 적정한지 판정할 수 없다. 사용량 보고서의 모델별 token breakdown과
실제 호출 수가 있어야 한다.

GitHub의 비용 절감 권고 중 OpenCode에서도 그대로 적용 가능한 것은 다음과 같다.

- 작업 전 모델을 정하고 중간에 불필요하게 바꾸지 않아 cache 재구축을 피한다.
- 조사·계획·구현을 분리하되, phase가 바뀌면 새 세션을 사용해 이전 tool result를
  다음 phase마다 다시 보내지 않는다.
- 먼저 사용자 지정 파일 범위를 정하고, 문서만으로 해결되지 않는 주장에 한해서만
  source를 연다.
- 사용하지 않는 MCP/tool server를 끄고, 큰 출력은 파일에 저장한 뒤 필요한 범위만
  읽는다.
- docs-only 작업에는 code-reviewer와 전체 테스트를 자동으로 붙이지 않는다. 설계를
  바꾸는 plan에만 reviewer를 쓰고, 나머지는 대상 문서 contradiction check로 끝낸다.

GitHub Copilot CLI의 `/context`, `/compact`, `/limits set max-ai-credits ...` 및
`--max-ai-credits=...`는 **Copilot CLI 기능**이다. OpenCode가 Copilot provider로
인증됐다는 이유만으로 이 session-limit 계약이 OpenCode에 전달되지는 않는다.
CONDUCTOR도 OpenCode에 존재하지 않는 credit cap을 설치했다고 주장하지 않는다.
OpenCode 세션 비용은 GitHub의 AI usage/billing report에서 모델별 input/output/cache
token을 확인하고, OpenCode에서는 작업 범위·모델·도구 수를 미리 제한하는 방식으로
관리한다.

CONDUCTOR의 현재 OpenCode 권장 기본값은 direct `openai/...` provider/model이다.
OpenCode에서 GitHub Copilot provider를 쓰는 사용자는
`--accept-model-defaults`로 이 값을 확정하지 않는다. 먼저 OpenCode `/models`에서
계정에 실제 표시되는 Copilot-backed `provider/model` 세 값을 확인한 뒤 다음처럼
저장한다.

```powershell
npx omniconductor@latest models configure --target=opencode "C:\path\to\project"
npx omniconductor@latest init --target=opencode "C:\path\to\project" --no-prompt
npx omniconductor@latest doctor "C:\path\to\project"
```

OpenCode가 GitHub Copilot 모델을 호출하더라도 읽는 project contract는 OpenCode
형식이므로 `--target=opencode`가 맞다. `--target=copilot`은 같은 프로젝트를 VS Code
등의 Copilot Chat client에서도 열어 `.github/*` 지침을 소비할 때만 추가한다.

로컬 OpenCode DB를 보조 증거로 분석할 때는 버전별 schema를 먼저 확인하고 SQL을
고정해야 한다. Windows adopter의 OpenCode `1.18.27` 관측에서는 `message`가
`time_created`와 `data`를 사용하고, 작업 경로는 `session.directory`, 비용은 message
JSON의 숫자 `$.cost`에 있었다. `created_at`, `role`, `tokens`, `session.cwd`,
`$.cost.total` 같은 추정 필드를 그대로 사용하면 안 된다. 이 관측을 다른 버전의
영구 계약으로 승격하지 말고, `PRAGMA table_info(...)`와 대표 JSON shape를 읽은 뒤
버전·schema fingerprint와 함께 query를 선택한다.

비교 보고서의 최소 증거는 총액 하나가 아니라 다음을 포함한다.

- 100K 이상 대형 입력 호출 비율
- main agent와 subagent 분리 및 역할별 실제 provider/model
- terminal task/session 귀속
- 포함·제외 기준이 고정된 cohort median
- 자동 smoke 한 호출의 고유 식별자와 사용자가 판정할 호출의 명확한 구분

Smoke 순서는 `사용자 호출 → 자동 DB 증거 추출 → 증거 제시 → 사용자 PASS`다.
사용자 호출 전에 그 호출의 PASS를 요구하는 순환 gate는 만들지 않는다. 자동 smoke와
사용자 smoke를 모두 실행한다면 어느 한 호출만 최종 증거인지 사전에 고정한다.

### 빠른 세션 측정

```bash
bash tools/measure-tokens.sh --latest
bash tools/measure-tokens.sh --latest --export-csv=/tmp/after.csv
```

Claude Code JSONL에서 다음을 읽는다.

- input/output tokens
- cache-read token share와 read/write/uncached 원시값
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
- cache-read token share (동일한 3항 분모)
- branch와 sub-agent role 분포
- cap이 설치되지 않았거나 저비용 역할이 전혀 사용되지 않은 징후

추정치는 `ceil(serialized characters / 4)` 휴리스틱이므로 청구 금액과 동일한
수치가 아니다. threshold 선택과 controlled comparison을 위한 방향성 증거다.

모든 측정은 로컬 파일만 읽으며 telemetry를 전송하지 않는다.

### 사용자별 절감 추정

```bash
# 현재 설치의 특정 도구 요청당 eager-context 회피량
npx omniconductor audit instructions . --target=claude

# 대표 기간에 요청 1000회가 있었다면 누적 context-token 추정도 표시
npx omniconductor audit instructions . --target=claude --requests=1000

# Claude: 개인 로컬 세션에서 실제 output elision과 호출 수 기반 구조 추정을 함께 보고
npx omniconductor audit savings . \
  --target=claude \
  --sessions="<Claude JSONL 파일 또는 디렉터리>" \
  --subject="익명 사용자 ID"

# 그 밖의 도구: 확인한 요청 수로 구조 추정만 보고
npx omniconductor audit savings . --target=codex --requests=1000 --subject="익명 사용자 ID"
```

이 값은 **같은 전체 정책을 매 요청 eager-load한 반사실적 기준**과 현재 bounded
kernel을 비교한 `bytes/4` 컨텍스트 추정치다. 공급자 청구 토큰이나 비용 절감액이
아니다. Claude 세션의 실제 output-cap 절감은 `audit-token-economy.js`가 marker에
기록된 `tokens elided`만 합산해 별도의 관측 하한으로 보여준다.

`audit savings`는 사용자 한 명이 자신의 로컬 기록에서 직접 실행하는 zero-telemetry
보고서다. 세션 원문·프롬프트·도구 결과를 출력하거나 전송하지 않으며, `--subject`는
사용자가 직접 넣는 선택적 표시값이다. 보고서는 다음을 의도적으로 분리한다.

- **관측 하한:** Claude truncation marker에 명시된 실제 `tokens elided` 합계
- **구조 추정:** 해당 어댑터의 bounded kernel과 동일 정책 eager-load 반사실의 차이
- **건강 지표:** cache-read token share — 공급자 캐시이므로 절감량에 귀속하지 않음

서로 증거 강도가 다른 입력·출력 숫자를 합친 `total savings`는 만들지 않는다. Claude
외 도구는 현재 호환되는 개인 세션 로그 파서가 없으므로 `--requests` 기반 구조 추정만
제공한다. `--json`을 붙이면 사용자가 직접 조직 내부 집계에 제출할 수 있지만,
CONDUCTOR 자체는 중앙 수집·사용자 추적을 하지 않는다.

## 8. 권장 확인 순서

```bash
# 1. 설치 전에 변경 미리보기
npx omniconductor init --target=all . --dry-run --no-prompt --accept-model-defaults

# 2. 실제 설치 후 native cap/hook/config 확인
npx omniconductor doctor .

# 2-1. 상시 지침 크기·원문 무결성·사용자별 절감 추정
npx omniconductor audit instructions . --target=claude --requests=1000
npx omniconductor audit savings . --target=claude --sessions="<session-directory>"

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
- **“Copilot CLI의 AI-credit limit가 OpenCode에도 적용된다.”** 아니다. 동일한
  GitHub 계정을 쓰더라도 client 기능 계약은 별개다.
- **“OpenCode에서 Copilot을 쓰므로 `--target=copilot`을 설치한다.”** 아니다.
  client가 OpenCode이면 `--target=opencode`이고, Copilot은 그 뒤의 model provider다.

## 관련 문서

- 공통 규칙: [`core/universal-rules/meta-discipline.md`](../core/universal-rules/meta-discipline.md)
- 안티패턴 카탈로그: [`core/anti-patterns/README.md`](../core/anti-patterns/README.md)
- 도구별 기능: [`COMPATIBILITY-MATRIX.md`](./COMPATIBILITY-MATRIX.md)
- 모델 라우팅: [`MODEL-ROUTING.md`](./MODEL-ROUTING.md)
- Prompt caching: [`PROMPT-CACHING-GUIDE.md`](./PROMPT-CACHING-GUIDE.md)
- Context editing: [`CONTEXT-EDITING-GUIDE.md`](./CONTEXT-EDITING-GUIDE.md)
- 설계 근거: `DESIGN-DECISIONS.md` ADR-035, ADR-036, ADR-051, ADR-058
- GitHub AI usage 최적화: <https://docs.github.com/en/copilot/tutorials/optimize-ai-usage>
- GitHub AI usage 확인: <https://docs.github.com/en/copilot/how-tos/manage-and-track-spending/monitor-ai-usage>
- Copilot CLI session limit: <https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/set-session-limit>
- OpenCode GitHub Copilot 연결: <https://opencode.ai/docs/providers/#github-copilot>
