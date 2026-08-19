# Lab 13 — 로깅 성능/용량 벤치마크: 실험 설계서 (v2, 재실험용)

> **상태**: 설계 리뷰 단계. 지금까지의 실측·시행착오를 반영한 **가설 + 조건**을 먼저 확정하고, 리뷰 후 전체를 실험한다.

---

## 1. 목적

APIM 게이트웨이에서 **로깅 구성(감사 방식)이 성능·용량에 미치는 영향**을, 특히 **payload 용량이 커질 때 App Insights(8KB 상한)와 Event Hub(무손실, 200KB)의 방향성 차이**를 실측으로 규명한다.

## 2. 구성 (무엇을 로깅하나)

| 구성 | 로깅 방식 | body ≤ 8KB | body > 8KB |
|------|-----------|-----------|-----------|
| **조건-1** | 로깅 없음 (applicationinsights 진단 삭제) | 없음 | 없음 |
| **조건-2** | App Insights + 응답 body (상한 8KB) | 전량(=body) | **8KB만 (잘림·유실)** |
| **조건-3** | App Insights body=0(메타) + `log-to-eventhub`(전량, ≤200KB) | 전량(=body) | **전량 (무손실)** |

- 대상: `bench` API — `return-response` mock(백엔드 없음)으로 `?bytes=N` 크기 응답 생성.
- 조건-2·조건-3는 **동일 payload를 서로 다른 sink(로그 저장 대상)**로 보냄. **차이는 8KB 초과 구간에서 발현**된다.

## 3. 가설

- **가설-1**: 로깅 오버헤드는 단건 레이턴시가 아니라 **부하/CPU 현상**이다.
- **가설-2**: App Insights body 로깅(조건-2)은 부하 시 **게이트웨이 CPU를 더 쓴다**
- **가설-3**: 그 CPU 비용은 **게이트웨이 CPU 포화 시 throughput 저하**로 이어진다(문서 "40~50%↓@>1000rps").
- **가설-4**: **8KB에서는 조건-2≈조건-3**(동일 payload). CPU도 유사(조건-3가 약간 낮음).
- **가설-5**: **body>8KB에서 조건-2는 8KB로 잘리고(유실), 조건-3는 전량 무손실**로 기록 한다.
- **가설-6**: **body 용량이 커질수록 조건-3(EH)의 비용이 증가**한다. EH Standard 1 TU = 1MB/s 한계라, `body × RPS`가 이를 넘으면 **EH Throttle/Drop 발생**(무손실의 대가·한계). 조건-2는 8KB 상한이라 body가 커져도 로깅 비용은 평탄.
- **가설-7**: 각 구성은 **의도한 로그만** 남긴다 — 조건-1 없음 / 조건-2 정확히 8192B / 조건-3 전량(body 크기만큼).

## 4. 변수 & 조건

> **부하 조건 · 반복 횟수 · SKU 사전 리뷰의 확정본은 [`TEST-SPEC.md`](TEST-SPEC.md)** 에 있다(재실험 착수 게이트). 아래는 요약.

### 4.1 body 크기 범위
`[8KB(8192), 32KB(32768), 64KB(65536), 128KB(131072), 200KB(204800)]`
- 8KB = 기준선(조건-2·조건-3 동일). 이후는 조건-2 잘림 vs 조건-3 전량이 갈리는 구간.

### 4.2 부하 조건 — 두 프로파일

ALT(Azure Load Testing)는 **closed-model(고정 동시성 방식)**로 VU(가상 사용자 수)를 고정하므로 RPS = 동시성 ÷ 응답시간이다. 정확한 RPS 고정은 불가 → **동시성을 고정하고 달성 RPS를 기록**한다. 매 측정은 steady-state(부하가 안정된 측정 구간)만 집계하고 ramp(부하 증가 구간)는 제외하며, 워밍업 런 1회는 폐기한다.

