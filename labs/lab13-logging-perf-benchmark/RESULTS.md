# Lab 13 — 로깅 성능/용량 벤치마크: 실험 설계서 (v2, 재실험용)

> **상태**: 설계 리뷰 단계. 지금까지의 실측·시행착오를 반영한 **가설 + 조건**을 먼저 확정하고, 리뷰 후 전체를 재실험한다. (v1 결과·이전 리포트는 [`old/`](old/) 참조 — 초기 "−26%"는 재현 실패로 판명, CPU% 메커니즘은 확인, 8KB 고정이라 EH 본질 미측정 등.)

---

## 0. 왜 다시 하나 (v1에서 배운 것)

| v1에서 드러난 문제 | v2에서 통제 |
|---|---|
| 단발·저부하 측정이 노이즈에 취약 (초기 −26%가 재현 안 됨) | **워밍업 + 순서 균형 + 반복** |
| 저부하는 게이트웨이 CPU 미포화라 로깅 비용 안 보임 | **CPU% 관측 + 포화까지 부하** |
| **payload(데이터 본문)를 8KB로 고정** → App Insights(8KB 상한)와 EH가 동일량 → EH의 존재 이유 미측정 | **body(본문) 크기 스윕(단계별 변화, 8→200KB)**, EH는 전량 기록 |
| 로그가 실제로 기록됐는지 내용 미검증 | **App Insights body 길이 + EH 소비**로 내용 검증 |
| EH 수신·스로틀 메트릭을 삭제 전에 못 챙김 | **삭제 전 EH 메트릭 캡처** 절차화 |
| 절대 throughput(처리량)이 클라이언트 동시성/네트워크에 제한 | 서버측 **CpuPercent_Gateway·TotalTime**을 권위 지표로 |

---

## 1. 목적

APIM 게이트웨이에서 **로깅 구성(감사 방식)이 성능·용량에 미치는 영향**을, 특히 **payload 용량이 커질 때 App Insights(8KB 상한)와 Event Hub(무손실, 200KB)의 방향성 차이**를 실측으로 규명한다.

## 2. 구성 (무엇을 로깅하나)

| 구성 | 로깅 방식 | body ≤ 8KB | body > 8KB |
|------|-----------|-----------|-----------|
| **C1** | 로깅 없음 (applicationinsights 진단 삭제) | 없음 | 없음 |
| **C2** | App Insights + 응답 body (상한 8KB) | 전량(=body) | **8KB만 (잘림·유실)** |
| **C3** | App Insights body=0(메타) + `log-to-eventhub`(전량, ≤200KB) | 전량(=body) | **전량 (무손실)** |

- 대상: `bench` API — `return-response` mock(백엔드 없음)으로 `?bytes=N` 크기 응답 생성.
- C2·C3는 **동일 payload를 서로 다른 sink(로그 저장 대상)**로 보냄. **차이는 8KB 초과 구간에서 발현**된다.

## 3. 가설

- **H1 (확정됨, v1)**: 로깅 오버헤드는 단건 레이턴시가 아니라 **부하/CPU 현상**이다. 단건 서버측 `TotalTime`은 0~1ms(sub-ms).
- **H2 (부분 확인, v1)**: App Insights body 로깅(C2)은 부하 시 **게이트웨이 CPU를 더 쓴다**(v1: +12.5%p @ CPU 65→77.5%). → v2에서 재확인.
- **H3 (미검증)**: 그 CPU 비용은 **게이트웨이 CPU 포화 시 throughput 저하**로 이어진다(문서 "40~50%↓@>1000rps"). → v2에서 포화까지 밀어 검증.
- **H4 (확정됨, v1)**: **8KB에서는 C2≈C3**(동일 payload). CPU도 유사(C3가 약간 낮음).
- **H5 (핵심, 미검증)**: **body>8KB에서 C2는 8KB로 잘리고(유실), C3는 전량 무손실**로 기록한다. → 내용 검증으로 실증.
- **H6 (핵심, 미검증)**: **body 용량이 커질수록 C3(EH)의 비용이 증가**한다. EH Standard 1 TU = 1MB/s 한계라, `body × RPS`가 이를 넘으면 **EH Throttle/Drop 발생**(무손실의 대가·한계). C2는 8KB 상한이라 body가 커져도 로깅 비용은 평탄.
- **H7 (내용 검증)**: 각 구성은 **의도한 로그만** 남긴다 — C1 없음 / C2 정확히 8192B / C3 전량(body 크기만큼).

