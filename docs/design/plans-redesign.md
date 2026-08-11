# Plans.md 재설계 — 백로그 팽창 저항 설계

- 상태: **설계 확정, 미구현** (구현은 별도 작업)
- 대상 브랜치: `exp/wip-guard-and-plans`
- 작성일: 2026-08-11
- 설계 목표: Linear의 issue hygiene, Shape Up의 bets-not-backlogs와 **백로그 팽창 저항** 한 축에서
  동등한 수준. "조금 더 깔끔해짐"은 실패로 간주한다.

---

## 0. 요약

죽여야 할 실패 두 가지:

1. **항목이 쌓이기만 한다.** `harness-plan`은 추가하고, 아무것도 은퇴시키지 않는다. 네 마커
   (`cc:todo` / `cc:wip` / `cc:done` / `cc:blocked`) 중 "안 하기로 했다"를 표현할 수 있는 것이 없다.
2. **파일이 안 읽힐 때까지 커진다.** 안 읽으면 안 돌보고, 안 돌보면 더 길어진다 — 강화 루프.

해법은 네 조각이며, **넷이 모두 있어야 작동한다**. 하나라도 빼면 기존 라이벌 시스템 중 하나로
퇴화한다(§5.1 참조).

| # | 조각 | 실패 1 | 실패 2 |
|---|------|--------|--------|
| A | `cc:dropped` — 이름 붙은 종결 상태 | 죽임 | — |
| B | terminal-complete 의미론 (dropped는 done과 동급으로 분모에 남고 진행률에 기여) | 죽임 | — |
| C | 3-파일 물리 분리 (active / backlog / archive) | — | 죽임 |
| D | 활성 파일 하드 캡 + staleness 스윕(제안만) | — | 죽임 |

A만 하면 claude-task-master(큐는 안 늘지만 파일은 무한 증가). C만 하면 OpenSpec(왜 떠났는지 기록 없음).
D만 하면 BMAD(썩는 걸 알려주지만 자를 어휘가 없음).

---

## 1. 측정된 증거

이 절의 모든 수치는 이 저장소에서 **직접 재실행해 확인**했다. 인용된 명령은 그대로 재현 가능하다.

### 1.1 현재 상태

```
$ awk -f scripts/lib/plans-markers.awk Plans.md
0 0 16 0 0 0
$ awk -F'|' '/^\|/{id=$2; gsub(/^ +| +$/,"",id); if(id ~ /^[0-9]+\.[0-9]+$/) n++} END{print n}' Plans.md
20
```

**표준 카운터가 done을 20% 적게 센다.** 20개 태스크 행 전부 done인데 16으로 보고한다.

### 1.2 활성 데이터 무결성 결함 (선행 수리 필수)

```
$ awk -F'|' '/^\|/ {s=$(NF-1); gsub(/^ +| +$/,"",s); id=$2; gsub(/^ +| +$/,"",id);
             if (s ~ /&#58;/ && id ~ /^[0-9]/) printf "row %-5s status=%s\n", id, s}' Plans.md
row 1.5   status=cc&#58;done [2fb3396b]
row 2.2   status=cc&#58;done [cfc03692]
row 3.1   status=cc&#58;done
row 6.1   status=cc&#58;done [ff3ed0eb]

$ sed 's/&#58;/:/g' Plans.md | awk -f scripts/lib/plans-markers.awk
0 0 20 0 0 0
```

원인: 커밋 `598f4a11` (2026-07-18, "chore: audit follow-ups")가 **설명 셀에 인용된** 마커 토큰을
중화하려고 `cc:` → `cc&#58;` 치환을 **행 전체에** 적용했다. 설명 셀이 마커를 인용한 4개 행에서는
같은 치환이 **상태 셀까지** 때렸다. 그래서 정확히 4개다.

이중으로 조용하다:
- `&#58;`는 어떤 마크다운 뷰어에서도 `:`로 렌더된다 → 사람 눈에는 정상 `cc:done`.
- `grep -rn '&#58;' scripts/ tests/` → 히트 0. 어떤 가드도 이 경우를 안 본다.

기존 `plans-prose-marker-inflation.md` 픽스처는 **인플레이션**(prose가 카운트를 부풀림)을 막는다.
이건 그 **정확한 거울상인 디플레이션**이고, 커버리지가 없다.

> **이것은 만료 로직보다 먼저 고쳐야 한다.** 만료는 같은 마커 카운트를 읽는다. done=16을
> 20개 행에 대고 읽으면 이미 끝난 4개 태스크가 미완료 유령으로 보이고, 스윕이 바로 그 행들을
> 잔소리하거나 만료시킨다.

수리 위치는 **이스케이프 단계**지 카운터가 아니다. `plans-markers.awk`가 `&#58;`를 디코드하게
만들면 마커 레전드 이스케이프(의도적으로 카운트에서 빼는 것)가 무력화된다.

### 1.3 이력 텔레메트리

```
$ git log HEAD --date=short --pretty='%h|%ad|%s' -- Plans.md
598f4a11|2026-07-18|chore: audit follow-ups ...
aca4cdeb|2026-07-08|chore(plans): mark task 6.1 done
54c43ec5|2026-07-07|chore(plans): mark Phase 3 done — all 20 tasks complete
95b7ff5e|2026-07-07|docs: lift sync gate ... (task 3.3)
529e2830|2026-07-07|chore(plans): mark task 4.2 done
75737306|2026-07-03|chore: update Plans.md ledger (14 tasks done)
27ea9578|2026-07-03|plan: add review-fix Plans.md (20 tasks, 5 phases)
$ wc -l Plans.md   # 71
$ find . -path ./.git -prune -o -name 'Plans-*.md' -print   # (없음)
$ ls .claude/memory/   # session-log.md  — 아카이브 0개
```

| 지표 | 측정값 |
|------|--------|
| Plans.md 커밋 수 (HEAD 계보) | 7 |
| 기간 | 2026-07-03 ~ 2026-07-18 (15일) |
| 존재한 적 있는 태스크 행 | 20 (1.1–1.6, 2.1–2.2, 3.1–3.3, 4.1–4.4, 5.1–5.4, 6.1) |
| `cc:done`에 도달한 행 | 20 |
| **포기율** | **0 / 20 = 0.0000** |
| 삭제된 행 | 0 (7개 스냅샷 전체 집합 차분으로 검증) |
| 아카이브 파일 | 0 |
| 최대 라인 수 | 71 |
| 중복 쌍 (Jaccard ≥ 0.20, `[tdd:*]` 보일러플레이트 제거 후) | 0 / 190 |
| 100% done 도달 | 2026-07-08 |
| 마지막 편집 | 2026-07-18 |
| **오늘(2026-08-11) 기준: 완료된 원장이 미아카이브 상태로 방치** | **33일** |

**수명 분포 (n=20):** min 0s, median 6791s(1h53m), mean 75595s(0.87d), **max 356791s = 4d 03h 06m 31s**.

주의 두 가지:
- 20개 중 15개가 **동일한** 6791초를 보고한다. 한 커밋이 전부 todo→done으로 뒤집었기 때문이다.
  즉 커밋 입도가 측정 바닥이고, median은 실제 작업 시간이 아니라 배치 커밋의 산물이다.