> **왜 TPS가 아니라 RPS인가?** 이 실험은 HTTP API 게이트웨이가 **초당 몇 개의 요청을 성공 처리하는지** 측정한다. TPS(Transactions Per Second)는 주문·결제 같은 업무 트랜잭션의 범위에 따라 API 요청 여러 개를 포함할 수 있어 기준이 모호하다. 따라서 여기서는 **성공 RPS(Requests Per Second, 초당 성공 요청 수)**를 사용자 관점의 처리량으로 사용한다.

| 프로파일 | 쉽게 말하면 | 고정하는 값 | 바꾸는 값 | 확인하는 값 |
|---|---|---|---|---|
| **A — CPU 영향 확인** | 요청을 늘려 초당 처리량과 CPU 차이 확인 | body 8KB | 동시성, 조건-1~조건-3 | **성공 RPS**, CPU, 오류율, p95 |
| **B — 대용량 로그 영향 확인** | 동시성은 유지하고 body를 키워 초당 처리량 변화 확인 | 동시성 1엔진 × 100 threads | body 8→200KB, 조건-1~조건-3 | **성공 RPS**, EH 처리 제한·유실, CPU |

**프로파일 A — 부하를 높여 CPU 영향 확인 (가설-2·가설-3)**
1. **기준 부하 찾기**: 동시성을 `2×250(500)` → `4×250(1000)` → `6×250(1500)`으로 높이며 CPU·성공 RPS·오류율·p95를 측정한다.
2. **조건 비교**: 선택한 knee(기준 부하)에서 조건-1~조건-3을 반복 측정한다.

각 단계는 ramp(부하 증가) 30초 후 120초 동안 측정한다.

**프로파일 B — body를 키워 대용량 로그 영향 확인 (가설-5·가설-6)**
1. 동시성을 **1엔진 × 100 threads**로 고정한다.
2. body를 `8/32/64/128/200KB`로 키우며 조건-1~조건-3을 비교한다.
3. EH 처리 제한·유실, CPU, 성공 RPS를 측정한다.

각 단계는 ramp 20초 후 90초 동안 측정한다. EH는 **1 TU(처리량 단위, 1MB/s)·auto-inflate(자동 확장) OFF**로 고정한다. 100 RPS 기준 예상 전송량은 8KB에서 0.8MB/s, 200KB에서 20MB/s다.

### 4.3 반복 & 순서 (구체)
- **반복 R = 3회** / (구성 × 부하셀). 편차가 크면(범위 > 평균의 15%) **R=5로 증량**.
- **순서 균형**: 정순·역순 교차. 예 3회: `조건-1 → 조건-2 → 조건-3` · `조건-3 → 조건-2 → 조건-1` · `조건-1 → 조건-2 → 조건-3`(각 구성이 1·2·3번 위치를 고루 경험).
- **워밍업**: 배포 직후 1회(폐기). 구성 전환 시 **전파 대기 90~150s**.
- **단일 워밍업된 게이트웨이**에서 구성만 토글(배포 편차 상수화).
- **보고**: 구성별 **mean ± (min/max)**. 이상치(콜드 등)는 표시하되 **제외 시 근거 명시**.

### 4.4 실행 예산 (리뷰용 — 시간/비용 가늠)
- 프로파일 A: knee(기준 부하) 탐색 3 + 본측정 3구성×3회 = **~12 런**.
- 프로파일 B: 5크기 × (조건-2,조건-3) × 3회 = 30 + 조건-1 기준 몇 = **~33 런** (+ auto-inflate 대조 세트 시 추가).
- 런당 ~4~6분(엔진 기동 포함) → **A+B ≈ 45런 ≈ 3~4시간 + 배포**. ⚠️ ALT(Azure Load Testing) VUH·APIM·EH 시간당 과금.
- **축소 옵션**(리뷰에서 선택): body를 3개(8/64/200KB)로, R=2로 → ~20런 ≈ 1.5~2시간.

## 5. 측정 지표

