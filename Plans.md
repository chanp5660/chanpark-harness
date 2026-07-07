# chanpark-harness 리뷰 수정 Plans.md

Created: 2026-07-03
Source: /code-review max (2026-07-02) — 상위 15건 CONFIRMED + 하위 14건
Validation: team_validation_mode=subagent (architect + critic, 2026-07-03)

> ⚠️ **운영 게이트**: Phase 3 완료 전까지 이 저장소에서 `bin/harness sync` 실행 금지.
> 구 바이너리의 sync는 `.claude-plugin/hooks.json` 중복본을 부활시킨다 (commit 980b0288에서 제거된 파일).
> harness.toml 정체성 정렬(1.2) 후에도 이 제약은 유지된다.

---

## Phase 1: 긴급 완화 + 검증 기반 (Required)

| Task | Description | DoD | Depends | Status |
|------|-------------|-----|---------|--------|
| 1.1 | 검증 기반 구축: `scripts/ci/check-baseline.sh` (bash -n + shellcheck(있으면) + jq JSON 검증) + 테스트 픽스처 (혼합 마커 Plans.md 샘플, mock 플러그인 루트) + 회귀 가드 스켈레톤 (정체성 일치 harness.toml==plugin.json, /usr/bin/grep 검출, sync의 hooks.json 생성 금지, agents/skills/templates CJK) `[tdd:skip:test-infra-itself]` | 가드 스크립트가 현 HEAD에서 기존 결함(정체성 불일치·/usr/bin/grep)을 검출하며 exit 1 | - | cc:done [543b21fb] |
| 1.2 | 정체성 정렬 일괄: harness.toml `[project]` name/version/homepage/repository/author → chanpark-harness/1.2.2/ChanPark **및** scripts/sync-plugin-cache.sh의 grep(`claude-code-harness`)·PLUGIN_NAME·MARKETPLACE_NAME·VERSION 소스(→plugin.json 버전) 수정 `[tdd:skip:no-test-framework-detected]` | 샌드박스 사본에서 `harness sync` 후 plugin.json 정체성 유지 + `hook setup-init` exit 0·캐시 동기화 수행 (실저장소 sync는 금지 유지) | 1.1 | cc:done [646d43f8] |
| 1.3 | hooks.json(65)·monitors.json(1)의 `/usr/bin/grep` → PATH `grep` 치환 `[tdd:skip:no-test-framework-detected]` | `grep -c '/usr/bin/grep' hooks/hooks.json monitors/monitors.json` = 0 + 샌드박스 훅 커맨드 시뮬 정상 실행 | 1.1 | cc:done [b1159579] |
| 1.4 | release-preflight.sh PROJECT_ROOT 기본값을 `$(pwd)`로 (SKILL.md:454 문서와 일치; 현재는 플러그인 체크아웃 자체를 검사) `[tdd:skip:no-test-framework-detected]` | 외부 디렉터리에서 인자 없이 실행 시 그 디렉터리를 검사함을 실행으로 확인 | 1.1 | cc:done [2b7f1966] |
| 1.5 | progress-snapshot.sh 파서 수정: 체크리스트 형식(`- [ ] … cc:todo`)·T001형 ID 파싱 + cc:blocked 분류를 카운트/total/alerts에 반영 `[tdd:skip:no-test-framework-detected]` | 픽스처 Plans.md에서 todo/wip/done/blocked 4값 정확 + blocked>0 시 pct<100 및 alerts 비어있지 않음 | 1.1 | cc:done [2fb3396b] |
| 1.6 | hud/statusline.sh 하드닝: per-user 0700 캐시 디렉터리 + 원자적 쓰기(mktemp+mv, statusline-harness.sh의 강화 패턴 이식) + BRANCH/SHA 기본값 + `%b`→`%s` + CHANPARK_HUD_GIT_CACHE 오버라이드 소유권 검증 `[tdd:skip:no-test-framework-detected]` | 리뷰 재현 3종(chmod 000 캐시 / 심링크 클로버 / `\n` 포함 WIP 제목) 전건 통과, statusline 정상 출력 | 1.1 | cc:done [413f1902] |

## Phase 2: 마커 스펙 정합 (Required)

| Task | Description | DoD | Depends | Status |
|------|-------------|-----|---------|--------|
| 2.1 | 마커 스펙 확정 + CLAUDE.md 정정 (Spec delta 적용): canonical 소문자 유지 선언, 바이너리 실측 행동 정밀 기술(**카운터 경로는 case-sensitive·cc:done 미집계** — 일부 개별 매처만 `(?i)`), scripts/ "binary fallbacks" 서술을 실제 역할로 정정, sync 금지 게이트 문서화 `[tdd:skip:docs-only]` | CLAUDE.md에 실측과 불일치하는 서술 0건 (리뷰 증거 대조) | - | cc:done [db590669] |
| 2.2 | 스킬·템플릿 마커 표기 통일: `cc:Done` 전면 제거, harness-work/plan/loop/principles/progress + templates/rules·AGENTS.md.template를 Plans.md.template(소문자 canonical)과 정합 + plan-brief-context schema enum(소문자화·cc:blocked 추가)·plan-brief-compile done-rate(cc:完了→영어) 수정 `[tdd:skip:docs-only]` | 마커 lint(1.1 가드)에 `cc:Done` 0건 + 표기 규약 단일 grep 검사 통과 | 2.1 | cc:done [cfc03692] |

## Phase 3: 바이너리 재빌드 — 결정 게이트 (Required, 착수 전 사용자 승인)