- 느린 4개 행(3.1, 3.2, 3.3, 4.2 — 전부 약 4일)만이 진짜 경과 체류다. 그리고 **넷 다 작업량이
  아니라 사람 승인 게이트에 걸려 있었다.**

### 1.4 어휘 변경의 폭발 반경 (직접 측정)

```
$ printf '| ID | Task | Status |\n|---|---|---|\n| 1.1 | a | cc:todo |\n| 1.2 | b | cc:wip |\n| 1.3 | c | cc:done |\n| 1.4 | d | cc:cancelled |\n| 1.5 | e | cc:blocked |\n' > A.md
$ awk -f scripts/lib/plans-markers.awk A.md
1 1 1 1 0 0            # 5행인데 4만 카운트 — cc:cancelled 행은 모든 버킷에서 증발
```

미지 마커는 if/else-if 체인에 else가 없어서 **어느 버킷도 증가시키지 않고 분모에서도 사라진다.**
버킷이 아니라 **분모가 손상된다.**

```
$ printf '... | 2.1 | a | cc:wip-paused |\n' > B.md
$ awk -f scripts/lib/plans-markers.awk B.md
0 1 0 0 0 0            # 접두 흡수: cc:wip-paused가 wip로 계산됨
$ printf '... | 3.1 | a | cc:done-reverted |\n' > C.md
$ awk -f scripts/lib/plans-markers.awk C.md
0 0 1 0 0 0            # 동일
```

```
$ printf '{"session_id":"y"}' | CLAUDE_PROJECT_DIR=... bash scripts/hook-handlers/wip-guard.sh stop
{"decision":"block","reason":"WIP tasks remain: 2.1. ..."}        # ← Plans.md에 cc:wip-paused 하나
$ # 같은 파일을 cc:cancelled로 바꾸면
[chanpark-harness] wip-guard: ... 0 WIP tasks; allowing
```

**측정된 결론 — 이게 마커 이름을 결정한다:**
- 기존 마커를 접두사로 갖는 새 마커(`cc:wip-*`, `cc:done-*`)는 부모 버킷에 흡수되고,
  `cc:wip-*`는 **추가로 wip-guard의 Stop을 막아 세션을 가둔다.**
- 어떤 기존 마커와도 문자열이 겹치지 않는 새 마커는 wip-guard에서 **fail-open**한다(안전).

### 1.5 출력 ABI가 하중을 받고 있다

`plans-markers.awk`는 고정 6정수를 낸다. 소비자가 **위치로** 읽는다:

- `hud/statusline.sh:141` — `read -r TODO WIP DONE _ _ _`
- `scripts/hook-handlers/plans-watcher.sh:88` — `read -r CC_TODO CC_WIP CC_DONE CC_BLOCKED PM_PENDING PM_CONFIRMED`
- `scripts/ci/check-regression-guard.sh:300,308` — 리터럴 `"6 0 9 0 0 0"`, `"2 2 2 1 0 0"`
- `scripts/ci/check-regression-guard.sh:377` — 리터럴 `"6 0 9 0"` (progress-snapshot)

7번째 열을 그냥 덧붙이면 HUD는 살아남지만(잉여 필드가 마지막 `_`로 들어감) **plans-watcher는
`PM_CONFIRMED`에 `"0 0"`이 들어가 `plans-state.json`이 깨진 JSON이 된다.** 즉 상태 추가는
additive가 아니라 **breaking ABI 변경**이다.

### 1.6 어휘가 최소 9곳에 흩어져 있고 이미 서로 어긋나 있다

| 위치 | 상태 |
|------|------|
| `scripts/lib/plans-markers.awk` | 표준 (4 + pm 2) |
| `hud/statusline.sh:150-159` | WIP 타이틀용 인라인 awk 사본 |
| `hud/statusline.sh:143-144` | grep 폴백 — **v1.3.6 이전의 unanchored 규칙, CI 커버리지 0** |
| `scripts/hook-handlers/wip-guard.sh` × 2 dialect | 자체 인라인 awk, unanchored |
| `scripts/progress-snapshot.sh:192-201` | Python `startswith` 체인 |
| `skills/harness-plan/SKILL.md:362-366` | **`cc:blocked` 누락**, `blocked`로 잘못 표기 |
| `templates/Plans.md.template:53-59` | 별도 레전드 (`cc:TODO`/`cc:WIP` 별칭) |
| `skills/harness-plan-brief/schemas/*.json` | 닫힌 enum — 유일하게 **loud fail** |
| 벤더 바이너리 | 컴파일된 6행 레전드, 재빌드 불가 |

이미 어긋난 이름들: `skills/maintenance/references/cleanup.md`는 `pm:pending`/`pm:confirmed`를,
`skills/harness-sync/SKILL.md:215`는 `pm:reviewed`를 가드/grep한다. **셋 다 이 시스템이 한 번도
쓰지 않는 이름이다.** 이게 v1.3.6을 낳은 드리프트 기하학이고, 상태를 추가하기 전에 봉합해야 한다.

### 1.7 벤더 바이너리는 지금 이 순간 틀려 있다

```
$ awk -f scripts/lib/plans-markers.awk Plans.md      →  0 0 16 0 0 0   (blocked=0)
$ ./bin/harness hook session-init                     →  ... blocked 1 ...
```

바이너리는 unanchored 부분 문자열을 세기 때문에 **이 저장소의 Plans.md에서 존재하지 않는 blocked
태스크를 하나 발명한다.** 게다가 `session-init`은 6행 마커 레전드를 세션 컨텍스트에 하드코딩해
주입하는데, Go 소스가 없어 새 마커를 반영할 수 없다. `monitors/monitors.json`이 아직
`bin/harness hook session-monitor`를 실행한다 — 기본 무장된 마지막 바이너리 마커 표면이다.

---

## 2. 필수 답변 5개 (요약 먼저)

| 질문 | 답 |
|------|-----|
| 새 마커 vs 파일 이동? | **둘 다, 2단계로.** 먼저 제자리 마커 변경(`cc:dropped`, 보이는 묘비), 나중에 파일 이동(아카이브). 하나만 고르면 각각 실패한다. |
| 별도 백로그 파일 vs 백로그 없음? | **별도 파일, 단 마커 없이.** 순수 Shape Up은 1인+에이전트에서 무너진다. |
| 자동 만료 며칠? | **14일. 제안만, 절대 자동 기록 안 함.** 유도는 §2.3. |
| 중복 판정 주체? | **스킬 (`harness-plan`), 자문만, 절대 차단 안 함.** |
| 활성 파일 하드 캡? | **태스크 행 25개 soft / 30개 hard.** 초과 시 백로그로 fail-closed. |

아래는 각각의 근거.

### 2.1 새 마커인가, 파일 이동인가 — **둘 다, 순서대로**

Linear의 파이프라인은 2단이다: stale → Canceled(**여전히 보임**) → 추가 비활동 후 → archived
(활성 데이터셋 밖). 이 둘을 하나로 합치면 안 된다.

- **아카이브 절반만 복사하면**: 보이는 묘비를 잃는다. 포기된 항목과 완료된 항목이 아카이브에서
  구분 불가 — 이게 OpenSpec의 유일한 약점이다(랭킹 1위인데도).