| 축 | 지표 | 출처 |
|----|------|------|
| 게이트웨이 CPU | `CpuPercent_Gateway` (max/avg, 구성×크기 윈도우) | Azure Monitor (APIM) |
| 단건 처리시간 | `TotalTime − BackendTime` | `ApiManagementGatewayLogs` (Dedicated) |
| 처리량 | **성공 RPS**(Total−Errors), p95, 오류% | `az load test-run metrics list` |
| **EH 방향성** | `EventHubTotalEvents`·`SuccessfulEvents`·**`ThrottledEvents`·`DroppedEvents`**·`TotalBytesSent` | Azure Monitor (APIM) — **삭제 전 캡처** |
| **내용 검증** | App Insights `Response-Body` 길이 분포 (조건-1 없음/조건-2 8192/조건-3 0) | `AppRequests`(Properties) |
| **내용 검증** | EH 실제 메시지 크기 (전량 담겼는지) | **Event Hub 소비**(azure-eventhub SDK, 사용자 Data Receiver 역할) |

## 6. 측정 격리 원칙 (백엔드·네트워크 배제)
- **백엔드 제거**: `return-response` → `BackendTime≈0`(데이터로 확인).
- **네트워크 배제**: 권위 지표는 서버측 `CpuPercent_Gateway`·`TotalTime`(클라이언트↔APIM RTT 무관).
- **중립 자**: GatewayLogs 진단을 **Dedicated(resource-specific)** 로 전 구성 상시 ON(상쇄).

## 7. 로그 내용 검증 절차 (삭제 전 필수)
1. 조건-2 소량 호출(큰 body) → `AppRequests`에서 `Response-Body` 길이 = **8192(잘림)** 확인.
2. 조건-3 소량 호출(큰 body) → **Event Hub 소비** → 메시지 크기 = **body 전량** 확인.
3. 조건-1 → App Insights에 요청 **없음** 확인(GatewayLogs엔 존재).
4. EH `Throttled/Dropped/BytesSent` 메트릭을 **teardown 전에** 캡처.

## 8. 결과

### 8.1 내용 검증 (64KB 요청) ✅ 핵심
| 구성 | App Insights `Response-Body` 길이 | EH 실제 메시지(소비 확인) |
|------|:---:|:---:|
| 조건-1 | (없음) | — |
| 조건-2 App Insights | **8192 (=8KB로 잘림)** × 15 | — |
| 조건-3 Event Hub | **0** × 15 | **8192·65536 전량**(EH 소비로 확인) |

→ **64KB 요청에서 조건-2는 8KB로 잘려 유실(가설-5의 App Insights 측), 조건-3는 EH에 전량(8192/65536) 무손실 저장** — EH를 쓰는 이유(8KB 초과 무손실)를 **직접 실증**. App Insights EventHub 송신 메트릭(`EventHubTotalBytesSent`)은 수집 지연/집계로 0이었으나, **EH를 직접 소비해 body 전량 저장을 확정**.

### 8.2 고부하 CPU 비교 (프로파일 A, **미포화**, 1,000 VU·body 8KB 고정)
**목적**: 게이트웨이를 **고부하로 눌러** 로깅 방식이 CPU·처리량에 주는 영향을 본다 → 그래서 **높은 동시성(1,000 VU)** 을 준다. 이때 조건-3의 **EH 로깅 용량 = 요청당 8KB**(= §8.3의 8KB 지점과 **같은 body**, 단 부하가 1,000 vs 100 VU로 달라 CPU가 67.5% vs 21%로 다르게 나옴).

**부하 모델 주의(closed-loop)**: 이 테스트는 "초당 N개를 쏘는" 방식이 아니라 **가상 사용자(VU) 수를 고정**(각자 요청→응답→반복)하고 그 결과로 나온 RPS를 관측한다. 따라서 **RPS는 내가 정한 입력이 아니라 결과값**이며, 아래 수치는 **"견디는 최대 용량"이 아니다**(closed/open 부하 모델은 §4.2 참조).