## 4. 변수 & 조건

> **부하 조건 · 반복 횟수 · SKU 사전 리뷰의 확정본은 [`TEST-SPEC.md`](TEST-SPEC.md)** 에 있다(재실험 착수 게이트). 아래는 요약.

### 4.1 body 크기 스윕 (핵심 축)
`[8KB(8192), 32KB(32768), 64KB(65536), 128KB(131072), 200KB(204800)]`
- 8KB = 기준선(C2·C3 동일). 이후는 C2 잘림 vs C3 전량이 갈리는 구간.

### 4.2 부하 조건 (구체) — 두 프로파일

ALT는 **closed-model(고정 동시성 방식)**로 VU(가상 사용자 수)를 고정하므로 RPS = 동시성 ÷ 응답시간이다. 정확한 RPS 고정은 불가 → **동시성을 고정하고 달성 RPS를 기록**한다. 매 측정은 steady-state(부하가 안정된 측정 구간)만 집계하고 ramp(부하 증가 구간)는 제외하며, 워밍업 런 1회는 폐기한다.

**프로파일 A — CPU 포화 (H2·H3, body=8KB 고정)**
- 목적: 게이트웨이 CPU를 포화(≥90%)까지 밀어 로깅 CPU 비용이 throughput에 미치는 영향 관측.
- **knee(기준 부하) 탐색(1회씩)**: 엔진 × threads = 동시성을 계단식으로 — `2×250(500)` → `4×250(1000)` → `6×250(1500)`, ramp 30s, duration 120s. 각 단계 CPU%·성공RPS·오류%·p95 기록 → **CPU가 포화되며 성공RPS가 평탄해지고 오류<5%인 knee(기준 부하) 지점** 확정.
- **본 측정**: 확정된 knee(기준 부하) 동시성에서 C1/C2/C3 각 **R회**(§4.3), 워밍업+균형순서.

**프로파일 B — EH 대용량 방향성 (H5·H6, body 스윕)**
- body: `8/32/64/128/200 KB`, **동시성 고정 1엔진 × 100 threads**, ramp 20s, duration 90s.
- EH 1 TU(Throughput Unit, 처리량 단위)=1MB/s 대비 예상 대역폭(달성 RPS는 응답시간에 따라 변동, 실측 기록):
  | body | 100 rps 가정 대역폭 | 1 TU(1MB/s) 대비 |
  |---|---|---|
  | 8KB | 0.8 MB/s | 여유 |
  | 32KB | 3.2 MB/s | 초과(≈3×) |
  | 64KB | 6.4 MB/s | 초과(≈6×) |
  | 128KB | 12.8 MB/s | 초과(≈13×) |
  | 200KB | 20 MB/s | 초과(≈20×) |
- 관측: 각 body에서 **C3의 EH Throttled/Dropped/BytesSent + CPU% + 성공RPS**. C2는 8KB 상한이라 대조(평탄) — 각 body에서 C2도 측정.
- **EH 용량 변수(중요)**: 기본 **1 TU·auto-inflate(처리량 단위 자동 확장) OFF**(=한계를 명확히 보여줌). 선택적으로 **auto-inflate ON(≤20 TU) 또는 파티션↑** 한 세트를 더 돌려 "스케일 vs 한계"를 대조.

### 4.3 반복 & 순서 (구체)
- **반복 R = 3회** / (구성 × 부하셀). 편차가 크면(범위 > 평균의 15%) **R=5로 증량**.
- **순서 균형**: 정순·역순 교차. 예 3회: `C1C2C3` · `C3C2C1` · `C1C2C3`(각 구성이 1·2·3번 위치를 고루 경험).
- **워밍업**: 배포 직후 1회(폐기). 구성 전환 시 **전파 대기 90~150s**.
- **단일 워밍업된 게이트웨이**에서 구성만 토글(배포 편차 상수화).
- **보고**: 구성별 **mean ± (min/max)**. 이상치(콜드 등)는 표시하되 **제외 시 근거 명시**.