- **마커 절반만 복사하면**: Plans.md가 무한히 자란다 — 이게 claude-task-master의 실패다.
  큐는 안 늘지만 `tasks.json`은 영원히 커진다.

그래서: **`cc:dropped`로 제자리 전이(묘비가 보인 채 유지) → 이후 스윕이 아카이브 파일로 물리 이동.**

**마커 이름: `cc:dropped`** (별칭 입력으로 `cc:cancelled` / `cc:canceled` 허용, `cc:dropped`로 정규화)

이름 선택 근거 — §1.4의 측정에서 직접 나온다:

1. **기존 마커의 접두 확장이면 안 된다.** `cc:wip-paused`는 wip로 흡수되고 **세션을 가둔다**(측정됨).
   `cc:dropped`는 todo/wip/done/blocked 어느 것과도 문자열이 겹치지 않아 wip-guard에서 fail-open한다(측정됨).
2. **철자 드리프트가 이 저장소의 실제 실패 기하학이다.** `cancelled`(UK) vs `canceled`(US)는
   진짜 위험이다 — 파서가 9곳이고 사람이 손으로 편집하며, 이미 `pm:reviewed`/`pm:pending`/
   `pm:confirmed` 세 개의 유령 이름이 존재한다. `dropped`는 철자가 하나다.
3. 업계 단어(`cancelled`)는 별칭으로 받아서 둘 다 챙긴다. 별칭 기계는 이미 있다
   (`cursor:` → `cc:`, `完了` → done).

**기각한 대안:**

| 대안 | 기각 이유 |
|------|-----------|
| `cc:cancelled` (표준 이름) | 철자 두 가지. US 철자로 타이핑하면 §1.4대로 행이 **조용히 증발**한다(분모 손상). 별칭으로만 수용. |
| `cc:wontdo` | 철자는 하나지만 단어 경계가 불명확하고 `cc:wont-do`/`cc:wont_do` 변형을 유발한다. |
| `cc:done` 재사용 + 설명 셀에 사유 | 포기가 완료로 **거짓말**한다. 감사 불가. 실패 1번을 전혀 못 죽인다. |
| `cc:blocked` 재사용 | blocked는 "무언가를 기다림" = **여전히 큐에 있고 여전히 빚**이다. 종결이 아니다. BMAD 함정 그대로. |
| 마커 없이 행 삭제만 | git 히스토리 밖에서는 grep 불가. 아카이브가 엄격히 우월하다(§2.1 아카이브 논거). |
| 접두 확장형(`cc:done-dropped`) | 측정상 `cc:done` 버킷에 흡수됨(§1.4). 치명. |

### 2.2 별도 백로그 파일인가, 백로그 없음(Shape Up)인가 — **별도 파일, 단 마커 없이**

각 극단에서 1인+에이전트에게 무너지는 것:

**순수 Shape Up (백로그 없음)에서 무너지는 것 — 안전망.**
Shape Up이 "let it go"를 안전하다고 말할 수 있는 이유는 저장이 아니라 **사회적 재발**이다:
"고객이 다시 불평하면", "Support가 다시 로비하면", "부서 간 1:1이 다시 꺼내면". 사용자가 거의
없는 1인 개발자에게는 **외부 신호 재생기가 없다.** 그래서 "let it go"는 그냥 "잊어버린다"로
붕괴하고, 의존하게 되는 것(자기 기억)이 애초에 이 정책이 의존하지 않으려던 바로 그것이다.

다만 Shape Up은 **아무것도 적지 말라고 한 적이 없다**. 자주 오독된다. 실제 문구는
"베팅에 **직접 입력**되는 **중앙** 리스트가 없다"이다. 부서별 개인 리스트는 계속 존재한다.

**순수 Linear (필터된 단일 데이터셋)에서 무너지는 것 — 필터.**
Linear의 Backlog/Active 분리는 **UI가 있어서** 성립한다. 승격이 드래그 한 번이다. 마크다운에는
UI가 없다. 유일하게 쓸 수 있는 필터는 **파일 경계**다. 섹션 헤딩으로 나누는 건 필터가 아니다 —
9개 파서 전부가 파일 전체를 스캔하고, 섹션은 카운트에서 안 빠진다(v1.3.6이 정확히 이 실패였다).

**결론: 3-파일. 그리고 백로그 파일은 마커를 갖지 않는다.**

```
Plans.md                              활성만. cc:todo / cc:wip / cc:blocked
                                      + 아직 아카이브 안 된 종결 행(cc:done / cc:dropped)
Plans-backlog.md                      비정형 캡처. append-only. cc: 마커 전면 금지
.claude/memory/archive/Plans-<date>.md  종결 행의 최종 안착지. 절대 스캔 안 함
```

**핵심 수는 "백로그 행은 `cc:` 마커를 갖지 않는다"이다.** 이건 스타일 규칙이 아니라 **물리적
집행**이다:

- 9개 파서 전부가 마커로 행을 인식한다. 마커가 없으면 **누가 실수로 파서를 이 파일에 겨눠도**
  카운트가 0이다.
- 이것이 "중앙 리스트가 베팅의 직접 입력이 아니다"를 관례가 아니라 **구조로** 구현한다.
- 승격 = 평문 불릿을 Plans.md의 표 행으로 **다시 쓰는 것**. 이 재작성 마찰이 Shape Up에서
  동료에게 로비해야 하는 마찰의 대체물이다. 마찰은 버그가 아니라 **기능**이다.

파일명 안전성 확인: `Plans-backlog.md`는 어떤 탐색 경로에도 안 걸린다. wip-guard는
`Plans.md` → `docs/Plans.md`, plans-watcher는 `<root>/Plans.md` 정확 일치, HUD는
`$PROJ_DIR/Plans.md`와 `$PWD/Plans.md`만 본다. 충돌 없음.

**Backlog-by-default 채택.** Linear에서 새 이슈는 Backlog에 태어나고 Active 진입은 명시적 승격이다.
번역: `harness-plan`이 만드는 새 항목은 **기본적으로 `Plans-backlog.md`로 간다.** `harness-work`가
승격한다. 이러면 `cc:todo` 카운트가 열망이 아니라 **실제 in-flight**를 뜻하게 된다.

**기각한 대안:**

| 대안 | 기각 이유 |
|------|-----------|
| 백로그 없음 (순수 Shape Up) | 안전망이 사회적 재발에 의존. 1인 개발자에겐 신호 재생기가 없어 "포기"가 "망각"이 됨. |
| Plans.md 내 `## Backlog` 섹션 | 필터가 아님. 9개 파서 전부 파일 전체를 스캔 → 백로그 항목이 카운트/분모/HUD에 그대로 들어감. v1.3.6 재현. |
| 백로그 파일에 `cc:backlog` 마커 도입 | 마커 어휘를 늘림(Linear의 fixed-spine 교훈 위반). 게다가 카운터에 보이므로 파일 분리의 이점이 사라짐. |
| `docs/Plans.md`를 백로그로 사용 | **위험.** wip-guard가 폴백으로 이 경로를 읽는다(측정됨) → 백로그의 WIP 유사 문자열로 Stop이 막힌다. |
| 4-파일(백로그를 shaped/unshaped로 분리) | 1인 규모에서 순수 과잉. Shape Up 부록이 명시적으로 구조 제거를 처방. |

