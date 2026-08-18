# Lab 13 — 로깅 성능/용량 벤치마크: 실험 설계서 (v2, 재실험용)

> **상태**: 설계 리뷰 단계. 지금까지의 실측·시행착오를 반영한 **가설 + 조건**을 먼저 확정하고, 리뷰 후 전체를 재실험한다. (v1 결과·이전 리포트는 [`old/`](old/) 참조 — 초기 "−26%"는 재현 실패로 판명, CPU% 메커니즘은 확인, 8KB 고정이라 EH 본질 미측정 등.)

---

## 0. 왜 다시 하나 (v1에서 배운 것)

| v1에서 드러난 문제 | v2에서 통제 |
|---|---|
| 단발·저부하 측정이 노이즈에 취약 (초기 −26%가 재현 안 됨) | **워밍업 + 순서 균형 + 반복** |
| 저부하는 게이트웨이 CPU 미포화라 로깅 비용 안 보임 | **CPU% 관측 + 포화까지 부하** |
| **payload를 8KB로 고정** → App Insights(8KB 상한)와 EH가 동일량 → EH의 존재 이유 미측정 | **body 크기 스윕(8→200KB)**, EH는 전량 기록 |
| 로그가 실제로 기록됐는지 내용 미검증 | **App Insights body 길이 + EH 소비**로 내용 검증 |
| EH 수신·스로틀 메트릭을 삭제 전에 못 챙김 | **삭제 전 EH 메트릭 캡처** 절차화 |
| 절대 throughput가 클라이언트 동시성/네트워크에 제한 | 서버측 **CpuPercent_Gateway·TotalTime**을 권위 지표로 |

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
- C2·C3는 **동일 payload를 서로 다른 sink**로 보냄. **차이는 8KB 초과 구간에서 발현**된다.

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

ALT는 **closed-model**(고정 VU)이라 RPS = 동시성 ÷ 응답시간. 정확한 RPS 고정은 불가 → **동시성을 고정하고 달성 RPS를 기록**한다. 매 측정은 steady-state만(ramp 구간 제외), 워밍업 런 1회 폐기.

**프로파일 A — CPU 포화 (H2·H3, body=8KB 고정)**
- 목적: 게이트웨이 CPU를 포화(≥90%)까지 밀어 로깅 CPU 비용이 throughput에 미치는 영향 관측.
- **knee 탐색(1회씩)**: 엔진 × threads = 동시성을 계단식으로 — `2×250(500)` → `4×250(1000)` → `6×250(1500)`, ramp 30s, duration 120s. 각 단계 CPU%·성공RPS·오류%·p95 기록 → **CPU가 포화되며 성공RPS가 평탄해지고 오류<5%인 지점(knee)** 확정.
- **본 측정**: 확정된 knee 동시성에서 C1/C2/C3 각 **R회**(§4.3), 워밍업+균형순서.

**프로파일 B — EH 대용량 방향성 (H5·H6, body 스윕)**
- body: `8/32/64/128/200 KB`, **동시성 고정 1엔진 × 100 threads**, ramp 20s, duration 90s.
- EH 1 TU=1MB/s 대비 예상 대역폭(달성 RPS는 응답시간에 따라 변동, 실측 기록):
  | body | 100 rps 가정 대역폭 | 1 TU(1MB/s) 대비 |
  |---|---|---|
  | 8KB | 0.8 MB/s | 여유 |
  | 32KB | 3.2 MB/s | 초과(≈3×) |
  | 64KB | 6.4 MB/s | 초과(≈6×) |
  | 128KB | 12.8 MB/s | 초과(≈13×) |
  | 200KB | 20 MB/s | 초과(≈20×) |
- 관측: 각 body에서 **C3의 EH Throttled/Dropped/BytesSent + CPU% + 성공RPS**. C2는 8KB 상한이라 대조(평탄) — 각 body에서 C2도 측정.
- **EH 용량 변수(중요)**: 기본 **1 TU·auto-inflate OFF**(=한계를 명확히 보여줌). 선택적으로 **auto-inflate ON(≤20 TU) 또는 파티션↑** 한 세트를 더 돌려 "스케일 vs 한계"를 대조.

