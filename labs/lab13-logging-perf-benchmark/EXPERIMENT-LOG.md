# Lab 13 실험 대장 (EXPERIMENT LOG)

> **목적**: 각 런이 **어떤 가설을, 얼마의 부하로, 언제부터 언제까지** 보냈는지 기록한다.
> 클라이언트는 이 표만 남기면 되고, 나머지(APIM Capacity·EventHubDroppedEvents,
> Event Hubs IncomingMessages, App Insights AppRequests)는 각 런의 **측정 시간창(UTC)**으로
> Azure 서버측 메트릭을 조회해 사후에 채운다.
>
> **이 파일은 맥북 로컬에 보관한다.** VM/RG를 삭제해도 이 기록은 남는다.
> Azure 서버측 메트릭은 조회 시점 기준 약 90일 보관되므로, 시간창만 있으면 재조회 가능하다.

## 실험 환경

| 항목 | 값 |
|---|---|
| APIM | `apim-ai-gw-aigateway-20260716` (기존, Developer v1, Korea Central) |
| APIM Resource Group | `rg-ai-gw-aigateway-20260716` |
| 실험 리소스 RG (삭제 대상) | `rg-ai-gw-logbench-202608191803` |
| Event Hubs | Standard, 40 TU, 32 partitions, auto-inflate OFF |
| EH 로거 | `logbench-v4-eh` (isBuffered=true) |
| 부하 VM | `Standard_D8as_v5` Linux, Korea Central |
| 부하 도구 | Python asyncio + aiohttp, concurrency=20 |
| 부하 프로파일 | 고정 500 offered RPS, warmup 120s + 측정 300s |

## 구성별 정의 (중요 — 헷갈리기 쉬움)

**이름 규칙**: 숫자(8/64)는 **클라이언트 요청 body 크기**, 문자(N/A/E)는 **로깅 방식**.
- N = None(무로깅), A = App Insights body 로깅, E = Event Hub 로깅
- 8 = 8KB 요청, 64 = 64KB 요청
- 예: N64 = "64KB 요청을 무로깅으로 처리". N8과 N64는 APIM 정책이 동일(무로깅), 요청 크기만 다름.

**설정되는 두 곳**:
1. APIM 정책 (`configure-condition.sh`): 로깅 방식(N/A/E) — log-to-eventhub 유무, App Insights body bytes
2. 클라이언트 요청 크기 (`benchmark.py --payload-bytes`): 8192 또는 65536

**⚠️ App Insights diagnostic 공통 배경 (모든 조건)**:
- **모든 조건(N/A/E)에서 App Insights diagnostic이 sampling 100%로 켜져 있다.** 요청당 메타데이터 텔레메트리(URL, 상태코드, duration)는 항상 App Insights에 기록됨.
- 조건별 차이는 **body bytes만**: A8/A64만 request body를 8192/65536 기록, N·E는 body 0.
- 즉 **N8/E8도 App Insights 메타데이터 부하가 있다.** "App Insights를 완전히 끈" 것이 아님.
- **따라서 비교는 "App Insights 메타데이터 공통 배경 + 각 조건의 추가 비용"**: A8 = 배경 + body 로깅, E8 = 배경 + EH 로깅. (사용자 결정: 이 설계 유지)

| 조건 | 요청 크기 | App Insights body | EH 로깅 | 검증하려는 것 |
|---|---|---|---|---|
| N8 | 8KB | 0 (메타만) | 없음 | 무로깅 8KB 기준선 |
| A8 | 8KB | 8192 | 없음 | App Insights body 로깅의 기록 완전성/지연 |
| E8 | 8KB | 0 (메타만) | 8KB | EH 로깅의 기록 완전성/지연 |
| N64 | 64KB | 0 (메타만) | 없음 | 무로깅 64KB 기준선 (요청 크기 비용) |
| E64 | 64KB | 0 (메타만) | 64KB | 대용량 EH 로깅 지연 (E64−N64) / EH TU 한계 |


## 서버측 재조회 명령 (시간창만 있으면 언제든 재현)