**포화 탐색 — 포화 미도달**: 500VU(2×250)→CPU 32%/1,322rps · 1,000VU(4×250)→CPU **61%**/2,695rps · 1,500VU(6×250)→CPU **61%**/4,100rps. **CPU가 61%에 머무는데도 사람을 늘리자 RPS는 계속 상승(2,695→4,100)** → 처리량이 평평해지는 knee(한계)를 **찾지 못함**. 역산한 응답시간도 ~0.37s에서 정체 → 이 mock 워크로드에선 게이트웨이 CPU가 병목이 되기 전에 **다른 요소(네트워크/mock 왕복 ~0.37s 지연 바닥)가 먼저 제한**했다. 즉 문서의 "완전 포화 시 throughput 붕괴"(가설-3)는 **여기서 재현 못 함**.

아래는 **동일 부하(1,000 VU·8KB)로 고정**하고 조건만 바꿔 잰 게이트웨이 CPU다(부하가 같아 "로깅 방식만의 CPU 차이"를 격리):

| 구성 | CPU% max (2런 균형) | 개별 런 | 관측 RPS(용량 아님) |
|------|:---:|:---:|---:|
| **조건-1** 무로깅 | **66.5%** | 65 / 68 | 2539 |
| **조건-2** App Insights 8KB | **74.5% (+8.0%p)** | 79 / 70 | 2759 |
| **조건-3** body=0 + EH | 67.5% (+1.0%p) | 69 / 66 | 2820 |

→ **가설-2: 경향 지지(통계적 확정은 아님)**. 동일 부하에서 App Insights body 로깅(조건-2)이 조건-1보다 CPU **+8%p** 경향. 단 **n=2이고 조건-2 개별 런(79/70)의 편차(9%p)가 효과 크기(8%p)와 맞먹어** 이 표 하나로는 확정이 아니다 — 다만 **방향은 v1(+12.5%p)·공식문서(§8.6)·프로파일 B(§8.3)와 일치**해 정황상 지지된다. **조건-3는 조건-1과 사실상 동등(+1%p)** — `log-to-eventhub`가 비동기라 게이트웨이 CPU 부담이 거의 없음.
→ **관측 RPS(2,539/2,759/2,820)가 세 조건 유사**한 건 **미포화**라 CPU 여유가 있어 로깅이 처리량을 갉아먹지 못한 것 → **처리량 관점 우열은 여기서 판단 불가**(이 수치는 용량 한계가 아니라 고정 부하에서의 관측값, 당시 에러 0).

### 8.3 EH 대용량 방향성 (프로파일 B, body 8/64/200KB, 1×100)
**목적**: 부하는 낮게 **고정**하고 **body 크기만** 8→200KB로 키워, 각 조건의 **비용 기울기**를 본다 → 그래서 **일부러 낮은 동시성(100 VU)** 을 준다(200KB를 고부하로 걸면 부하 엔진·네트워크·EH가 게이트웨이보다 먼저 터져 body 효과가 가려짐). **프로파일 A(1,000 VU)와 부하가 달라 절대값 직접 비교는 불가** — 두 실험을 잇는 공통 앵커가 없어 **"고부하 × 대용량 body" 구석은 미측정**.

| body | 조건-1 CPU% / 성공 RPS | 조건-2 CPU% / 성공 RPS | **조건-3 CPU% / 성공 RPS** | EH thr/drop |
|------|:---:|:---:|:---:|:---:|
| 8KB | 17 / 653 | 18 / 553 | **21 / 521** | 0 / 0 |
| 64KB | 17 / 492 | 24 / 540 | **26 / 598** | 0 / 0 |
| 200KB | 25.5 / 458 | 29 / 453 | **37 / 388** | 0 / 0 |

→ **가설-6 방향성 확인**: **body가 커질수록 조건-3(EH)의 CPU 비용이 가장 가파르게 증가**(21→26→**37%**). 200KB에서 조건-3 CPU가 최고(37%)이고 RPS 최저(388) — `log-to-eventhub`가 200KB 전량을 인라인(요청 처리 중) 직렬화·전송하는 비용. 반면 **조건-2는 8KB 상한이라 body가 커져도 로깅 몫은 평탄**(CPU 18→24→29는 주로 응답 전송 자체 비용).
→ **EH throttle/drop(처리 제한/유실) = 0 (전 구간)**: 이 부하(1×100, ~400-600rps)에선 200KB×RPS가 1TU(1MB/s)를 넘겼을 것으로 추정되나 **버퍼링·재시도로 유실 없이 흡수**. 더 센 부하에선 throttle(처리 제한) 가능(미도달).