### 4.3 반복 & 순서 (구체)
- **반복 R = 3회** / (구성 × 부하셀). 편차가 크면(범위 > 평균의 15%) **R=5로 증량**.
- **순서 균형**: 정순·역순 교차. 예 3회: `C1C2C3` · `C3C2C1` · `C1C2C3`(각 구성이 1·2·3번 위치를 고루 경험).
- **워밍업**: 배포 직후 1회(폐기). 구성 전환 시 **전파 대기 90~150s**.
- **단일 워밍업된 게이트웨이**에서 구성만 토글(배포 편차 상수화).
- **보고**: 구성별 **mean ± (min/max)**. 이상치(콜드 등)는 표시하되 **제외 시 근거 명시**.

### 4.4 실행 예산 (리뷰용 — 시간/비용 가늠)
- 프로파일 A: knee탐색 3 + 본측정 3구성×3회 = **~12 런**.
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
| **Auto-inflate** | 테스트 중 TU가 1→N으로 자동 증가 → **용량이 실험 중 변함**(초반 throttle, 후반 해소) | **OFF 고정**(기본). H6는 고정 용량에서. 스케일 대조는 별도 세트로 명시적 |
| **TU(capacity)** | 1 TU=1MB/s. 큰 body에서 즉시 throttle → C3 비교 왜곡 | **1 TU 고정**(한계 관측). 별도 세트로 20 TU 대조 |
| **파티션 수** | 파티션 적으면 병렬성 병목 | 4 파티션 고정, 값 기록 |
| **로거 `isBuffered`** | 버퍼링 on/off로 배치·throttle·CPU 거동 변화 | 값 고정(기본 on) + 기록 |
| **partition-key** | 정책에 지정 시 특정 파티션 쏠림 | 미지정(라운드로빈) |
| **메시지 200KB 상한** | 200KB 초과분 자동 절단 → "전량"이 아님 | body ≤ 200KB로 스윕 상한 설정 |

### 9.2 Azure Load Testing (ALT)
| 변수 | 이상치 시나리오 | 통제 |
|------|----------------|------|
| **엔진 콜드스타트** | 첫 런이 느림(v1 3회차 C1 이상치) | **워밍업 런 폐기** |
| **Auto-stop(오류율)** | 오류>90%/60s 시 런 자동 중단 → 데이터 카오스(v1 과부하) | 부하를 auto-stop 미만으로, 또는 **failureCriteria/auto-stop 완화** 후 오류율 지표로 별도 해석 |
| **Closed-model** | 고정 VU라 RPS=동시성/응답. 응답↑(큰 body)면 RPS 자연 감소 → "고정 RPS" 착시 | 동시성 고정 + **달성 RPS 실측** |
| **엔진 병목** | 엔진이 부족하면 클라이언트-바운드(게이트웨이 미포화) → 로깅 효과 안 보임(v1) | knee 탐색으로 게이트웨이-바운드 확인, 필요 시 엔진↑ |
| **ramp 구간** | ramp 중 부분 부하가 평균을 오염 | **steady-state 윈도우만** 집계 |
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
- **단일 리전(japaneast)**·**동일 세션 시간대**로 네트워크·noisy-neighbor 변동 최소화.
- **GatewayLogs Dedicated** 미설정 시 `TotalTime` 없음.

## 10. 실행 순서 (재실험)
1. 배포(0818x) — 수정된 `deploy-logbench.sh`(MI 로거 자동, Dedicated 진단, RG/EH `SecurityControl=Ignore` 태그).
2. 사용자에게 EH **Data Receiver** 역할 부여(소비용).
3. **내용 검증**(§7): 64KB로 C2 잘림·C3 전량(EH 소비) 확인.
4. **CPU 포화 실험**(§4.2 A): knee 탐색 후 C1/C2/C3, CPU% 관측(H2·H3).
5. **EH 방향성 스윕**(§4.2 B): body 8→200KB, C3의 CPU·throughput·**EH Throttle/Drop/Bytes**(H5·H6).
6. **삭제 전** EH·CPU 메트릭 캡처 → 분석.
7. teardown(RG 삭제) + APIM purge.

## 10. 결과 (재실험 후 채움)
- 10.1 내용 검증 결과 — *TBD*
- 10.2 CPU 포화 결과(H2/H3) — *TBD*
- 10.3 EH 대용량 방향성(H5/H6) — *TBD*
- 10.4 판정표(가설별) — *TBD*
- 10.5 한계 — *TBD*