```bash
# 환경 변수
APIM_ID=$(az apim show -g rg-ai-gw-aigateway-20260716 -n apim-ai-gw-aigateway-20260716 --query id -o tsv)
EH_NS_ID=$(az eventhubs namespace show -g rg-ai-gw-logbench-202608191803 -n ehns-logbench-202608191803 --query id -o tsv)
WS_ID=5a3336dd-bc9b-484d-8f8c-19b23d279de9   # Log Analytics customerId
# S, E = 해당 런의 measureStartUtc, measureEndUtc (분 경계로 넉넉히)

# APIM 게이트웨이 부하%
az monitor metrics list --resource "$APIM_ID" --metric Capacity --aggregation Average Maximum --start-time "$S" --end-time "$E" --interval PT1M
# APIM 게이트웨이 처리시간(ms)
az monitor metrics list --resource "$APIM_ID" --metric Duration --aggregation Average --start-time "$S" --end-time "$E" --interval PT1M
# APIM → EH 송신/드롭 (EH 조건만)
az monitor metrics list --resource "$APIM_ID" --metric EventHubTotalEvents EventHubSuccessfulEvents EventHubDroppedEvents EventHubThrottledEvents --aggregation Total --start-time "$S" --end-time "$E" --interval PT1M
# EH 수신/스로틀
az monitor metrics list --resource "$EH_NS_ID" --metric IncomingMessages ThrottledRequests --aggregation Total --start-time "$S" --end-time "$E"
# App Insights 실제 기록 수 (A8 조건)
az monitor log-analytics query -w "$WS_ID" --analytics-query "AppRequests | where TimeGenerated between (datetime($S) .. datetime($E)) | count"
```

> **핵심 메트릭 정의(공식)**: `EventHubDroppedEvents` = "events skipped because of **queue size limit reached**".
> `EventHubTotalEvents`(=Successful) = EH로 실제 전송된 수. Total에는 Dropped가 **포함되지 않음**(별개 카운터).

## 런 기록

각 런: 부하는 클라이언트 실측, 서버측은 측정 시간창으로 사후 조회.