### 8.4 판정표 (가설별)
| 가설 | 판정 | 근거 |
|------|------|------|
| 가설-1 단건 sub-ms | ✅ 확정 | (v1) TotalTime 0~1ms |
| 가설-2 조건-2가 CPU 더 씀 | △ **경향 지지** | A: +8%p 경향(n=2, 런 편차 9%p) — v1·문서·B와 방향 일치 |
| 가설-3 CPU 비용→throughput 붕괴 | ⚠️ 미도달 | CPU가 ~61-75%에서 정체(100% 미포화), mock이 게이트웨이를 그만큼만 씀 |
| 가설-4 8KB에서 조건-2≈조건-3 | ✅ 확정 | B 8KB: CPU 18 vs 21, 근접 |
| **가설-5 body>8KB: 조건-2 잘림·조건-3 무손실** | ✅ **확정(핵심)** | 내용검증: 조건-2=8192, 조건-3=EH에 8192/65536 전량 |
| **가설-6 body↑ → 조건-3 비용↑** | ✅ **방향성 확인** | B: 조건-3 CPU 21→26→37%, RPS 521→598→388 |
| 가설-7 의도한 로그만 | ✅ 확정 | 조건-1 없음/조건-2 8192/조건-3 0 (App Insights) + EH 전량 |

### 8.4.1 조건-3 성능 판정 — **성능 향상은 없다**
질문: "조건-3는 성능 관점에서 이득이 있는가?" → **본 실험의 모든 결과로 볼 때 조건-3의 성능 향상은 없다.** 성능축에서 로깅은 비용이지 이득이 아니며, 어떤 로깅 구성도 무로깅(조건-1)을 이길 수 없다. 세 단계로 정리:

1. **무로깅(조건-1) 대비: 향상 0.** 조건-3도 조건-1 대비 **+1%p CPU**(A: 66.5→67.5). "조건-3를 켜서 빨라진다"는 성립 불가.
2. **조건-2 대비: 조건부 "덜 나쁨"이며 견고하지 않음.**

   | 조건 | 조건-2 | 조건-3 | 조건-3 우위? |
   |------|:---:|:---:|:---:|
   | 8KB·포화 (Profile A) | 74.5% | 67.5% | ✅ CPU −7%p (비동기 디커플링) |
   | 8KB·저부하 (Profile B) | 18% | 21% | ❌ 조건-3가 더 씀 |
   | 64KB (Profile B) | 24% | 26% | ❌ 조건-3가 더 씀 |
   | 200KB (Profile B) | 29% | **37%** | ❌❌ 조건-3가 훨씬 더 씀 |

   - 작은 body(≤8KB)·포화에서만 조건-3가 조건-2보다 CPU 절약(async, 게이트웨이 back-pressure 없음).
   - **큰 body(>8KB)에서는 오히려 조건-3가 조건-2보다 CPU를 더 씀** — 조건-2는 8KB에서 잘라 멈추지만(로깅 몫 평탄) 조건-3는 전량(≤200KB)을 인라인 직렬화·전송.
   - **같은 8KB인데 Profile A(조건-3<조건-2)와 Profile B(조건-3>조건-2)가 상반** → 조건-3의 CPU 우위는 로드 조건 의존적, 견고하지 않음.
3. **CPU를 아꼈어도 throughput/latency 개선으로 "측정"되지 않음.** A에서 조건-3가 조건-2 대비 CPU 8%p를 아꼈으나, 시스템이 CPU-bound가 아니라 동시성·네트워크 한계라 성공 RPS는 노이즈 범위 내 혼재(2539/2759/2820, 가설-3 미도달).

→ **종합**: 조건-3의 정당화는 **성능이 아니라 역량**(무손실·200KB·샘플링 무관·감사). 순수 성능만 보면 조건-3는 잘해야 "작은 body·포화 한정 조건-2보다 CPU 덜 씀"(측정된 throughput 이득 없음), 나쁘면 "큰 body에서 조건-2보다 CPU 더 씀". **무로깅 대비 개선은 0.**