### 2.3 자동 만료 며칠인가 — **14일, 제안만**

**먼저 정직하게: 측정 데이터는 임계값을 적합(fit)시킬 수 없다.** 포기율이 진짜 0/20이고,
행 삭제로 가려진 0이 아니다(7개 스냅샷 집합 차분으로 검증). 관측된 포기 분포가 **존재하지 않는다** —
"망할 항목이 얼마나 오래 사는가"의 분모가 비어 있다.

그래서 데이터는 임계값을 **적합시킬 수는 없지만, 아래에서 경계 지을 수는 있다.** 유도:

```
[1] 측정된 최대 정당 체류 (cc:todo → cc:done)
    D_max = 356791 s = 4d 03h 06m 31s = 4.129 일        (행 3.2, 3.3)

[2] 하한: 임계값은 D_max를 넘어야 한다.
    안 그러면 나중에 정상 완료된 작업을 죽인다.
    측정상 4.129일 미만의 임계값은 태스크 4개(3.1, 3.2, 3.3, 4.2)를 만료시켰을 것이다.
    → threshold > 4.129 일                              [측정된 바닥]

[3] 그 4개는 전부 사람 승인 게이트에 걸려 있었지 작업량 때문이 아니었다.
    임계값은 의사결정 게이트에서 발화하면 안 된다. 게이트는 정상 상태다.

[4] 표본 최대값은 모집단 최대값이 아니다.
    n=20에서 다음 관측이 기존 20개를 전부 넘을 확률 = 1/21 ≈ 4.8% (무모수).
    → 안전 계수 필요. 공학적 기본값 ×2 채택 (데이터가 아니라 명시된 정책).
    2 × 4.129 = 8.26 일

[5] 사람이 실제로 검토하는 경계로 올림 (주 단위).
    8.26 일 → 다음 주 경계 = 14 일

[6] 소급 검증 — 결정적 단계:
    측정된 이력 20개 행 전부에 14일을 적용하면 취소되는 행: 0 / 20.
    최대 체류 4.129일 << 14일.
    → 관측된 이력 100%에 대해 증명 가능하게 비파괴적이다.
```

**14일. 그리고 이 숫자에 대해 주장할 수 있는 최강의 것은 "적합시켰다"가 아니라 "관측된 모든
이력에서 아무것도 안 죽인다"이다.** 그게 정직한 한계다.

Linear가 이걸 지지한다: Linear는 메커니즘을 출하하면서 **기본값 숫자를 공개하기를 거부하고**
팀별 설정으로 노출한다. 공개 문서에 auto-close 기본값도 auto-archive 기본값도 없다(웹 요약이
주장하는 "6개월"은 어떤 Linear 페이지에서도 확인되지 않는다). 즉 **수입할 권위 있는 상수가
애초에 없다.** 그래서 14일은 `harness.toml`에서 설정 가능해야 하고, 이 문서의 유도가 기본값의
근거로 남는다.

**두 개의 서로 다른 14일 트리거:**

| 트리거 | 조건 | 산출 |
|--------|------|------|
| **T1 — stale 제안** (약한 근거) | `cc:todo` 또는 `cc:blocked` 행이 14일간 무터치 | `cc:dropped` **후보로 보고**. 기록 안 함. |
| **T2 — 아카이브 제안** (강한 근거) | 모든 행이 종결(done/dropped) **그리고** 파일 14일 무편집 | 아카이브 이동 **제안** |

**T2가 T1보다 근거가 훨씬 강하다.** 측정: 이 파일은 2026-07-08에 100% done에 도달했고
2026-07-18에 마지막 편집됐다. T2 규칙이라면 **2026-08-01에 발화**했을 것이다. 오늘은 2026-08-11 —
현재 상태(33일간 미아카이브된 완료 원장)를 정확히 짚어낸다. 반면 T1은 뒷받침할 포기 관측이 0개다.
그래서 T1은 기본 **꺼짐**으로 출하하고, T2는 기본 **켜짐**으로 출하한다.

**절대 자동으로 쓰지 않는다.** Linear가 auto-cancel을 안전하게 할 수 있는 이유는 활동 피드,
undo, 변경을 노출하는 UI가 있기 때문이다. UI 없는 마크다운 파일에는 셋 다 없다 — 행을
`cc:dropped`로 조용히 재작성하면 **누군가 diff를 읽기 전까지 안 보인다.** 올바른 적응은
후보를 **보고**하고(harness-sync의 drift 출력이 이미 하는 방식) 확인된 패스에서만 쓰는 것이다.

**per-row last-touch는 스키마 변경 없이 git으로.** 새 날짜 컬럼이 필요 없다:

```
$ git blame --line-porcelain -- Plans.md | grep -c '^author-time'
71                       # 71줄 전부 per-line author-time 확보 (측정됨)
```

한 번의 서브프로세스, awk로 파싱 가능, shell+awk+jq 제약 준수. 알려진 한계: 파일 전체 재포맷은
모든 blame을 리셋한다. **마이그레이션 자체가 blame을 리셋하므로 스윕의 시계는 마이그레이션
시점부터 시작한다** — 문서화하고 수용한다.

**만료의 목적지는 done이 아니라 dropped다.** Linear: "Issues will be auto-closed and **marked
canceled**." done으로 만료시키면 시스템이 거짓말을 하고, 실패 1번이 그대로 돌아온다.

**기각한 대안:**

| 대안 | 기각 이유 |
|------|-----------|
| 자동 만료 없음 | 실패 1번을 못 죽인다. Linear의 핵심 교훈: 수동 그루밍은 **일어나지 않는다**. 스탠드업도 PM도 없는 1인은 팀보다 그루밍 압력이 **더 적다** → 기계화 논거가 여기서 **더 강하다**. |
| 7일 (BMAD `STALE_DAYS_DEFAULT`) | 측정된 정당 체류 최대 4.129일에 안전 계수 ×2를 적용하면 8.26일 > 7일. 파일 수준 체크용 상수를 per-task에 전용하는 것이기도 하다. |
| 5일 (측정 바닥 바로 위) | 안전 계수 없음. 표본 최대값을 모집단 최대값으로 취급하는 오류. |
| 30일 / 6개월 | 데이터에서 유도 불가. "6개월"은 Linear 문서에서 **확인되지 않은** 웹 요약이다 — 카고컬트. |
| 자동 기록(조용한 rewrite) | UI/undo/활동피드 없음 → diff를 읽기 전까지 안 보임. 1인 개발자의 신뢰를 즉시 파괴하고, 그러면 도구를 꺼버린다. |
| 생성일 기준 만료 | Linear는 **비활동**(마지막 업데이트) 기준이지 생성 후 경과가 아니다. 생성 기준은 활발히 진행 중인 장기 작업을 죽인다. |

### 2.4 중복은 누가 판정하나 — **스킬. 자문만. 절대 차단 안 함.**