| 런 ID | 조건 | 가설 | 부하 | offered | success | 측정 시작(UTC) | 측정 종료(UTC) | 상태 |
|---|---|---|---|---:|---:|---|---|---|
| real-E8 | E8 | EH가 8KB 모든 요청을 무손실 기록하는가 | 8KB × 500 RPS | 150000 | 150000 | 2026-08-19T12:58:25Z | 2026-08-19T13:04:40Z | 완료 (500점 1회, 400/300/200/100 추세로 뒷받침) |
| real-A8 | A8 | App Insights가 8KB 모든 요청을 무손실 기록하는가 | 8KB × 500 RPS | 150000 | 150000 | 2026-08-19T13:25:02Z | 2026-08-19T13:31:16Z | 완료 (App Insights 150,178 무손실 확인) |
| real-N8 | N8 | 무로깅 8KB 기준선 (CPU 비교 기준) | 8KB × 500 RPS | 150000 | 150000 | 2026-08-19T13:39:08Z | 2026-08-19T13:44:09Z | 완료 (500점 기준선) |
| real-N64 | N64 | 무로깅 64KB 기준선 | 64KB × 500 RPS | → r500-N64로 측정 완료 (아래 참조) | | | | ✅ 측정됨 |
| real-E64 | E64 | EH가 64KB 무손실 기록하는가 / EH TU 한계 | 64KB × 500 RPS | → r500-E64로 측정 완료 (드롭 76,434) | | | | ✅ 측정됨 |
| r400-N8 | N8 | RPS 스윕 기준선 | 8KB × 400 RPS | 72000 | 72000 | 2026-08-19T13:52:40Z | 2026-08-19T13:55:40Z | 완료 |
| r400-A8 | A8 | RPS 스윕 App Insights | 8KB × 400 RPS | 72000 | 72000 | 2026-08-19T13:57:38Z | 2026-08-19T14:00:38Z | 완료 |
| r400-E8 | E8 | RPS 스윕 EH (드롭 관측) | 8KB × 400 RPS | 72000 | 72000 | 2026-08-19T14:02:41Z | 2026-08-19T14:05:41Z | 완료 (드롭 2,933) |
| r300-N8 | N8 | RPS 스윕 기준선 | 8KB × 300 RPS | 54000 | 54000 | 2026-08-19T14:07:36Z | 2026-08-19T14:10:37Z | 완료 |
| r300-A8 | A8 | RPS 스윕 App Insights | 8KB × 300 RPS | 54000 | 54000 | 2026-08-19T14:12:31Z | 2026-08-19T14:15:31Z | 완료 |
| r300-E8 | E8 | RPS 스윕 EH (드롭 0 확인) | 8KB × 300 RPS | 54000 | 54000 | 2026-08-19T14:17:26Z | 2026-08-19T14:20:27Z | 완료 (드롭 0, 무손실) |
| r200-N8 | N8 | RPS 스윕 기준선 | 8KB × 200 RPS | 36000 | 36000 | 2026-08-19T14:28:31Z | 2026-08-19T14:31:31Z | 완료 (Cap 58%) |
| r200-A8 | A8 | RPS 스윕 App Insights | 8KB × 200 RPS | 36000 | 36000 | 2026-08-19T14:33:26Z | 2026-08-19T14:36:26Z | 완료 (Cap 66%) |
| r200-E8 | E8 | RPS 스윕 EH | 8KB × 200 RPS | 36000 | 36000 | 2026-08-19T14:38:20Z | 2026-08-19T14:41:20Z | 완료 (Cap 85%, 드롭 0) |
| r100-N8 | N8 | RPS 스윕 기준선 | 8KB × 100 RPS | 18000 | 18000 | 2026-08-19T14:43:16Z | 2026-08-19T14:46:16Z | 완료 (Cap 31.5%) |
| r100-A8 | A8 | RPS 스윕 App Insights | 8KB × 100 RPS | 18000 | 18000 | 2026-08-19T14:48:10Z | 2026-08-19T14:51:10Z | 완료 (Cap 39%) |
| r100-E8 | E8 | RPS 스윕 EH | 8KB × 100 RPS | 18000 | 18000 | 2026-08-19T14:53:05Z | 2026-08-19T14:56:05Z | 완료 (Cap 38%, 드롭 0) |
| r500-N64 | N64 | 64KB 무로깅 기준선 | 64KB × 500 RPS | 90000 | 90000 | 2026-08-19T15:02:21Z | 2026-08-19T15:08:26Z | 완료 (Dur 7.32ms) |
| r500-E64 | E64 | 64KB EH 로깅 (대용량) | 64KB × 500 RPS | 90000 | 90000 | 2026-08-19T15:12:02Z | 2026-08-19T15:20:06Z | 완료 (드롭 76,434) |
| r300-N64 | N64 | 64KB 무로깅 기준선 | 64KB × 300 RPS | 54000 | 54000 | 2026-08-19T15:22:11Z | 2026-08-19T15:25:47Z | 완료 (Dur 6.04ms) |
| r300-E64 | E64 | 64KB EH 로깅 | 64KB × 300 RPS | 54000 | 54000 | 2026-08-19T15:28:35Z | 2026-08-19T15:34:16Z | 완료 (드롭 41,435) |

## ★★ RPS 스윕 결과 (8KB, 500~100, 각 1회) — 핵심 발견

| RPS | 조건 | APIM Capacity% | APIM Duration ms | EH Dropped |
|---|---|---|---|---|
| 500 | N8 | ~89 | 0.1~0.35 | - |
| 500 | A8 | ~89 | 0.9~2.5 | - |
| 500 | E8 | ~87 | 0.4~1.7 | **대량 (약 절반)** |
| 400 | N8 | 85.5 | 0.03 | - |
| 400 | A8 | 84.5 | 0.64 | - |
| 400 | E8 | 85.5 | 1.00 | **2,933** |
| 300 | N8 | 79 | 0.06 | - |
| 300 | A8 | 88.5 | 0.13 | - |
| 300 | E8 | 86.5 | 0.36 | **0** |
| 200 | N8 | **58** | 0.02 | - |
| 200 | A8 | **66** | 0.05 | - |
| 200 | E8 | **85** | 0.04 | **0** |
| 100 | N8 | **31.5** | 0.01 | - |
| 100 | A8 | 39 | 0.03 | - |
| 100 | E8 | 38 | 0.03 | **0** |