### 4.4 실행 예산 (리뷰용 — 시간/비용 가늠)
- 프로파일 A: knee(기준 부하) 탐색 3 + 본측정 3구성×3회 = **~12 런**.
- 프로파일 B: 5크기 × (C2,C3) × 3회 = 30 + C1 기준 몇 = **~33 런** (+ auto-inflate 대조 세트 시 추가).
- 런당 ~4~6분(엔진 기동 포함) → **A+B ≈ 45런 ≈ 3~4시간 + 배포**. ⚠️ ALT VUH·APIM·EH 시간당 과금.
- **축소 옵션**(리뷰에서 선택): body를 3개(8/64/200KB)로, R=2로 → ~20런 ≈ 1.5~2시간.

## 5. 측정 지표

| 축 | 지표 | 출처 |
|----|------|------|
| 게이트웨이 CPU | `CpuPercent_Gateway` (max/avg, 구성×크기 윈도우) | Azure Monitor (APIM) |
| 단건 처리시간 | `TotalTime − BackendTime` | `ApiManagementGatewayLogs` (Dedicated) |
| 처리량 | **성공 RPS**(Total−Errors), p95, 오류% | `az load test-run metrics list` |
| **EH 방향성** | `EventHubTotalEvents`·`SuccessfulEvents`·**`ThrottledEvents`·`DroppedEvents`**·`TotalBytesSent` | Azure Monitor (APIM) — **삭제 전 캡처** |
| **내용 검증** | App Insights `Response-Body` 길이 분포 (C1 없음/C2 8192/C3 0) | `AppRequests`(Properties) |
| **내용 검증** | EH 실제 메시지 크기 (전량 담겼는지) | **Event Hub 소비**(azure-eventhub SDK, 사용자 Data Receiver 역할) |

## 6. 측정 격리 원칙 (백엔드·네트워크 배제)
- **백엔드 제거**: `return-response` → `BackendTime≈0`(데이터로 확인).
- **네트워크 배제**: 권위 지표는 서버측 `CpuPercent_Gateway`·`TotalTime`(클라이언트↔APIM RTT 무관).
- **중립 자**: GatewayLogs 진단을 **Dedicated(resource-specific)** 로 전 구성 상시 ON(상쇄).

## 7. 로그 내용 검증 절차 (삭제 전 필수)
1. C2 소량 호출(큰 body) → `AppRequests`에서 `Response-Body` 길이 = **8192(잘림)** 확인.
2. C3 소량 호출(큰 body) → **Event Hub 소비** → 메시지 크기 = **body 전량** 확인.
3. C1 → App Insights에 요청 **없음** 확인(GatewayLogs엔 존재).
4. EH `Throttled/Dropped/BytesSent` 메트릭을 **teardown 전에** 캡처.

## 8. 알려진 함정 & 통제 (v1 실측으로 확보)
- **리전**: `japaneast` (koreacentral은 Azure Load Testing 미지원).
- **EH SAS 비활성 테넌트**: 이 테넌트는 Azure Policy로 EH `disableLocalAuth=true`를 강제한다. **두 가지 우회**:
  - (기본, 검증됨) **MI 로거 + "Azure Event Hubs Data Sender" 역할** — SAS 불필요, 더 안전. 배포 스크립트가 RBAC 전파 후 재시도 등록.
  - (더 단순) EH 네임스페이스(및 RG)에 **태그 `SecurityControl = Ignore`** → 폴리시 우회로 **SAS 유지** → bicep-native **연결문자열 로거**(후처리 불필요, 한 방 배포). ⚠️ 태그는 **리소스 생성 시점**에 있어야 정책이 통과된다.
- **GatewayLogs 타이밍**: 진단이 기본 `AzureDiagnostics`면 `TotalTime` 없음 → **Dedicated** 필수.
- **az load 특성**: `--env`는 환경변수(JMX는 `System.getenv`로 읽음), `--wait` 미지원(기본 대기), 집계는 `testRunStatistics`(null) 대신 **`metrics list`**.
- **yaml**: 빈 `userPropertyFile` 금지(경로 `.` 오인).
- **EH 용량**: Standard 1 TU=1MB/s. 큰 body 실험에서 **auto-inflate 여부/파티션 수**를 변수로 고려(H6 해석에 필요).
- **삭제 전 캡처**: APIM/EH 삭제 시 플랫폼 메트릭 접근 불가 → **측정 직후 캡처**. (LA는 14일 soft-delete로 사후 복구 가능.)
- **StandardV2**: `gatewayUrl` 출력이 비어올 수 있어 `<name>.azure-api.net`로 보정.