측정 근거부터: **이 코퍼스에는 중복할 것이 없다.** 190개 설명 셀 쌍 중 Jaccard ≥ 0.20이
`[tdd:skip:*]` 보일러플레이트 제거 후 **0개**다. 중복 ID 0, 완전 중복 행 0.

| 주체 | 잘못 판정하면 어느 쪽으로 실패하나 | 판정 |
|------|-----------------------------------|------|
| **훅** (PreToolUse가 Plans.md 쓰기를 차단) | **Fail-closed, 복구 불가.** 정당한 추가가 흐름 중에 거부된다. 이 저장소에는 이미 판례가 있다 — wip-guard가 `cc:wip-paused` 하나로 **세션을 가둔다**(측정됨). 관측 발생률 0인 문제에 차단 훅을 짓는 건 잘못된 교환이다. | **기각** |
| **사람** (직접 검토) | 일어나지 않는다. Linear의 전체 논지가 이것이다: 자동화를 만든 이유가 팀이 백로그를 "manually comb through" 하지 않게 하려는 것. 1인은 팀보다 의례가 **더 없다**. | **기각** |
| **스킬** (`harness-plan`이 추가 전 검사) | **Fail-open, 복구 가능.** 중복 행 하나가 생긴다 → 사람이 보거나, 다음 스윕이 하나를 dropped 후보로 올린다. 값싸게 회복된다. | **채택** |

`harness-plan`은 이미 append하려고 Plans.md를 읽는다. 추가 I/O가 0이다.

**임계값 유도:** 보일러플레이트 제거 후 실제 쌍의 관측 최대 유사도 = **0.21**, 190쌍 중 0.20을
넘는 쌍 = **0**. 관측된 노이즈 천장의 **2배**인 **Jaccard ≥ 0.4**를 채택 → 측정된 코퍼스에서
오탐 0이 보장된다. 스킬은 후보를 보여주고 진행한다. **절대 멈추지 않는다.**

### 2.5 활성 파일 하드 캡 — **태스크 행 25 soft / 30 hard**

캡이 필요한 이유: 실패 2번이 "안 읽힐 때까지 커졌다"이다. Linear는 캡이 없지만 **UI가 있다.**
Shape Up은 구조적으로 캡이 걸린다(후보가 지난 사이클 피치 + 되살린 1~2개). UI 없는 마크다운은
명시적 숫자가 필요하다.

**유도 (약함 — 정직하게 표시):** 이 저장소는 71줄/20행을 넘은 적이 없으므로 "안 읽히는 지점"의
관측치가 **없다.** 임계값을 적합시킬 수 없다. 유도할 수 있는 것:

```
관측된, 실제로 완주된 최대 계획 = 20 태스크 행 (5일 만에 100% done)
soft cap = 20 × 1.25 = 25        (검증된 작업 크기 + 25% 여유)
hard cap = 30                    (soft 초과 20% 지점에서 정지)
WIP cap  = 1                     (Shape Up: 활성 베팅 1개. wip-guard가 이미 사실상 집행)
```

여기서 세는 것은 **활성 행뿐**(todo + wip + blocked)이다. 아직 아카이브 안 된 종결 행은
캡에 안 들어간다 — 안 그러면 캡이 아카이브 스윕과 싸운다.

**오버플로 시 무슨 일이 일어나나 — 백로그로 fail-closed:**

| 상태 | 동작 |
|------|------|
| 활성 행 ≤ 25 | 정상. `harness-plan`이 Plans.md에 추가. |
| 26–30 | **경고**하고 새 항목을 `Plans-backlog.md`로 라우팅. Plans.md 추가는 명시적 승격으로만. |
| > 30 | **Plans.md 추가 거부.** 백로그로 라우팅하고 이유를 출력. 아카이브 스윕을 먼저 돌리라고 안내. |

**절대 조용히 자라지 않는다.** 이건 파일 자체에 적용한 Shape Up의 circuit breaker다: 기본값이
연장 없음이고, 실패 방향이 백로그(회복 가능)이지 무한 증가(회복 불가)가 아니다.

**기각한 대안:**

| 대안 | 기각 이유 |
|------|-----------|
| 캡 없음 (Linear식) | Linear는 UI로 필터한다. 마크다운은 못 한다. 실패 2번을 그대로 둔다. |
| 바이트/라인 캡 | 설명 길이에 좌우된다. 잘 문서화된 태스크 10개가 한 줄짜리 40개보다 먼저 걸린다 — 좋은 서술을 벌준다. |
| 오버플로 시 하드 에러(백로그 라우팅 없음) | 흐름을 막는다. 사람은 도구를 우회하거나 끈다. 캡이 자멸한다. |
| 오버플로 시 자동 아카이브 | 종결 안 된 행을 조용히 옮긴다. Linear: 아카이브는 상태+시간의 순수 함수여야 하고 **불편한 작업의 은신처가 되면 안 된다.** |

---

## 3. 마커 모델

### 3.1 닫힌 어휘

Linear의 fixed-category 규율: **어휘는 닫혀 있고, 더 미세한 구분은 설명 셀로 가지 절대 새
마커로 가지 않는다.** `scripts/lib/plans-markers.awk`가 유일한 정의다.

| 마커 | 분류 | 뜻 | 분모 | 진행률 기여 |
|------|------|-----|------|-------------|
| `cc:todo` | active | 시작 안 함 | 포함 | 아니오 |
| `cc:wip` | active | 진행 중 (최대 1개) | 포함 | 아니오 |
| `cc:blocked` | active | 무언가를 기다림 — **여전히 빚** | 포함 | 아니오 |
| `cc:done` | **terminal** | 완료 | 포함 | **예** |
| `cc:dropped` | **terminal** | **안 하기로 결정함** | 포함 | **예** |
| `pm:requested` | gate | PM 요청 | 별도 | — |
| `pm:approved` | gate | PM 승인 | 별도 | — |

입력 별칭(정규화 대상): `cursor:*` → `cc:*`, `cc:完了` → `cc:done`, `pm:依頼中` → `pm:requested`,
**`cc:cancelled` / `cc:canceled` → `cc:dropped`** (신규).

### 3.2 terminal-complete 의미론 — 훔쳐올 최고의 아이디어

claude-task-master의 `TERMINAL_COMPLETE_STATUSES = ['done','completed','cancelled']`.
이게 문제의 **비자명한 절반**이다. 누구나 'cancelled' 라벨은 상상할 수 있다. 거의 아무도 그
결과를 처리하지 않는다.

```
active   = todo + wip + blocked
terminal = done + dropped
total    = active + terminal
progress = terminal / total          ← done/total 이 아니다
```

`cc:dropped`는:
- **분모에 남는다** (증발하지 않는다 — §1.4의 미지 마커 실패를 피한다)
- **진행률에 기여한다** (done과 동일)
- **의존성을 만족시킨다** (다운스트림 태스크를 데드락시키지 않는다)
- **"다음 태스크"로 선택되지 않는다**

**왜 이게 하중을 받나:** dropped가 진행률을 깎으면 운영자는 **아무것도 포기 표시하지 않도록
학습된다.** 그게 정확히 BMAD의 리스트가 무한히 자라는 이유다. 의미론을 훔쳐야지 라벨만 훔치면 안 된다.