### 8.5 한계
- **CPU 완전 포화(100%) 미도달**: mock `return-response`는 게이트웨이를 60-75%까지만 사용 → 문서의 "throughput 40~50%↓"(완전 포화 전제)는 여전히 미검증(가설-3). 실백엔드·더 무거운 정책이면 포화 가능.
- **EH throttle 미발생**: 우리 부하로는 EH 1TU를 유실까지 몰지 못함(버퍼가 흡수). "무손실의 대가=drop"은 더 센 부하 필요.
- **EH 200KB 소비 샘플 미확보**: 소비 배치 타이밍상 8192·65536만 잡힘(200KB는 log-to-eventhub 200KB 상한 이내라 전송은 됨).
- **성공 RPS 노이즈**: 프로파일 B는 1엔진·소규모라 RPS 절대값 변동 존재. CPU%가 더 안정적 지표.

### 8.6 공식 문서 근거 (조건-2 vs 조건-3 성능 서술의 비대칭)
**조건-2와 조건-3를 직접(head-to-head) 벤치마크한 공식 문서는 없다.** 그러나 성능 저하 경고가 **오직 조건-2/App Insights 문서에만** 붙어 있고, 조건-3/Event Hub 문서는 정반대로 포지셔닝된다 — 이 **서술의 비대칭 자체**가 우리 실측(조건-2 CPU +8%p·8KB 잘림 vs 조건-3 +1%p·무손실)과 방향이 일치한다.

| 근거 | 조건-2 (App Insights) | 조건-3 (Event Hub) |
|------|---|---|
| 성능 경고 | ✅ **명시**: "internal load tests, **40%–50% reduction in throughput** when request rate exceeded **1,000 requests per second**" | ❌ 없음. 오히려 "**millions of events per second**", "**decouples** production from consumption"(비동기) |
| body 로깅 | "**might significantly decrease the performance**" → "To improve performance issues, **skip … Body logging**" | log-to-eventhub: "**not affected by … sampling. All invocations … will be logged**"(무손실) |
| 손실/상한 | 샘플링으로 **의도적 유실** 전제, body **8KB** | 샘플링 무관 전량, 메시지 **200KB** |
| 감사 적합성 | "**not** intended to be an audit system. **Not suited for logging each individual request for high-volume APIs**" | "highly scalable data ingress service" (감사·오프라인 분석용) |

**출처**
- [Integrate APIM with Application Insights — "Performance implications and log sampling"](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-app-insights#performance-implications-and-log-sampling): "40%–50% reduction in throughput … over 1,000 rps", "skip … Body logging", "not intended to be an audit system"
- [`log-to-eventhub` policy reference — Usage notes](https://learn.microsoft.com/en-us/azure/api-management/log-to-eventhub-policy): "not affected by Application Insights sampling. All invocations … logged", "maximum … message size … is 200 KB"
- [How to log events to Azure Event Hubs](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-log-event-hubs): "ingest millions of events per second", "decouples the production … from the consumption"

**단, 정직하게**: 문서의 "-40~50% throughput"은 **완전 포화(>1000rps)** 전제이고, 본 실험은 mock이 게이트웨이를 60-75%까지만 써서 그 **수치(크기)는 미재현**(가설-3, §8.5). **저하 방향**은 문서·실측 일치, **크기**는 본 환경 미검증.

### 8.7 산출물
- **HTML 리포트**: [`report.html`](./report.html) — 자체완결(인라인 SVG, Clawpilot 테마), 위 결과 시각화
- **차트(PNG)**: [`v2-assets/verify.png`](./v2-assets/verify.png) (내용검증), [`v2-assets/A-cpu.png`](./v2-assets/A-cpu.png) (CPU 포화), [`v2-assets/B-directionality.png`](./v2-assets/B-directionality.png) (EH 방향성)
- **v1 아카이브**: [`old/`](./old/) — 2026-08-18 이전 단건 측정 결과