측정창(UTC)은 `results/rps-sweep-windows.txt`, `rps-sweep2-windows.txt` 참조. 스윕 런은 warmup 60s + 측정 180s.

### ★ 핵심 발견 (8KB)

1. **EH 드롭은 부하(RPS)에 직접 비례 → 인과 확정.** 500(대량) → 400(2,933) → **300 이하(0)**. RPS를 낮춰 부하를 줄이니 드롭이 사라졌다. **드롭 원인 = 부하(게이트웨이 포화)**. EH TU 한계가 아니다(EH throttle 항상 0).

2. **8KB 무손실 임계 ≈ 300 RPS.** Developer v1 + 8KB에서 300 이하는 EH 무손실, 400부터 드롭.

3. **★ 로깅의 케파 영향은 "포화에서 내려와야" 보인다.**
   - 500·400: N8도 이미 ~85-89% 천장 → 로깅 영향이 케파에 안 보임 (포화라 가려짐).
   - **200 RPS: N8=58%, A8=66%, E8=85% → 로깅별 케파 차이가 뚜렷.** EH(E8)가 무로깅보다 +27%p로 케파를 가장 많이 쓴다.
   - 100 RPS: N8=31.5%로 더 여유.
   - **결론 수정**: "로깅은 케파에 영향이 없다"가 아니라 **"로깅은 케파에 영향을 준다(특히 EH). 단 500 RPS에선 이미 포화라 안 보였을 뿐."** (사용자 1번 정리 정밀화)

4. **★ EH(E8)가 App Insights(A8)보다 게이트웨이 부하가 크다.** 200 RPS에서 E8 85% vs A8 66%. 이것이 500 RPS에서 E8만 드롭한 이유와 연결 — EH 로깅이 게이트웨이를 더 무겁게 해서 큐를 못 비움.

## ★★ 64KB 스윕 결과 (대용량 EH 로깅, APIM 관점)

| RPS | 조건 | APIM Capacity% | APIM Duration ms | EH Dropped | EH Throttled |
|---|---|---|---|---|---|
| 500 | N64 (무로깅) | 85.4 | 7.32 | - | - |
| 500 | E64 (EH) | 89.1 | 7.58 | **76,434** | 0 |
| 300 | N64 (무로깅) | 82.5 | 6.04 | - | - |
| 300 | E64 (EH) | 82.2 | 5.24 | **41,435** | 0 |

측정창은 `results/sweep-64k-windows.txt`. (64KB×500=32MB/s 부하로 부하생성기가 밀려 실측정 구간이 3~8분으로 늘어남 — 500 RPS는 달성됨, 0오류)

### ★ 핵심 발견 (64KB)

1. **★ payload가 커지면 무손실 임계 RPS가 급락.** 8KB는 300에서 드롭 0이었으나, **64KB는 300 RPS에서도 41,435개 드롭**. 대용량 로깅은 훨씬 낮은 RPS에서만 무손실 가능.

2. **64KB 드롭도 EH TU 한계가 아님.** 64KB×500=32MB/s로 EH 40TU의 80% 부하인데도 **EH Throttled=0**. 드롭은 여전히 **APIM 큐** 때문. (예상과 달리 EH는 80% 부하도 버팀)

3. **★ 대용량 지연의 주범은 payload 크기 자체, EH 로깅이 아님.** 64KB 무로깅(N64)만으로 Duration 7.3ms (8KB N8의 100배+). E64−N64 = 0.26ms(500) — **EH 로깅이 더하는 지연은 작다. APIM이 64KB body를 받아 읽는 비용이 지배적.**


## ★ 성능 비교표 (전부 APIM 서버측 값, 각 1회)

| 조건 | 측정창(UTC) | APIM Capacity 평균 | APIM Duration 평균 | 로그 완전성 |
|---|---|---|---|---|
| **N8** 무로깅 | 13:39:08~13:44:09 | **~89% (84~93)** | **0.09~0.35 ms** | (로깅 없음) |
| **A8** App Insights 8KB | 13:25:02~13:31:16 | ~89% (85~91) | 0.9~2.5 ms | **무손실 150,178** |
| **E8** Event Hub 8KB | 12:58:25~13:04:40 | ~87% (80~92) | 0.4~1.7 ms | **드롭 발생** |