부작용: 전부 dropped하면 100%가 된다. Linear/task-master가 수용한 동작이고 올바르다 — 가지치기를
벌하지 않는다. 다만 **HUD가 dropped를 별도로 표시**해서 숨지 못하게 한다.

**분모 버그도 같이 고친다:** 현재 `hud/statusline.sh:147`의 `TOTAL=$((TODO + WIP + DONE))`은
**blocked를 이미 분모에서 빼고 있다.** 오늘부터 틀렸다. 새 규칙이 이걸 바로잡는다.

### 3.3 출력 ABI — 위치 기반에서 라벨 기반으로

§1.5에서 확인했듯 7번째 열 추가는 `plans-state.json`을 깨뜨린다. 그래서 **의도적으로, 한 번만**
ABI를 바꾼다:

```
# 이전
todo wip done blocked pm_requested pm_approved
0 0 16 0 0 0

# 이후
todo=0 wip=0 done=20 blocked=0 dropped=0 pm_requested=0 pm_approved=0
```

그리고 **공유 로더**를 새로 만들어 어떤 소비자도 파싱을 재구현하지 않게 한다:

```
scripts/lib/plans-counts.sh   (신규)
  plans_counts_load <file>  →  PLANS_TODO PLANS_WIP PLANS_DONE PLANS_BLOCKED
                               PLANS_DROPPED PLANS_PM_REQUESTED PLANS_PM_APPROVED
                               PLANS_ACTIVE PLANS_TERMINAL PLANS_TOTAL
```

이게 §1.6의 드리프트 기하학을 죽인다. **한 곳에 정의하고 테스트로 추종자를 고정한다.**
이후 상태 추가는 모든 독자에게 additive가 된다.

---

## 4. 파일 레이아웃

```
<repo root>/
├─ Plans.md                                 ← 기본으로 열리는 파일. 활성 작업만.
├─ Plans-backlog.md                         ← 비정형 캡처. cc: 마커 금지.
└─ .claude/memory/archive/
   └─ Plans-<YYYY-MM-DD>[-<phase>].md       ← 종결 행 안착지. 절대 스캔 안 함.
```

> 아카이브 경로는 **이 저장소의 기존 관례**다 (`docs/plans-archive-pattern.md`, 업스트림에 26개
> 존재). 작업 지시가 가정한 `Plans-archive-*.md`가 **아니다.**

**기본으로 열리는 파일은 `Plans.md`이며, 활성 작업만 담는다.** Linear의 Active 뷰가 6개 카테고리
중 3개를 기본 숨김하는 것과 같다.

### 4.1 각 파일의 내용

**`Plans.md`** — 표 dialect. 활성 행(todo/wip/blocked) + 아직 아카이브 안 된 종결 행.
활성 행 ≤ 25(soft) / 30(hard). `cc:wip` ≤ 1.

**`Plans-backlog.md`** — 평문 불릿, 캡처 날짜 포함, **`cc:` 마커 없음**. 표 행도 아니다
(표준 카운터가 표 행만 세므로 이중 안전). 캡 없음 — append-only 캡처는 자라도 된다.
읽히지 않으니까. 승격만이 유일한 출구.

**`.claude/memory/archive/Plans-<date>.md`** — 종결 행이 이동해 온다. **어떤 카운터도 절대 읽지
않는다.** 물리 분리가 각 카운터에게 섹션 건너뛰기를 가르치는 것보다 훨씬 싼 집행이다 —
v1.3.6이 정확히 이 교훈이다(아카이브 문장 하나가 `cc_done`을 부풀렸다).

### 4.2 카운팅 규칙 (불변)

| 파일 | HUD | plans-watcher | progress-snapshot | wip-guard |
|------|-----|---------------|-------------------|-----------|
| `Plans.md` | 읽음 | 읽음 | 읽음 | 읽음 |
| `Plans-backlog.md` | **안 읽음** | **안 읽음** | **안 읽음** | **안 읽음** |
| `.claude/memory/archive/**` | **안 읽음** | **안 읽음** | **안 읽음** | **안 읽음** |

**아카이브된 행은 어떤 카운트에도 기여하지 않는다.** 회귀 가드가 이걸 고정한다.

---

## 5. 결정 요약과 기각된 대안

### 5.1 왜 네 조각 전부인가

각 라이벌은 최대 2개를 한다. 넷 다 하는 시스템은 조사 대상 중 없다.

| 시스템 | A 이름있는 종결 | B terminal-complete 의미론 | C 물리 이동 | D staleness 스윕 | 결과 |
|--------|:---:|:---:|:---:|:---:|------|
| OpenSpec | ✗ | — | ✓ | ✗ | 활성 집합은 유계지만 왜 떠났는지 기록 없음 |
| claude-task-master | ✓ | ✓ | ✗ | ✗ | 큐는 안 늘고 파일은 무한 증가 |
| BMAD-METHOD | ✗ | — | ✗ | ✓ | 썩는 걸 알려주고 자를 어휘는 없음 (진단만, 치료 없음) |
| Amazon Kiro | ✗ | — | ✗ | ✗ | 생명주기 없음 |
| GitHub Spec Kit | ✗ | — | ✗ | ✗ | 이진 체크박스뿐 |
| **chanpark-harness (현재)** | **✗** | — | **✗** | **✗** | **BMAD 함정, 진단도 없이** |
| **chanpark-harness (제안)** | **✓** | **✓** | **✓** | **✓** | — |

### 5.2 Shape Up에서 채택 / 기각

에이전트는 1인 개발자에게 **위임(Force 1)은 주지만 복수성(Force 2)은 안 준다.** 이 비대칭이
무엇이 살아남는지를 깔끔하게 예측한다.

| Shape Up 요소 | 판정 | 근거 |
|---------------|------|------|
| Circuit breaker (연장 없음) | **채택** — WIP=1 + 14일 스윕 | 에이전트가 가치를 **높인다**: 한 번 더 시도의 한계비용이 낮아 매몰비용 나선이 들어가기 쉽고 **느끼기 어렵다**. |
| Appetite / 기록된 베팅 | **채택** — 태스크 행이 그 기록 | 안 적혀 있으면 베팅이 아니라 그냥 "일하는 것"이고, 그건 실패 조건이 없다. |
| No-backlog **정책** | **부분 채택** | 세 갈래 논거는 n=1에서 더 세게 적용된다. 그러나 안전망(사회적 재발)은 이전 안 된다 → §2.2. |
| Cool-down | **채택** — T2 아카이브 제안이 그 이음매 | "사이클 끝은 만나서 계획하기 최악의 시점." 1인은 **항상 everybody**다. |
| Betting table (회의) | **기각** | 좌석 4개 중 3개가 무효. 자원 배분은 문자 그대로 공집합. 남는 하중은 회의가 아니라 **기록된 약속**이다. |
| 에이전트로 빈 좌석 채우기 | **기각** | 에이전트에게 go/no-go를 물으면 **비준 편향**이 있다 → 직감을 결정으로 세탁한다. 테이블 없는 것보다 **더 나쁘다**. |
| 6주 고정 사이클 | **기각** | 하한을 만든 힘(계획 오버헤드)이 1인+무회의에서 0으로 간다. 살아남는 건 "느껴지는 마감"뿐. |
| Kick-off 공지 / 부서별 리스트 / 팀 사이징 | **기각** | 1인에서 공허. |