## 9. 이상치/교란 변수 사전 분석 (EH · Load Testing · APIM SKU)

측정 전에 **어떤 설정이 이상치를 만들 수 있는지**를 열거하고 통제 방법을 고정한다. (v1의 노이즈 대부분이 아래에서 왔다.)

### 9.1 Event Hub
| 변수 | 이상치 시나리오 | 통제 |
|------|----------------|------|
| **Auto-inflate(처리량 단위 자동 확장)** | 테스트 중 TU가 1→N으로 자동 증가 → **용량이 실험 중 변함**(초반 throttle(처리 제한), 후반 해소) | **OFF 고정**(기본). H6는 고정 용량에서. 스케일 대조는 별도 세트로 명시적 |
| **TU(capacity, 처리 용량)** | 1 TU=1MB/s. 큰 body에서 즉시 throttle(처리 제한) → C3 비교 왜곡 | **1 TU 고정**(한계 관측). 별도 세트로 20 TU 대조 |
| **파티션 수** | 파티션 적으면 병렬성 병목 | 4 파티션 고정, 값 기록 |
| **로거 `isBuffered`** | 버퍼링 on/off로 배치·throttle·CPU 거동 변화 | 값 고정(기본 on) + 기록 |
| **partition-key** | 정책에 지정 시 특정 파티션 쏠림 | 미지정(라운드로빈) |
| **메시지 200KB 상한** | 200KB 초과분 자동 절단 → "전량"이 아님 | body ≤ 200KB로 스윕 상한 설정 |

### 9.2 Azure Load Testing (ALT)
| 변수 | 이상치 시나리오 | 통제 |
|------|----------------|------|
| **엔진 콜드스타트(초기 기동 지연)** | 첫 런이 느림(v1 3회차 C1 이상치) | **워밍업 런 폐기** |
| **Auto-stop(오류율)** | 오류>90%/60s 시 런 자동 중단 → 데이터 카오스(v1 과부하) | 부하를 auto-stop 미만으로, 또는 **failureCriteria/auto-stop 완화** 후 오류율 지표로 별도 해석 |
| **Closed-model(고정 동시성 방식)** | 고정 VU라 RPS=동시성/응답. 응답↑(큰 body)면 RPS 자연 감소 → "고정 RPS" 착시 | 동시성 고정 + **달성 RPS 실측** |
| **엔진 병목** | 엔진이 부족하면 클라이언트-바운드(부하 생성기가 한계인 상태)가 되어 게이트웨이가 미포화 → 로깅 효과 안 보임(v1) | knee(기준 부하) 탐색으로 게이트웨이-바운드(게이트웨이가 한계인 상태) 확인, 필요 시 엔진↑ |
| **ramp(부하 증가) 구간** | ramp 중 부분 부하가 평균을 오염 | **steady-state(안정 상태) 윈도우만** 집계 |
| **분당 버킷/`testRunStatistics` null** | 집계 지표 누락 | `metrics list` 시계열 사용 |

### 9.3 APIM SKU (StandardV2)
| 변수 | 이상치 시나리오 | 통제 |
|------|----------------|------|
| **Autoscale** | 유닛이 실험 중 1→N 자동 증가 → **용량 변동**으로 CPU%/throughput 급변 | **capacity 1 고정, autoscale 규칙 없음** 확인 |
| **배포별 유닛 편차** | 배포마다 다른 하드웨어 → 배포 간 성능 차(v1 0818e가 전반적으로 느림) | **단일 게이트웨이에서 구성만 토글**(배포 편차 상수화) |
| **콜드/JIT** | 배포·구성변경 직후 느림 | 워밍업 + 전파 대기 |
| **플랫폼 rate-limit(429)** | 극한 부하에서 config 무관 429 → 오류 해석 오염 | 오류를 config-window별로 분리, auto-stop 미만 유지 |
| **진단 sampling** | sampling<100%면 telemetry량(=CPU)↓ | **100% 고정**(전 구성 동일) |
| **capacity 메트릭명** | classic=`Capacity`, v2=`CpuPercent_Gateway` | v2 메트릭명 고정 사용 |