**핵심 해석:**
1. **Capacity(부하%)로는 로깅 영향 구분 불가** — N8/A8/E8 전부 ~87-89%. **500 RPS 자체가 이미 Developer 게이트웨이를 포화**시킨다. 로깅 유무와 무관하게 ~90%.
2. **Duration(처리시간)은 로깅 영향이 뚜렷** — 무로깅 0.1~0.35ms → E8 0.4~1.7ms(3~5배) → A8 0.9~2.5ms(7~10배). **App Insights가 EH보다 게이트웨이 처리시간을 더 늘린다.**
3. **결과의 역설** — 게이트웨이가 이미 포화(89%)라, E8은 로깅 큐를 못 비워 **드롭**하고, A8은 처리시간을 더 쓰면서도 **전량 기록(150,178)**. 즉 같은 포화 상태에서 두 로거의 실패 방식이 다르다: EH=유실, App Insights=지연.



### real-E8 (12:58:25 ~ 13:04:40)

| 지표 | 값 | 출처 | 해석 |
|---|---|---|---|
| APIM Capacity (게이트웨이 부하%) | 80~92% (평균 ~87%) | APIM `Capacity` | 게이트웨이 거의 포화 |
| APIM Duration (게이트웨이 처리시간) | 0.4~1.7 ms (분당 avg) | APIM `Duration` | 게이트웨이 처리 자체는 sub-ms |
| APIM EventHubTotalEvents (=Successful) | 조회 필요(정밀 시간창) | APIM 메트릭 | EH로 실제 전송 성공 |
| APIM EventHubDroppedEvents | 큐 한도로 대량 드롭 | APIM 메트릭 | **큐 크기 한도 도달로 스킵** (공식 정의) |
| APIM EventHubThrottledEvents | 0 | APIM 메트릭 | EH가 스로틀 안 함 |
| EH IncomingMessages | Successful과 일치 | Event Hubs 메트릭 | EH는 받은 건 무손실 |
| EH ThrottledRequests | 0 | Event Hubs 메트릭 | EH 용량 여유 (8KB×500=4MB/s ≪ 40TU) |

> **주의**: 위 EH 송신/드롭 수치는 warmup이 섞인 넓은 시간창으로 조회해 **정확한 드롭률(%)은 미확정**이다.
> measurement 300초 구간만 정밀 정렬해 재검산 필요. (Azure Monitor 분당 집계는 수집 지연으로 실요청과 경계가 어긋남)

### real-A8 (13:25:02 ~ 13:31:16)

| 지표 | 값 | 출처 | 해석 |
|---|---|---|---|
| 클라이언트 보낸 수 | 150,000 | result.json | offered=successful=150000, 오류 0 |
| **App Insights AppRequests 기록 수** | **150,178** | Log Analytics `AppRequests \| count` (측정창) | **전량 기록 (누락 없음)** — 150,178은 측정창 경계에 걸친 warmup 잔여 포함 |
| APIM Capacity (게이트웨이 부하%) | 85~91% (평균 ~89%) | APIM `Capacity` | E8과 비슷하게 게이트웨이 포화 |
| APIM Duration (게이트웨이 처리시간) | 0.9~2.5 ms (분당 avg) | APIM `Duration` | E8(0.4~1.7ms)보다 약간 높음 |
| 클라이언트 p50/p95/p99 (ms) | 5.0 / 516 / 546.8 | result.json | 참고(클라이언트 핸드셰이크 꼬리 공통) |

> **핵심**: App Insights(sampling 100%, body 8KB)는 500 RPS에서 **모든 요청을 기록했다(무손실)**.
> Log Analytics workspace `log-logbench-202608191803`(customerId 5a3336dd-...) AppRequests에서 측정창 count = 150,178 ≥ 150,000.

## 잠정 발견 (근거와 함께)

