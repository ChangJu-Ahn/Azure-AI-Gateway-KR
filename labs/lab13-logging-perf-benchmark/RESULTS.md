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

### 4.1 body 크기 스윕 (핵심 축)
`[8KB(8192), 32KB(32768), 64KB(65536), 128KB(131072), 200KB(204800)]`
- 8KB = 기준선(C2·C3 동일). 이후는 C2 잘림 vs C3 전량이 갈리는 구간.

### 4.2 부하 (두 목적)
- **(a) CPU 포화 확인용**: 게이트웨이 CPU를 100% 근처까지 미는 고부하(엔진 다수·고동시성). H2·H3용.
- **(b) EH 방향성용**: body×RPS로 EH 대역폭(1MB/s)을 넘겨 Throttle/Drop을 유도하는 중간 부하. H6용.
- 각 실행: **워밍업 런(폐기)** 후 측정.

### 4.3 방법론 규율 (재현성)
- **워밍업**: 콜드스타트 제거.
- **순서 균형 + 반복**: 구성/크기 순서를 균형화(예: 정순·역순)하고 각 셀 **N≥2회** 측정, 평균±범위 보고.
- **단일 워밍업된 게이트웨이**에서 구성만 토글(배포 편차 상수화).

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
- **EH SAS 비활성 테넌트**: 연결문자열 로거 배포 실패 → **MI 로거 + "Azure Event Hubs Data Sender" 역할**(배포 스크립트가 재시도 등록).
- **GatewayLogs 타이밍**: 진단이 기본 `AzureDiagnostics`면 `TotalTime` 없음 → **Dedicated** 필수.
- **az load 특성**: `--env`는 환경변수(JMX는 `System.getenv`로 읽음), `--wait` 미지원(기본 대기), 집계는 `testRunStatistics`(null) 대신 **`metrics list`**.
- **yaml**: 빈 `userPropertyFile` 금지(경로 `.` 오인).
- **EH 용량**: Standard 1 TU=1MB/s. 큰 body 실험에서 **auto-inflate 여부/파티션 수**를 변수로 고려(H6 해석에 필요).
- **삭제 전 캡처**: APIM/EH 삭제 시 플랫폼 메트릭 접근 불가 → **측정 직후 캡처**. (LA는 14일 soft-delete로 사후 복구 가능.)
- **StandardV2**: `gatewayUrl` 출력이 비어올 수 있어 `<name>.azure-api.net`로 보정.

## 9. 실행 순서 (재실험)
1. 배포(0818x) — 수정된 `deploy-logbench.sh`(MI 로거 자동, Dedicated 진단).
2. 사용자에게 EH **Data Receiver** 역할 부여(소비용).
3. **내용 검증**(§7): 64KB로 C2 잘림·C3 전량(EH 소비) 확인.
4. **CPU 포화 실험**(§4.2a): body별 C1/C2/C3, CPU% 관측(H2·H3).
5. **EH 방향성 스윕**(§4.2b): body 8→200KB, C3의 CPU·throughput·**EH Throttle/Drop/Bytes**(H5·H6).
6. **삭제 전** EH·CPU 메트릭 캡처 → 분석.
7. teardown(RG 삭제) + APIM purge.

## 10. 결과 (재실험 후 채움)
- 10.1 내용 검증 결과 — *TBD*
- 10.2 CPU 포화 결과(H2/H3) — *TBD*
- 10.3 EH 대용량 방향성(H5/H6) — *TBD*
- 10.4 판정표(가설별) — *TBD*
- 10.5 한계 — *TBD*
