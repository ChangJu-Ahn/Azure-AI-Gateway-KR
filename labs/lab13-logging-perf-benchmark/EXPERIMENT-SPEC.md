# Lab 13 — Developer v1에서 App Insights와 Event Hub 로깅 비교

> **상태**: 실행 전 실험 명세
> **적용 범위**: 기존 Azure API Management Developer v1 인스턴스, 단일 리전
> **목표 부하**: 500 offered RPS (고정)
> **필수 크기**: 8KB, 64KB

---

## 0. 이 실험을 시작한 두 질문과 공식 문서의 답

### 질문 1 — APIM에 App Insights 로깅을 연결하면 성능이 저하되는가

Microsoft의 [APIM과 Application Insights 통합 문서 — Performance implications and log sampling](https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights#performance-implications-and-log-sampling)은 다음과 같이 명시한다.

> "Logging all events might have serious performance implications, depending on incoming requests rate."
>
> "Based on internal load tests, enabling the logging feature caused a 40%-50% reduction in throughput when request rate exceeded 1,000 requests per second."

문서는 이어서 Application Insights가 통계적 성능 분석용이며 다음 용도에는 맞지 않는다고 설명한다.

> "It's not: Intended to be an audit system. Suited for logging each individual request for high-volume APIs."

공식 완화책은 sampling을 낮추고 request/response header와 body 로깅을 생략하는 것이다.

> "Sampling helps to reduce telemetry volume, effectively preventing significant performance degradation while still carrying the benefits of logging."
>
> "To improve performance issues, skip: Request and responses headers; Body logging."

#### 이 문서가 증명하는 것

- App Insights로 모든 요청을 로깅하면 요청률에 따라 심각한 성능 영향을 줄 수 있다.
- Microsoft 내부 테스트에서는 **1,000 RPS를 초과**했을 때 throughput이 40~50% 감소했다 (배경 정보 — 본 실험 범위 외).
- sampling 100%는 모든 요청을 로깅하도록 설정하는 값이다.
- sampling 축소와 body 로깅 생략은 성능 완화책이지만 모든 요청의 body를 감사하려는 요구와 충돌한다.

#### 이 문서가 증명하지 않는 것

- Developer v1에서도 정확히 1,000 RPS 또는 40~50% 감소가 재현된다는 보장은 없다.
- 본 실험은 1,000 RPS 이상을 측정하지 않는다. APIM Developer SKU의 500 RPS 조건에서의 영향만 실측한다.

### 질문 2 — 모든 요청을 로깅하면서 성능 저하를 피할 방법이 있는가

App Insights 문서의 완화책은 sampling 축소 또는 body 생략이므로 모든 요청의 body를 감사하려는 요구를 만족하지 못한다. Event Hub를 대안 가설로 세우는 공식 근거는 두 문서에 있다.

Microsoft의 [APIM events를 Event Hubs에 로깅하는 방법](https://learn.microsoft.com/azure/api-management/api-management-howto-log-event-hubs)은 Event Hubs를 다음과 같이 설명한다.

> "Azure Event Hubs is a highly scalable data ingress service that can ingest millions of events per second."
>
> "Event Hubs decouples the production of a stream of events from the consumption of those events, so that event consumers can access the events on their own schedule."

Microsoft의 [`log-to-eventhub` 정책 문서 — Usage notes](https://learn.microsoft.com/azure/api-management/log-to-eventhub-policy#usage-notes)는 다음을 명시한다.

> "The policy is not affected by Application Insights sampling. All invocations of the policy will be logged."
>
> "The maximum supported message size that can be sent to an event hub from this policy is 200 kilobytes (KB). A larger message will be automatically truncated to 200 KB."

#### 이 문서가 증명하는 것

- Event Hubs는 대규모 이벤트 수집과 생산자·소비자 분리를 목적으로 설계됐다.
- `log-to-eventhub` 정책 호출은 App Insights sampling의 영향을 받지 않는다.
- 정책이 보내는 메시지는 최대 200KB이며 초과분은 자동으로 잘린다 (배경 정보 — 본 실험은 8KB·64KB만 측정).

#### 이 문서가 증명하지 않는 것

- `log-to-eventhub`를 사용하면 APIM throughput이 저하되지 않는다는 직접적인 성능 보장은 없다.
- "All invocations ... will be logged"는 정책이 sampling으로 생략되지 않는다는 뜻이지, 최종 consumer에서 누락이 항상 0이라는 end-to-end 보장은 아니다.
- Event Hubs 자체가 대규모 이벤트를 수집할 수 있다는 설명만으로는, APIM gateway가 `log-to-eventhub` 정책을 실행해도 같은 처리량을 유지하거나 payload 증가에 따른 정책 실행 비용이 없다고 볼 수 없다.

따라서 H2는 **500 RPS에서 Event Hub가 모든 요청의 8KB 로그를 전달하면서 SLO를 충족하는지**, H3는 **64KB에서도 같은 SLO를 충족하는지**를 실측한다.

---

## 1. 검증 가설

### H1 — App Insights 8KB의 500 RPS 성능 영향

Developer v1에서 N8과 A8에 동일한 500 offered RPS를 주었을 때 App Insights sampling 100% + 8KB body 로깅이 gateway CPU, p99 또는 성공 처리율에 추가 비용을 만든다.

#### 판정

- **리소스 오버헤드 지지**:
  - A8 평균 gateway CPU가 N8보다 5%p 이상 높거나
  - A8 p99가 N8보다 20% 이상 높고
  - 세 반복이 모두 같은 방향이다.
- **처리량 저하 확정**:
  - N8은 성공 RPS 495 이상이며 오류율 1% 이하이고
  - A8은 성공 RPS 495 미만이거나 오류율이 1%를 초과한다.
- 두 조건이 모두 성립하지 않으면 "본 Developer v1·500 RPS 조건에서는 유의한 저하를 관찰하지 못함"으로 판정한다.

공식 문서의 1,000 RPS 초과 내부 테스트 결과를 500 RPS에 그대로 적용하지 않는다.

### H2 — Event Hub 8KB의 500 RPS 유지

E8이 모든 요청의 8KB 로그를 Event Hub consumer까지 전달하면서 500 RPS SLO를 충족한다.

#### 필수 통과 조건

- generated / offered requests ≥ 99%
- 성공 RPS ≥ 495
- 오류율 ≤ 1%
- p99 ≤ 같은 블록 N8 p99의 120%
- APIM 성공 요청의 모든 고유 ID가 EH consumer에서 확인
- payload hash 일치
- 전체 EH 메시지 크기 8KB

A8도 SLO를 통과하면 Event Hub가 성능 손실을 회복했다고 표현하지 않는다. "Event Hub도 500 RPS를 유지했다"라고만 결론 내리고 CPU와 p99 차이를 별도 보고한다.

### H3 — Event Hub 64KB의 500 RPS 유지

E64가 모든 요청의 64KB 로그를 Event Hub consumer까지 전달하면서 500 RPS SLO를 충족한다.

#### 필수 통과 조건

H2와 동일한 기준을 사용하되 p99는 같은 블록 N64와 비교하고 메시지 크기는 64KB여야 한다.

N64가 SLO를 실패하면 E64를 Event Hub 실패로 판정하지 않고 해당 Developer v1 또는 부하 생성기의 64KB 처리 한계로 분리한다.

---

## 2. 실험 구성

모든 구성은 같은 APIM 인스턴스, API, 요청 body, 응답 크기, 정책 순서와 공통 진단을 사용한다. 조건별 차이는 body를 어느 sink로 보내는지뿐이다.

| ID | 감사 레코드 | App Insights | Event Hub |
|---|---:|---|---|
| N8 | 8KB | sampling 100%, body 0B | 없음 |
| A8 | 8KB | sampling 100%, body 8KB | 없음 |
| E8 | 8KB | sampling 100%, body 0B | 8KB 전체 메시지 |
| N64 | 64KB | sampling 100%, body 0B | 없음 |
| E64 | 64KB | sampling 100%, body 0B | 64KB 전체 메시지 |

응답은 모든 조건에서 동일한 작은 고정 body이며 backend를 호출하지 않는다.

### 감사 레코드와 응답

- 감사 레코드는 `requestId`, 클라이언트 송신 시각, 전체 레코드 크기, payload hash와 padding payload를 포함한다.
- `log-to-eventhub`는 별도 JSON envelope를 추가하지 않고 요청 body를 그대로 보낸다.
- 8KB·64KB는 `log-to-eventhub`가 보내는 **전체 메시지 content 크기**다.
- 응답은 모든 조건에서 동일한 작은 고정 body를 반환한다.
- 백엔드는 호출하지 않고 `return-response`를 사용한다.

---

## 3. 고정 인프라 조건

### 3.1 APIM

- SKU: **Developer v1** (기존 인스턴스)
- APIM autoscale 설정: **없음**
- 리전: APIM과 동일 리전 (Korea Central)
- multi-region: 사용하지 않음
- 테스트 중 SKU, unit, zone, network, custom domain, certificate와 기타 인프라 변경 금지

각 런 전후 다음을 JSON으로 저장한다.

- SKU와 unit 수
- autoscale 설정 전체
- provisioning state
- gateway URL과 리전
- API revision
- API 및 diagnostic policy hash
- App Insights sampling과 body byte 설정

### 3.2 부하 생성기

- 도구: Python asyncio + aiohttp, 고정 도착률(open workload)
- VM: APIM과 동일 리전(Korea Central)의 고정 단일 Standard_D8as_v5 Linux VM
- 동시성: 20 (검증 결과 500 RPS·0 오류·p50 4ms 달성; 과도한 동시성은 TLS 핸드셰이크 churn으로 꼬리 지연 유발)
- 커넥션 재사용 + 측정 전 커넥션 풀 예열
- autoscale: 사용하지 않음
- HTTP client retry: **OFF**

다음 중 하나라도 발생하면 런을 무효화한다.

- VM CPU 평균 70% 초과
- generated / offered requests 99% 미만
- socket 또는 TLS 오류

> **부하 생성기 한계와 판정 지표**: 단일 프로세스 asyncio는 TLS 처리로 인해 클라이언트 측 p95/p99에 ~500ms 꼬리를 남긴다. 이 꼬리는 **모든 조건에 공통**이며 APIM 서버측과 무관하다. 따라서 성능 판정의 **권위 지표는 APIM 서버측 `CpuPercent_Gateway`(및 Capacity/Duration)**로 하고, 클라이언트 p50/p95/p99는 교차검증용 참고 기록으로만 사용한다. 클라이언트 p99를 통과/실패 판정의 1차 근거로 쓰지 않는다.

### 3.3 Event Hubs

- auto-inflate: **OFF**
- partition 수: 주 실험 전체에서 고정
- 실험 중 TU와 partition 수 변경 금지

**E8**: 예상 payload ingress 약 4.1 MB/s — Standard **5 TU 이상** 고정

**E64**: 예상 payload ingress 약 32.8 MB/s — Standard **40 TU** 고정

실제 직렬화 메시지가 64KB를 넘지 않도록 요청 body 자체를 EH content로 사용한다.

EH throttling, server error 또는 consumer lag가 발생하면 APIM 성능과 별도로 sink 용량 조건 실패를 보고한다. 모든 요청 수신 조건을 충족하지 못하면 H2 또는 H3는 실패다.

---

## 4. 부하와 반복

- offered RPS: **500 고정**
- 부하 모델: open workload
- 조건별 반복: 3회

### 런 수 매트릭스

| 블록 | 조건 | 반복 | 런 수 |
|---|---|---:|---:|
| 8KB | N8, A8, E8 | 3회씩 | 9 |
| 64KB | N64, E64 | 3회씩 | 6 |
| **합계** |  |  | **15** |

### 런 구조

| 구간 | 시간 | 집계 여부 |
|---|---:|---|
| ramp | 60초 | 제외 |
| stabilization | 60초 | 제외 |
| steady-state | 300초 | 포함 |
| EH drain | 최대 10분 또는 2분 연속 신규 이벤트 없음 | 감사 완전성만 집계 |

실행 순서는 조건이 앞·중간·뒤 위치를 고르게 경험하도록 블록별 균형 무작위화한다.

한 반복만 반대 방향이거나 판정 경계에 있으면 해당 셀만 2회 추가한다.

---

## 5. 수집 지표

- **클라이언트(참고)**: offered / generated / successful RPS, 오류율, p50 / p95 / p99
- **APIM(권위)**: Capacity(게이트웨이 부하%), Duration(게이트웨이 처리시간), 전체·성공·실패 요청 수
- **Event Hubs**: incoming requests / bytes, throttled requests, server errors
- **대조**: 성공 request ID 집합, EH 수신 ID 집합, 누락·중복 ID, payload hash와 메시지 크기

GatewayLogs 전체 수집은 필수로 두지 않는다. 비용을 줄이기 위해 클라이언트 성공 응답 ID와 EH consumer ID를 권위 대조 데이터로 사용하고, GatewayLogs는 설정 확인용 소량 호출에만 사용한다.

---

## 6. 허용 결론

### H1 지지

> Developer v1의 본 조건에서 App Insights sampling 100% + 8KB body 로깅은 500 offered RPS에서 기준선 대비 CPU 또는 p99 오버헤드를 보였다.

처리량 SLO까지 실패한 경우에만 처리량 저하를 별도로 명시한다.

### H2 통과

> Developer v1의 본 조건에서 Event Hub는 모든 요청의 8KB 로그를 consumer까지 전달하면서 500 RPS SLO를 충족했다.

### H3 통과

> Developer v1의 본 조건에서 Event Hub는 모든 요청의 64KB 로그를 consumer까지 전달하면서 500 RPS SLO를 충족했다.

---

## 7. 금지 결론

- Event Hub가 APIM 성능을 향상시킨다.
- App Insights는 항상 APIM throughput을 저하시킨다.
- Developer v1 결과가 Basic v2, Standard v2 또는 운영 API에 그대로 적용된다.
- 500 RPS 통과가 APIM의 최대 처리량 또는 공식 보장 처리량이다.
- EH metric의 drop 0만으로 모든 요청이 전달됐다고 결론 낸다.
- 64KB 통과 결과로 200KB 성능을 추정한다.

---

## 8. 제외 범위

다음 항목은 본 실험의 측정 대상이 아니다.

- Basic v2
- 포화점 R\* 탐색
- 1,000 RPS 초과 공식 수치 재현
- 32KB, 128KB, 200KB
- Event Hubs 최대 용량 탐색
- Azure Load Testing을 이용한 분산 부하

---

## 9. 원시 데이터 보존

각 런은 다음 디렉터리 구조로 원시 데이터를 보존한다.

```text
raw/
  <run-id>/
    manifest.json
    loadtest-metrics.json
    apim-metrics.json
    eventhub-metrics.json
    sent-request-ids.csv
    received-event-ids.csv
    reconciliation.json
```

`manifest.json`에는 최소한 다음을 기록한다.

- run ID와 test ID
- 조건 ID
- UTC 시작·종료 시각
- offered RPS
- payload 크기
- APIM resource ID, SKU, 리전
- Event Hubs resource ID, tier, 고정 TU, partition 수
- k6 VM instance ID
- Git commit SHA
- API 및 diagnostic policy hash
- App Insights diagnostic 설정
- warm-up 여부
- 유효/무효 판정과 사유

---

## 10. 공식 근거

- [Integrate Azure API Management with Application Insights](https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights#performance-implications-and-log-sampling)
  sampling과 body logging의 성능 영향 및 고처리량 API에서의 제한. 내부 테스트 수치(1,000 RPS 초과, 40~50% 감소)는 배경 정보이며 본 실험의 측정 대상이 아니다.
- [`log-to-eventhub` policy](https://learn.microsoft.com/azure/api-management/log-to-eventhub-policy)
  App Insights sampling의 영향을 받지 않으며 정책 호출마다 실행된다. 최대 메시지 크기 200KB는 배경 정보이며 본 실험은 8KB·64KB만 측정한다.
- [Log API Management events to Azure Event Hubs](https://learn.microsoft.com/azure/api-management/api-management-howto-log-event-hubs)
  Event Hubs 기반 로깅 구성과 생산·소비 분리.
- [Upgrade and scale an Azure API Management instance](https://learn.microsoft.com/azure/api-management/upgrade-and-scale)
  APIM unit의 calls/sec는 대략적인 용량 계획값이며 실제 throughput은 정책·payload·backend latency에 따라 달라진다.