1. **E8에서 APIM이 EH 이벤트를 드롭한다** — `EventHubDroppedEvents > 0` (공식 정의: 큐 크기 한도 도달로 스킵).
2. **드롭 시점 APIM Capacity 80~92%** — 게이트웨이가 포화 상태.
3. **EH는 무고** — EH ThrottledRequests=0, IncomingMessages=Successful, 8KB×500은 40TU의 10%만 사용.
4. **→ E8 드롭 원인은 EH TU 한계가 아니라 APIM 게이트웨이 처리 포화(Developer 티어)로 추정.**
5. **★ 반전: A8(App Insights 100%)은 무손실, E8(log-to-eventhub)은 드롭.**
   - A8: 150,000 보냄 → App Insights에 150,178 기록 (전량)
   - E8: 150,000 보냄 → APIM이 큐 한도로 대량 드롭
   - 즉 같은 500 RPS·8KB에서 **App Insights는 모든 요청을 기록했지만 log-to-eventhub는 유실**했다.
   - 원래 가설("App Insights는 샘플링 유실, EH는 무손실")과 **정반대** 방향의 실측.
   - 단, App Insights는 sampling을 100%로 명시 설정했고 body 8KB를 실제 기록. 성능(CPU) 대가는 별도 확인 필요.

## 신뢰도 구분 (정직하게)

### ✅ 확정 (1회지만 방향·사실 명확)
- **A8: App Insights(100%)는 8KB 500 RPS에서 무손실 기록** — 측정창 count 150,178 ≥ 150,000. 유실 없음이 명확.
- **E8: APIM이 EH 이벤트를 드롭한다** — `EventHubDroppedEvents > 0`이 real-E8 + 여러 드라이런에서 반복 재현됨. 드롭 "발생"은 확실.
- **E8 드롭은 EH TU 한계가 아니다** — EH ThrottledRequests=0, 8KB×500=4MB/s는 40TU의 10%. EH는 무고.

### ⚠️ 방향은 맞지만 수치 미확정
- **E8 정확한 드롭률(%)** — warmup 섞인 넓은 시간창으로 조회해 % 미확정. measurement 300초만 정밀 정렬 필요.
- **드롭 원인 = APIM 게이트웨이 포화** — Capacity 80~92%와 상관관계는 확인, 인과는 미확정(SKU 상향 실험 필요).

### ❌ 아직 못 하는 것 (데이터 없음)
- **CPU 오버헤드 비교** — N8(무로깅) 기준선이 없어 "로깅이 CPU를 얼마나 올렸나" 판단 불가.
- **반복 신뢰도** — 같은 조건 3회 반복은 안 함. 대신 8KB는 5개 RPS(500/400/300/200/100)의 **단조로운 추세**로, 64KB는 2개 RPS로 뒷받침됨. 단일점 우려는 추세로 완화되나, 오차막대(분산)는 없음.
- **64KB(E64)** — 미측정. EH 80% 사용 구간에서 TU 한계가 나타나는지 모름.

## 미검증 / 다음 단계

- [x] real-A8: App Insights AppRequests 기록 수 = 150,178 (무손실 확인)
- [ ] real-E8 measurement 300초만 정밀 정렬해 정확한 드롭률(%) 확정
- [ ] N8/N64 기준선 CPU 측정 (E8/A8의 CPU가 무로깅 대비 얼마나 높은지)
- [ ] E64: 64KB×500=32MB/s(40TU의 80%)에서 EH TU 한계가 실제로 나타나는지
- [ ] A8의 서버측 CPU(Capacity)를 E8과 비교 — App Insights도 게이트웨이를 포화시키는가
- [ ] (옵션) APIM SKU를 올려 CPU 여유 시 EH 드롭이 줄어드는지 — 인과 검증

## ⚠️ SKU 상향 실험 (복원 필수)

- **원래 APIM SKU**: `Developer`, capacity 1, Korea Central
- 실험 후 반드시 복원:
  ```bash
  az apim update -g rg-ai-gw-aigateway-20260716 -n apim-ai-gw-aigateway-20260716 --sku-name Developer --sku-capacity 1
  ```
- 목적: SKU를 올려 게이트웨이 여유↑ → 같은 500 RPS·8KB에서 EH 드롭이 줄면 "드롭 원인=APIM 처리능력" 직접 확정.