---

## 6. 파일별 변경 지도

구현 금지 — 이건 지도다. 4단계, 각 단계는 독립적으로 커밋 가능하고 되돌릴 수 있다.

### Phase 0 — 데이터 수리 (다른 모든 것에 선행. 필수.)

| 파일 | 변경 | 비고 |
|------|------|------|
| `Plans.md` | 상태 셀 4개의 `cc&#58;done` → `cc:done` (행 1.5, 2.2, 3.1, 6.1). **설명 셀 이스케이프는 유지.** | §1.2. 카운터가 16 → 20이 된다. |
| `tests/fixtures/plans-status-cell-entity.md` | **신규** — 디플레이션 픽스처. 설명 셀에 이스케이프된 마커, 상태 셀은 정상. | 기존 인플레이션 픽스처의 거울상. |
| `scripts/ci/check-regression-guard.sh` | **신규 케이스** `check_plans_status_cell_entity` — 어떤 상태 셀도 `&#58;`를 포함하면 FAIL. | 미커버 결함을 봉인. |

### Phase 1 — 어휘 + 단일 출처 (ABI 변경. 한 커밋에 전부.)

| 파일 | 변경 |
|------|------|
| `scripts/lib/plans-markers.awk` | `cc:dropped` 분기 추가 + 별칭 `cc:cancelled`/`cc:canceled` 정규화. 출력을 라벨 k=v로 전환. |
| `scripts/lib/plans-counts.sh` | **신규** — 공유 로더 (§3.3). 유일한 파싱 지점. |
| `hud/statusline.sh` | 로더 사용. `TOTAL`을 blocked 포함으로 **수정**(현재 버그). dropped 별도 표시. 인라인 WIP-title awk 갱신. **grep 폴백 제거** (v1.3.6 이전 unanchored 규칙, CI 커버리지 0 — 조용히 틀리느니 0을 표시하는 게 낫다). |
| `scripts/hook-handlers/plans-watcher.sh` | 로더 사용. `plans-state.json`에 `cc_dropped` 추가. dropped 증가 시 델타 메시지 추가(현재 done/pm만 발화). |
| `scripts/hook-handlers/wip-guard.sh` | 표 dialect: unanchored `~ /cc:wip/`를 **앵커 매치**로 교체(후행 노트 제거 후). 체크리스트 dialect: `cc:[A-Za-z]+`의 하이픈 절단 수정 → `cc:[A-Za-z-]+`. §1.4의 세션 감금 버그를 죽인다. |
| `scripts/progress-snapshot.sh` | dropped 버킷 추가. `total`에 blocked 포함. `progress_pct = terminal/total`. |
| `skills/harness-progress/schemas/progress-snapshot.v1.schema.json` | `blocked_tasks`/`_blocked_count` 추가 (**이미 방출 중이라 오늘 스키마 위반**) + `dropped_tasks`/`_dropped_count`. |
| `skills/harness-plan-brief/schemas/plan-brief-context.v1.schema.json` | outcome enum에 `cc:dropped` 추가. **유일한 loud-fail 경로.** |
| `scripts/plan-brief-compile.sh` | 신뢰도 계산에서 dropped를 terminal로 취급 (안 그러면 취소가 점수를 깎는다). |
| `tests/fixtures/plans-mixed-markers.md` | dropped 행 추가. |
| `tests/fixtures/plans-prose-marker-inflation.md` | `(all cc:done)` 트랩 문장 **보존** + dropped prose 트랩 추가. |
| `scripts/ci/check-regression-guard.sh` | 리터럴 단언 3개 갱신 (`"6 0 9 0 0 0"`, `"2 2 2 1 0 0"`, `"6 0 9 0"`). wip-guard 앵커링 케이스 신규. 미지 마커 케이스 신규. |

### Phase 2 — 바이너리 인수 (`plans-watcher.sh` 판례를 따름)

| 파일 | 변경 |
|------|------|
| `scripts/hook-handlers/session-monitor.sh` | **신규** — `harness hook session-monitor`를 대체. §1.7의 live 드리프트(존재하지 않는 blocked 발명)와 하드코딩된 6행 레전드를 고친다. |
| `monitors/monitors.json` | 바이너리 대신 스크립트를 exec. |
| `scripts/ci/check-regression-guard.sh` | **신규** `check_session_monitor_handler` — 기존 `check_plans_watcher_handler`를 미러. `harness sync`가 바이너리를 되돌려 놓으면 FAIL. |

> 세션 시작 블록은 Linear의 Overview 랜딩에 해당한다. 여기서 **active / backlog / archive 카운트를
> 분리해서** 보고한다.

### Phase 3 — 파일 레이아웃 + 스킬 계약

| 파일 | 변경 |
|------|------|
| `Plans-backlog.md` | **신규** — 마커 없는 캡처 파일 + 규칙을 설명하는 헤더. |
| `scripts/plans-sweep.sh` | **신규** — T1/T2 제안자. `git blame --line-porcelain`으로 per-row last-touch. **읽기 전용, 후보만 보고.** |
| `harness.toml` | `[plans]` 섹션: `stale_days = 14`, `archive_days = 14`, `soft_cap = 25`, `hard_cap = 30`, `stale_sweep_enabled = false`, `archive_sweep_enabled = true`. |
| `skills/harness-plan/SKILL.md` + `references/create.md` | 레전드 수정(`cc:blocked` **누락됨**, `blocked`로 오표기 → 수정, `cc:dropped` 추가). Backlog-by-default. 캡 집행. 중복 자문 검사(Jaccard ≥ 0.4). |
| `skills/harness-work/SKILL.md` + `references/*` | 백로그 → Plans.md 승격 단계. `cc:dropped` 전이(~15개 지점). WIP=1 명시. |
| `skills/harness-sync/SKILL.md` | `pm:reviewed` → `pm:approved` **수정**(유령 이름). 스윕 후보를 drift 출력에 보고. |
| `skills/maintenance/references/cleanup.md` | `pm:pending`/`pm:confirmed` → `pm:requested`/`pm:approved` **수정**(유령 이름). `cc:done`**과** `cc:dropped` 둘 다 아카이브. 아카이브는 **스윕 전용, 손으로 옮기지 않음**(Linear: 아카이브는 은신처가 되면 안 됨). |
| `templates/Plans.md.template` | 표 dialect로 전환(현재 체크리스트 dialect라 **표준 카운터가 0을 반환** — 새 프로젝트의 HUD가 빈 채로 시작). 레전드에 dropped 추가. 백로그 파일 안내. |
| `scripts/plans-format-migrate.sh` | 엔티티 수리 + 백로그 분리 마이그레이션 추가. |
| `CLAUDE.md` | 불변식 갱신: 닫힌 어휘 5개 `cc:` 마커, 3-파일 레이아웃, 캡, 라벨 ABI. |

---

## 7. 마이그레이션

### 7.1 전진 (단계별)

각 단계는 **자체 커밋**이고 독립적으로 검증된다.