### 9.4 공통(cross-cutting)
- **전파 지연**(정책/진단 ~1-2분), **수집 지연**(LA/AI ~2-5분) → 변경 후 대기, 조회 재시도.
- **단일 리전(japaneast)**·**동일 세션 시간대**로 네트워크·noisy-neighbor(공유 인프라의 이웃 부하) 변동 최소화.
- **GatewayLogs Dedicated** 미설정 시 `TotalTime` 없음.

## 10. 실행 순서 (재실험)
1. 배포(0818x) — 수정된 `deploy-logbench.sh`(MI 로거 자동, Dedicated 진단, RG/EH `SecurityControl=Ignore` 태그).
2. 사용자에게 EH **Data Receiver** 역할 부여(소비용).
3. **내용 검증**(§7): 64KB로 C2 잘림·C3 전량(EH 소비) 확인.
4. **CPU 포화 실험**(§4.2 A): knee(기준 부하) 탐색 후 C1/C2/C3, CPU% 관측(H2·H3).
5. **EH 방향성 스윕**(§4.2 B): body 8→200KB, C3의 CPU·throughput·**EH Throttle/Drop/Bytes**(H5·H6).
6. **삭제 전** EH·CPU 메트릭 캡처 → 분석.
7. teardown(RG 삭제) + APIM purge.

## 10. 결과 (v2 재실험 — 2026-08-18, 배포 `v2a`, japaneast, StandardV2·EH Standard 1TU/inflate off/4part)

### 10.1 내용 검증 (64KB 요청) ✅ 핵심
| 구성 | App Insights `Response-Body` 길이 | EH 실제 메시지(소비 확인) |
|------|:---:|:---:|
| C1 | (없음) | — |
| C2 App Insights | **8192 (=8KB로 잘림)** × 15 | — |
| C3 Event Hub | **0** × 15 | **8192·65536 전량**(EH 소비로 확인) |

→ **64KB 요청에서 C2는 8KB로 잘려 유실(H5의 App Insights 측), C3는 EH에 전량(8192/65536) 무손실 저장** — EH를 쓰는 이유(8KB 초과 무손실)를 **직접 실증**. App Insights EventHub 송신 메트릭(`EventHubTotalBytesSent`)은 수집 지연/집계로 0이었으나, **EH를 직접 소비해 body 전량 저장을 확정**.

### 10.2 CPU 포화 (프로파일 A, body 8KB, knee(기준 부하)=4×250)
knee(기준 부하) 탐색: 2×250→CPU32%/1322rps · 4×250→CPU61%/2695rps · 6×250→CPU61%/4100rps (CPU가 ~61%에서 정체 = 이 mock(모의 응답) 워크로드는 게이트웨이를 60%대까지만 사용).

| 구성 | CPU% max (2런 균형) | 개별 런 | 성공 RPS |
|------|:---:|:---:|---:|
| **C1** 무로깅 | **66.5%** | 65 / 68 | 2539 |
| **C2** App Insights 8KB | **74.5% (+8.0%p)** | 79 / 70 | 2759 |
| **C3** body=0 + EH | 67.5% (+1.0%p) | 69 / 66 | 2820 |

→ **H2 재확인**: App Insights body 로깅(C2)이 게이트웨이 CPU를 C1보다 **+8%p** 더 씀(v1 +12.5%p와 방향 일치, 워밍업·균형순서 적용). **C3는 C1과 사실상 동등(+1%p)** — `log-to-eventhub` 비동기라 게이트웨이 CPU 부담 거의 없음(사용자 통찰 실증).

### 10.3 EH 대용량 방향성 (프로파일 B, body 8/64/200KB, 1×100)
| body | C1 CPU% / RPS | C2 CPU% / RPS | **C3 CPU% / RPS** | EH thr/drop |
|------|:---:|:---:|:---:|:---:|
| 8KB | 17 / 653 | 18 / 553 | **21 / 521** | 0 / 0 |
| 64KB | 17 / 492 | 24 / 540 | **26 / 598** | 0 / 0 |
| 200KB | 25.5 / 458 | 29 / 453 | **37 / 388** | 0 / 0 |