| Task | Description | DoD | Depends | Status |
|------|-------------|-----|---------|--------|
| 3.1 | upstream 캐치업 조사 + 패치 세트: PROVENANCE.md 절차로 Go 소스 확보, 발산도 평가(대규모 발산·cgo 의존 추가 시 **폴백**: bash 래퍼 후처리 전략을 보고하고 재결정). 패치 범위: 카운터 `(?i)` + cc:done + cc:blocked 집계, 일본어 사용자 문자열 영어화(pm:requested/pm:approved 범례), ci-cd-fixer 스티어링 제거, sync의 `.claude-plugin/hooks.json` 중복 생성 제거, setup-codex/opencode 참조 정리 `[tdd:skip:upstream-source]` | 패치 diff 작성 완료 + 발산도 리포트 승인 | 2.1 | cc:TODO |
| 3.2 | 4플랫폼 재빌드(CGO_ENABLED=0) + bin/ 커밋(0755, .gitattributes) — Optional: linux-arm64 신규 추가(~16MB 증가, 별도 승인) `[tdd:skip:build-artifact]` | 각 바이너리 `grep -a` CJK 0건 + 샌드박스에서 소문자 Plans.md 카운트 정상 | 3.1 | cc:TODO |
| 3.3 | 재빌드 검증 + sync 금지 해제: 재현 스위트(1.1) 전건 통과 — session-init 범례 영어, 소문자/cc:done/cc:blocked 카운트, sync 정체성 유지·중복 파일 미생성 `[tdd:skip:verification-task]` | 회귀 가드 + 재현 스위트 exit 0, Plans.md 상단 sync 금지 문구 제거 | 3.2 | cc:TODO |

## Phase 4: 죽은 코드·참조 정리 (Recommended)

| Task | Description | DoD | Depends | Status |
|------|-------------|-----|---------|--------|
| 4.1 | 삭제 후보 분석 리포트: 죽은 스크립트(~81건, 섀도잉 위험군 우선) 참조 그래프(hooks/monitors/binary strings/skills/templates/스크립트 상호참조) + 도달불가 스킬 9종 처분안(삭제/references 이동/플래그 수정) 작성 — **실행 아님, 결정 자료** `[tdd:skip:analysis-only]` | 후보별 참조 0건 근거 명시된 리포트 + 스킬별 처분안 제시 | - | cc:done [3cc9cec5] |
| 4.2 | [결정 게이트] 사용자 승인 목록대로 삭제/이동 실행 + CLAUDE.md 레이아웃 표 갱신. 신규 바이너리 문자열 재확인 필수(새 바이너리가 참조하는 스크립트 보존) `[tdd:skip:no-test-framework-detected]` | 삭제 후 doctor/validate + 훅 스모크 + 회귀 가드 통과 | 4.1, 3.3 | cc:done [2a06adaf] |
| 4.3 | 죽은 참조 수정 (런타임 영향 우선): skills/ci ci-cd-fixer→실존 경로, scripts/harness-memd→`harness mem`, /harness-init·/harness-update→/harness-setup (BEST_PRACTICES·session·session-init·템플릿), harness-work Breezing 다이어그램 task-worker/code-reviewer→chanpark-harness:worker/reviewer, 9개 정책 문서 인용(인용 제거 또는 스텁 작성), skills-gate 템플릿 ui 지시 수정 `[tdd:skip:docs-only]` | 링크체크(1.1 가드 확장)에서 스킬·에이전트 내 사각 참조 0건 | - | cc:done [54035058] |
| 4.4 | 설정 4중주 해소: .claude-code-harness.config.yaml 허위 "DERIVED" 헤더 사실화(수동 관리 선언 또는 템플릿 정합), codex enable/deny 모순 해소(기본 off), 루트 claude-code-harness.config.{example,schema}.json 삭제 `[tdd:skip:no-test-framework-detected]` | 설정 파일 간 모순 grep 검사 통과 + worker의 config-utils 경로 스모크 정상 | - | cc:done [bfb2009a] |

## Phase 5: 하위 14건 개선 (Recommended/Optional)

| Task | Description | DoD | Depends | Status |
|------|-------------|-----|---------|--------|
| 5.1 | statusline 성능: jq 14회→1회 `@tsv` 통합, rev-parse를 캐시 게이트 내부로, `GIT_OPTIONAL_LOCKS=0` `[tdd:skip:no-test-framework-detected]` | 렌더 실측 <100ms (기존 ~350ms) + 출력 동일성 확인 | 1.6 | cc:done [bd0e59b7] |
| 5.2 | 훅 과다 정리: PostToolUse haiku advisory 훅 제거(PreToolUse와 중복), PostToolUse `*` 매처 축소(Read 제외) `[tdd:skip:config-only]` | Write당 haiku 훅 1회·Read당 커맨드 훅 감소를 hooks.json 구조로 확인 | - | cc:done [d77a5a04] |
| 5.3 | template-registry 정합: html 5종 등록 + $schema 포인터 해소(작성 또는 제거) + check-template-registry를 회귀 가드에 편입 `[tdd:skip:config-only]` | `scripts/ci/check-template-registry.sh` exit 0 | - | cc:done [533cab15] |
| 5.4 | 소형 버그 일괄: session-state.sh 최상위 `local` 제거, hud-onboarding-nudge `/hud off` 후 재알림(옵트아웃 마커) + jq/grep null 판정 통일, `[claude-code-harness]` 브랜딩 stderr 3곳, plan-brief 문장분리(`.` 추가), Stop/PreCompact 프롬프트 마커 표기 정합 `[tdd:skip:no-test-framework-detected]` | 각 항목 재현 시나리오 통과 (session-state 오류경로 전이표 출력 등) | 2.2 | cc:done [306eefd1] |

---

## Marker Legend

| Marker | 의미 |
|--------|------|
| cc:TODO | 미착수 |
| cc:WIP | 진행 중 |
| cc:done | 완료 |
| blocked | 차단 (사유 필수) |