| # | 단계 | 검증 |
|---|------|------|
| **0** | 백업 태그: `git tag plans-redesign-baseline` | `git tag -l` |
| **1** | `Plans.md`의 상태 셀 엔티티 4개 un-escape | `awk -f scripts/lib/plans-markers.awk Plans.md` → `0 0 20 0 0 0` |
| **2** | 디플레이션 픽스처 + CI 가드 케이스 추가 | `bash scripts/ci/check-regression-guard.sh` → PASS |
| **3** | 카운터에 `cc:dropped` + 별칭 추가, 라벨 ABI로 전환 | 새 dropped 픽스처에서 라벨 출력 확인 |
| **4** | `scripts/lib/plans-counts.sh` 추가; **소비자 4개 전부 같은 커밋에서** 전환 | HUD, plans-watcher, snapshot, plan-brief 각각 실행 |
| **5** | wip-guard 앵커링 수정 | `cc:wip-paused` 픽스처 → **block 안 함** (현재는 block) |
| **6** | 스키마 2개 + CI 리터럴 3개 갱신 | `harness validate`, 회귀 가드 전체 |
| **7** | `session-monitor.sh` + `monitors.json` + CI 가드 | 스크립트 직접 실행, 카운트가 표준과 일치 확인 |
| **8** | `Plans-backlog.md` 생성 (초기 비어 있음) | 카운터를 겨눠도 0 반환 확인 |
| **9** | `plans-sweep.sh` 추가 (읽기 전용) | 현재 Plans.md에 실행 → **T2 아카이브 제안이 발화해야 함** (마지막 편집 후 33일, 전부 종결) |
| **10** | 스킬/템플릿/CLAUDE.md 문서 갱신 | `harness validate`; english-only grep이 비어야 함 |
| **11** | 스윕 제안 실행: 현재 20개 종결 행을 `.claude/memory/archive/Plans-2026-08-11.md`로 이동 | Plans.md 활성 행 0, 아카이브에 20행 |

**단계 4가 원자적이라는 점이 중요하다.** ABI 변경이라 카운터와 4개 소비자가 같은 커밋에 있어야
한다. 나누면 `plans-state.json`이 깨진 JSON을 쓴다(§1.5).

**단계 11 주의:** 파일 재작성이 `git blame`을 리셋한다. 스윕의 last-touch 시계는 여기서부터
시작한다. 예상된 동작이고 문서화한다.

### 7.2 english-only 가드

`scripts/ci/check-regression-guard.sh`의 english-only 케이스는 `agents/ skills/ output-styles/
templates/`를 강제한다. 이 설계 문서는 `docs/` 아래라 한국어가 허용된다. **Phase 3의 스킬/템플릿
변경은 반드시 영어로 작성한다.**

```
grep -rlP '[\x{3040}-\x{30ff}\x{4e00}-\x{9fff}]' agents skills output-styles templates   # 비어야 함
```

### 7.3 역행 (어떻게 되돌리나)

각 Phase는 독립적으로 되돌릴 수 있고, **역순으로** 되돌린다.

| 되돌릴 Phase | 절차 | 데이터 손실? |
|--------------|------|--------------|
| **Phase 3** (레이아웃) | 아카이브 파일 행을 `Plans.md`에 다시 append. `Plans-backlog.md` 항목을 `cc:todo` 행으로 승격하거나 파일 유지(무해 — 어떤 파서도 안 읽음). `plans-sweep.sh` 삭제. `harness.toml [plans]` 제거. 스킬 문서 revert. | **없음.** 아카이브는 비파괴적이고 grep 가능. |
| **Phase 2** (바이너리 인수) | `monitors/monitors.json`을 `bin/harness hook session-monitor`로 revert. `check_session_monitor_handler` 제거. | 없음. 단 §1.7의 오카운트가 **돌아온다.** |
| **Phase 1** (어휘) | 카운터를 6정수 위치 출력으로 revert, `cc:dropped` 분기 제거. 소비자 4개 revert. CI 리터럴 revert. **선행 조건: 남아 있는 `cc:dropped` 행이 없어야 한다** — 있으면 §1.4대로 조용히 증발한다. | **조건부.** 되돌리기 전에 `grep -c 'cc:dropped' Plans.md` = 0을 확인해야 한다. 아니면 dropped 행을 `cc:done`으로 재작성(정보 손실 — 그래서 이게 가장 되돌리기 비싼 단계다). |
| **Phase 0** (데이터 수리) | **되돌리지 말 것.** 이건 순수 버그 수정이다. 되돌리면 20% 언더카운트가 복원된다. | 되돌림이 손해다. |

**전체 중단:** `git reset --hard plans-redesign-baseline`. 단계 0의 태그가 이걸 한 명령으로 만든다.

**되돌리기 순서가 강제되는 이유:** Phase 3가 `cc:dropped` 행을 만들고 Phase 1이 그걸 세는 유일한
것이다. Phase 1을 먼저 되돌리면 dropped 행이 모든 버킷과 분모에서 증발한다(§1.4에서 측정됨).

---

## 8. 남는 리스크

| 리스크 | 완화 |
|--------|------|
| 14일 임계값이 데이터에서 적합된 게 아니라 **경계 지어진** 것 | 설정 가능(`harness.toml`). T1은 기본 꺼짐. 소급 검증상 관측 이력 20/20에 대해 비파괴적. |
| 재포맷이 `git blame` 시계를 리셋 | 문서화. 마이그레이션이 시계를 리셋한다 — 스윕은 그 시점부터 센다. |
| 벤더 바이너리의 `session-init`이 여전히 unanchored 카운트 + 낡은 레전드를 주입 | Phase 2가 `session-monitor`를 인수. `session-init`은 남는다 — **주입된 컨텍스트일 뿐 아무도 되읽지 않는다.** 후속 작업으로 기록. |
| `harness sync`가 `monitors.json`을 되돌릴 가능성 | `check_session_monitor_handler`가 CI에서 FAIL시킨다 (`check_plans_watcher_handler` 판례). |
| 캡 숫자(25/30)가 약하게 유도됨 | 정직하게 표시(§2.5). 설정 가능. 실패 방향이 백로그(회복 가능)다. |
| dropped 남용으로 진행률 100% 위조 | HUD가 dropped를 **별도로** 표시. 세션 시작 블록이 카운트를 분리 보고. |

---

## 부록 A — 재현 명령

```bash
cd /data/chanp5660/chanpark-harness

# 현재 카운트 vs 엔티티 디코드 후
awk -f scripts/lib/plans-markers.awk Plans.md
sed 's/&#58;/:/g' Plans.md | awk -f scripts/lib/plans-markers.awk

# 영향받은 상태 셀
awk -F'|' '/^\|/ {s=$(NF-1); gsub(/^ +| +$/,"",s); id=$2; gsub(/^ +| +$/,"",id);
            if (s ~ /&#58;/ && id ~ /^[0-9]/) printf "row %-5s %s\n", id, s}' Plans.md

# 이력
git log HEAD --date=short --pretty='%h|%ad|%s' -- Plans.md

# per-row last-touch 가능성
git blame --line-porcelain -- Plans.md | grep -c '^author-time'

# 바이너리 드리프트
./bin/harness hook session-init | grep -i plans
```