→ **H6 방향성 확인**: **body가 커질수록 C3(EH)의 CPU 비용이 가장 가파르게 증가**(21→26→**37%**). 200KB에서 C3 CPU가 최고(37%)이고 RPS 최저(388) — `log-to-eventhub`가 200KB 전량을 인라인(요청 처리 중) 직렬화·전송하는 비용. 반면 **C2는 8KB 상한이라 body가 커져도 로깅 몫은 평탄**(CPU 18→24→29는 주로 응답 전송 자체 비용).
→ **EH throttle/drop(처리 제한/유실) = 0 (전 구간)**: 이 부하(1×100, ~400-600rps)에선 200KB×RPS가 1TU(1MB/s)를 넘겼을 것으로 추정되나 **버퍼링·재시도로 유실 없이 흡수**. 더 센 부하에선 throttle(처리 제한) 가능(미도달).

### 10.4 판정표 (가설별)
| 가설 | 판정 | 근거 |
|------|------|------|
| H1 단건 sub-ms | ✅ 확정 | (v1) TotalTime 0~1ms |
| H2 C2가 CPU 더 씀 | ✅ **재확인** | A: +8%p (v1 +12.5%p) |
| H3 CPU 비용→throughput 붕괴 | ⚠️ 미도달 | CPU가 ~61-75%에서 정체(100% 미포화), mock이 게이트웨이를 그만큼만 씀 |
| H4 8KB에서 C2≈C3 | ✅ 확정 | B 8KB: CPU 18 vs 21, 근접 |
| **H5 body>8KB: C2 잘림·C3 무손실** | ✅ **확정(핵심)** | 내용검증: C2=8192, C3=EH에 8192/65536 전량 |
| **H6 body↑ → C3 비용↑** | ✅ **방향성 확인** | B: C3 CPU 21→26→37%, RPS 521→598→388 |
| H7 의도한 로그만 | ✅ 확정 | C1 없음/C2 8192/C3 0 (App Insights) + EH 전량 |

### 10.4.1 C3 성능 판정 — **성능 향상은 없다**
질문: "C3는 성능 관점에서 이득이 있는가?" → **본 실험의 모든 결과로 볼 때 C3의 성능 향상은 없다.** 성능축에서 로깅은 비용이지 이득이 아니며, 어떤 로깅 구성도 무로깅(C1)을 이길 수 없다. 세 단계로 정리:

1. **무로깅(C1) 대비: 향상 0.** C3도 C1 대비 **+1%p CPU**(A: 66.5→67.5). "C3를 켜서 빨라진다"는 성립 불가.
2. **C2 대비: 조건부 "덜 나쁨"이며 견고하지 않음.**

   | 조건 | C2 | C3 | C3 우위? |
   |------|:---:|:---:|:---:|
   | 8KB·포화 (Profile A) | 74.5% | 67.5% | ✅ CPU −7%p (비동기 디커플링) |
   | 8KB·저부하 (Profile B) | 18% | 21% | ❌ C3가 더 씀 |
   | 64KB (Profile B) | 24% | 26% | ❌ C3가 더 씀 |
   | 200KB (Profile B) | 29% | **37%** | ❌❌ C3가 훨씬 더 씀 |

   - 작은 body(≤8KB)·포화에서만 C3가 C2보다 CPU 절약(async, 게이트웨이 back-pressure 없음).
   - **큰 body(>8KB)에서는 오히려 C3가 C2보다 CPU를 더 씀** — C2는 8KB에서 잘라 멈추지만(로깅 몫 평탄) C3는 전량(≤200KB)을 인라인 직렬화·전송.
   - **같은 8KB인데 Profile A(C3<C2)와 Profile B(C3>C2)가 상반** → C3의 CPU 우위는 로드 조건 의존적, 견고하지 않음.
3. **CPU를 아꼈어도 throughput/latency 개선으로 "측정"되지 않음.** A에서 C3가 C2 대비 CPU 8%p를 아꼈으나, 시스템이 CPU-bound가 아니라 동시성·네트워크 한계라 성공 RPS는 노이즈 범위 내 혼재(2539/2759/2820, H3 미도달).

→ **종합**: C3의 정당화는 **성능이 아니라 역량**(무손실·200KB·샘플링 무관·감사). 순수 성능만 보면 C3는 잘해야 "작은 body·포화 한정 C2보다 CPU 덜 씀"(측정된 throughput 이득 없음), 나쁘면 "큰 body에서 C2보다 CPU 더 씀". **무로깅 대비 개선은 0.**

### 10.5 한계
- **CPU 완전 포화(100%) 미도달**: mock `return-response`는 게이트웨이를 60-75%까지만 사용 → 문서의 "throughput 40~50%↓"(완전 포화 전제)는 여전히 미검증(H3). 실백엔드·더 무거운 정책이면 포화 가능.
- **EH throttle 미발생**: 우리 부하로는 EH 1TU를 유실까지 몰지 못함(버퍼가 흡수). "무손실의 대가=drop"은 더 센 부하 필요.
- **EH 200KB 소비 샘플 미확보**: 소비 배치 타이밍상 8192·65536만 잡힘(200KB는 log-to-eventhub 200KB 상한 이내라 전송은 됨).
- **성공 RPS 노이즈**: 프로파일 B는 1엔진·소규모라 RPS 절대값 변동 존재. CPU%가 더 안정적 지표.

### 10.5.1 공식 문서 근거 (C2 vs C3 성능 서술의 비대칭)
**C2와 C3를 직접(head-to-head) 벤치마크한 공식 문서는 없다.** 그러나 성능 저하 경고가 **오직 C2/App Insights 문서에만** 붙어 있고, C3/Event Hub 문서는 정반대로 포지셔닝된다 — 이 **서술의 비대칭 자체**가 우리 실측(C2 CPU +8%p·8KB 잘림 vs C3 +1%p·무손실)과 방향이 일치한다.

| 근거 | C2 (App Insights) | C3 (Event Hub) |
|------|---|---|
| 성능 경고 | ✅ **명시**: "internal load tests, **40%–50% reduction in throughput** when request rate exceeded **1,000 requests per second**" | ❌ 없음. 오히려 "**millions of events per second**", "**decouples** production from consumption"(비동기) |
| body 로깅 | "**might significantly decrease the performance**" → "To improve performance issues, **skip … Body logging**" | log-to-eventhub: "**not affected by … sampling. All invocations … will be logged**"(무손실) |
| 손실/상한 | 샘플링으로 **의도적 유실** 전제, body **8KB** | 샘플링 무관 전량, 메시지 **200KB** |
| 감사 적합성 | "**not** intended to be an audit system. **Not suited for logging each individual request for high-volume APIs**" | "highly scalable data ingress service" (감사·오프라인 분석용) |

**출처**
- [Integrate APIM with Application Insights — "Performance implications and log sampling"](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-app-insights#performance-implications-and-log-sampling): "40%–50% reduction in throughput … over 1,000 rps", "skip … Body logging", "not intended to be an audit system"
- [`log-to-eventhub` policy reference — Usage notes](https://learn.microsoft.com/en-us/azure/api-management/log-to-eventhub-policy): "not affected by Application Insights sampling. All invocations … logged", "maximum … message size … is 200 KB"
- [How to log events to Azure Event Hubs](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-log-event-hubs): "ingest millions of events per second", "decouples the production … from the consumption"

**단, 정직하게**: 문서의 "-40~50% throughput"은 **완전 포화(>1000rps)** 전제이고, 본 실험은 mock이 게이트웨이를 60-75%까지만 써서 그 **수치(크기)는 미재현**(H3, §10.5). **저하 방향**은 문서·실측 일치, **크기**는 본 환경 미검증.

### 10.6 산출물
- **HTML 리포트**: [`report.html`](./report.html) — 자체완결(인라인 SVG, Clawpilot 테마), 위 결과 시각화
- **차트(PNG)**: [`v2-assets/verify.png`](./v2-assets/verify.png) (내용검증), [`v2-assets/A-cpu.png`](./v2-assets/A-cpu.png) (CPU 포화), [`v2-assets/B-directionality.png`](./v2-assets/B-directionality.png) (EH 방향성)
- **v1 아카이브**: [`old/`](./old/) — 2026-08-18 이전 단건 측정 결과
