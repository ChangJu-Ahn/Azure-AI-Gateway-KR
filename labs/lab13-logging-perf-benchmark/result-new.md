# Lab 13 — App Insights 저하 구간에서 Event Hub 처리량 보장 검증

> **상태**: 신규 재실험 설계서  
> **적용 범위**: Azure API Management **Basic v2, 1 unit**, 단일 리전  
> **핵심 질문**: App Insights가 sampling 100%와 8KB body 로깅 때문에 처리량을 잃는 구간에서, Event Hub는 동일하거나 더 큰 body를 전건 로깅하면서도 같은 요청 처리량과 지연 SLO를 만족하는가?

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

- App Insights 전건 로깅은 요청률에 따라 심각한 성능 영향을 줄 수 있다.
- Microsoft 내부 테스트에서는 1,000 RPS를 초과했을 때 throughput이 40~50% 감소했다.
- sampling 100%는 모든 요청을 로깅하도록 설정하는 값이다.
- sampling 축소와 body 로깅 생략은 성능 완화책이지만 전건 body 감사 요구와 충돌한다.

#### 이 문서가 증명하지 않는 것

- Basic v2 1 unit에서도 정확히 1,000 RPS 또는 40~50% 감소가 재현된다는 보장은 없다.
- 정책, payload, 연결과 리전이 다른 본 실험 환경의 저하 지점은 문서 수치가 아니라 실측해야 한다.

따라서 H1은 공식 수치를 그대로 재현하는 실험이 아니라, **본 환경에서 App Insights 100% + 8KB body 로깅이 실제로 실패하는 `R*`를 먼저 찾는 실험**이다.

### 질문 2 — 전건 로깅을 유지하면서 성능 저하를 피할 방법이 있는가

App Insights 문서의 완화책은 sampling 축소 또는 body 생략이므로 전건 body 감사 요구를 만족하지 못한다. Event Hub를 대안 가설로 세우는 공식 근거는 두 문서에 있다.

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
- 정책이 보내는 메시지는 최대 200KB이며 초과분은 자동으로 잘린다.

#### 이 문서가 증명하지 않는 것

- `log-to-eventhub`를 사용하면 APIM throughput이 저하되지 않는다는 직접적인 성능 보장은 없다.
- "All invocations ... will be logged"는 정책이 sampling으로 생략되지 않는다는 뜻이지, 최종 consumer에서 누락이 항상 0이라는 end-to-end 보장은 아니다.
- Event Hubs 서비스가 초당 수백만 이벤트를 수집할 수 있다는 설명은 선택한 tier, TU/PU/CU, partition 수와 메시지 크기에서 용량이 자동 보장된다는 뜻이 아니다.

따라서 H2는 **App Insights가 실패한 동일 `R*`에서 Event Hub가 처리량을 확보하는지**, H3는 **그 처리가 최대 몇 KB까지 유지되는지**, H4는 **최종 consumer까지 실제 전건 도달했는지**를 각각 실측한다.

---

## 1. 결론부터 정의한다

이 실험은 Event Hub가 무로깅보다 빠르거나 APIM 자체 성능을 높인다는 주장을 검증하지 않는다.

검증하려는 주장은 다음 하나다.

> **App Insights 100% sampling + 8KB body 로깅이 실패하는 동일한 offered RPS에서, `log-to-eventhub`는 8KB 또는 더 큰 body를 전건 전달하면서 성공 처리량·오류율·p99 SLO를 만족한다.**

따라서 결과도 "Event Hub가 성능을 향상시켰다"라고 쓰지 않는다. 통과한 경우에만 아래처럼 쓴다.

> Basic v2 1 unit의 본 실험 조건에서 App Insights 8KB 로깅이 SLO를 위반한 R\* RPS를, Event Hub는 최대 N KB까지 감사 완전성과 성능 SLO를 함께 충족했다.

이 결론은 Basic v2 1 unit, 사용한 정책, 리전, payload, 테스트 시점에만 적용한다. Standard v2, 다른 unit 수, 실백엔드 또는 다른 정책 조합으로 일반화하지 않는다.

---

## 2. 검증 가설

### H1 — App Insights 저하 구간 재현

동일한 8KB 요청을 처리할 때 App Insights sampling 100% + request body 8KB 로깅은 metadata-only 기준선보다 먼저 성능 SLO를 위반한다.

- **공식 근거**: App Insights 로깅은 1,000 RPS 초과 내부 테스트에서 throughput 40~50% 감소가 관측됐고, body 로깅 생략이 성능 완화책으로 권고된다. 정확한 `R*`와 감소 폭은 본 환경에서 다시 측정한다.
- **통과 조건**: metadata-only 기준선 `N8`은 통과하지만 App Insights `A8`은 실패하는 가장 낮은 offered RPS `R*`가 반복 측정에서 재현된다.
- **의미**: `R*`가 없으면 Event Hub가 회복할 App Insights 성능 손실도 없으므로 이후 비교를 진행하지 않는다.
- **실패 시 결론**: "본 조건에서 App Insights 8KB의 처리량 저하 구간을 재현하지 못해 Event Hub 회복 가설을 평가할 수 없음."

### H2 — Event Hub 8KB 처리량 회복

H1에서 확정한 `R*`에서 Event Hub `E8`은 8KB body를 전달하면서 성능 SLO와 감사 완전성 기준을 모두 충족한다.

- **공식 근거**: Event Hubs는 고처리량 수집과 생산·소비 분리를 제공하고, `log-to-eventhub`는 App Insights sampling과 무관하게 모든 정책 호출에 실행된다.
- **검증 공백**: 공식 문서는 APIM throughput 무저하를 직접 보장하지 않으므로 이 가설을 실측해야 한다.
- **통과 조건**: `E8`이 `R*`에서 성공 처리량, 오류율, p99, 감사 완전성 기준을 모두 통과한다.
- **의미**: Event Hub가 더 빠르다는 뜻이 아니라 App Insights에서 잃은 처리량을 동일한 8KB 감사 payload로 확보했다는 뜻이다.

### H3 — Event Hub 대용량 처리량 보장 범위

`R*`를 고정한 상태에서 Event Hub payload를 32/64/128/200KB로 늘려도 일정 범위까지 성능 SLO와 감사 완전성을 함께 충족한다.

- **공식 근거**: `log-to-eventhub`의 정책상 최대 메시지 크기는 200KB이며 초과 메시지는 자동 절단된다.
- **검증 공백**: 200KB는 크기 상한이지 성능 보장값이 아니므로 각 크기를 직접 측정한다.
- **통과 조건**: `E32`, `E64`, `E128`, `E200`을 순서대로 평가해 모든 기준을 연속으로 통과한 최대 크기를 보장 범위로 선언한다.
- **부분 통과 예시**: 64KB까지 통과하고 128KB에서 실패하면 "최대 64KB까지 검증"으로 기록한다.
- **금지**: 200KB를 실제로 통과하지 않았다면 정책의 문서상 상한만으로 "200KB 성능 보장"이라고 쓰지 않는다.

### H4 — 감사 완전성

Event Hub 성능 셀에서 APIM이 성공 처리한 모든 요청의 고유 ID가 Event Hub에서 확인된다.

- 누락 요청 수: **0**
- 고유 수신율: **100%**
- drain 종료 후 지연 도착 요청 수와 최대 전달 지연을 별도 보고
- 중복 이벤트 수와 중복률을 별도 보고
- 셀당 성공 요청이 최소 30,000건이고 누락이 0이면, 관측되지 않은 손실률의 95% 상한을 `3/N`으로 함께 보고한다.

H4를 통과하지 못하면 성능 지표가 좋아도 해당 셀은 실패다.

### 선택 가설 O1 — Event Hubs 용량 한계

고정된 낮은 Event Hubs 용량에서 payload × RPS를 높여 throttle, drop 또는 수신 누락이 시작되는 지점을 찾는다.

이 실험은 **선택 사항**이며 H1~H4의 주 실험과 분리한다. 주 실험에서는 Event Hubs 용량 부족이 APIM 로깅 방식의 성능 결과를 오염시키지 않도록 충분한 고정 용량을 사전 할당한다.

---

## 3. 실험 구성

모든 구성은 같은 APIM 인스턴스, API, 요청 body, 응답 크기, 정책 순서와 공통 진단을 사용한다. 조건별 차이는 body를 어느 sink로 보내는지뿐이다.

| ID | 감사 레코드 | App Insights | Event Hub | 목적 |
|---|---:|---|---|---|
| `N8` | 8KB | sampling 100%, body 0B | 없음 | H1/H2의 8KB metadata-only 기준선 |
| `A8` | 8KB | sampling 100%, request body 8KB | 없음 | App Insights 저하 재현 |
| `E8` | 8KB | sampling 100%, body 0B | 감사 레코드 8KB | 동일 크기 Event Hub 비교 |
| `N32` | 32KB | sampling 100%, body 0B | 없음 | 32KB 운송·파싱 기준선 |
| `E32` | 32KB | sampling 100%, body 0B | 감사 레코드 32KB | EH 32KB |
| `N64` | 64KB | sampling 100%, body 0B | 없음 | 64KB 운송·파싱 기준선 |
| `E64` | 64KB | sampling 100%, body 0B | 감사 레코드 64KB | EH 64KB |
| `N128` | 128KB | sampling 100%, body 0B | 없음 | 128KB 운송·파싱 기준선 |
| `E128` | 128KB | sampling 100%, body 0B | 감사 레코드 128KB | EH 128KB |
| `N200` | 200KB | sampling 100%, body 0B | 없음 | 200KB 운송·파싱 기준선 |
| `E200` | 200KB | sampling 100%, body 0B | 감사 레코드 200KB | EH 200KB |

### 3.1 왜 크기별 `N` 기준선이 필요한가

큰 요청은 Event Hub를 사용하지 않아도 네트워크 전송, TLS, APIM request buffering과 body 파싱 비용이 증가한다. `E200`만 측정하면 200KB 요청 자체의 비용과 Event Hub 로깅 비용을 구분할 수 없다.

각 `E<size>`는 같은 크기의 `N<size>`와 함께 측정한다.

- `N<size>`도 `R*`를 통과하지 못하면 해당 크기는 APIM 또는 부하 생성기의 payload 처리 한계이므로 Event Hub 실패로 판정하지 않는다.
- `N<size>`는 통과하지만 `E<size>`만 실패하면 Event Hub 로깅 또는 Event Hubs 용량의 영향으로 판정한다.

### 3.2 감사 레코드와 응답

- 요청 body 자체를 정확히 8/32/64/128/200KB인 비압축 JSON 감사 레코드로 만든다.
- 감사 레코드는 `requestId`, 클라이언트 송신 시각, 전체 레코드 크기, payload hash와 padding payload를 포함한다.
- `log-to-eventhub`는 별도 JSON envelope를 추가하지 않고 요청 body를 그대로 보낸다.
- 이 문서의 8~200KB는 실제 body 데이터만의 크기가 아니라 `log-to-eventhub`가 보내는 **전체 메시지 content 크기**다.
- `E200`은 metadata를 포함한 전체 content가 정확히 200KB 이하여야 한다. 200KB body에 envelope를 추가해 정책 상한을 넘기는 구성을 사용하지 않는다.
- 응답은 모든 조건에서 동일한 작은 고정 body를 반환한다.
- 백엔드는 호출하지 않고 `return-response`를 사용한다.

큰 응답을 되돌려 부하 생성기 다운로드 대역폭이 결과를 지배하는 기존 방식은 사용하지 않는다.

---

## 4. 고정 인프라 조건

### 4.1 APIM

- SKU: **Basic v2**
- unit: **1 고정**
- APIM autoscale 설정: **없음**
- 리전: 단일 리전
- multi-region: 사용하지 않음
- 배포 후 워밍업과 안정화 완료 뒤 측정
- 테스트 중 SKU, unit, zone, network, custom domain, certificate와 기타 인프라 변경 금지

각 런 전후 다음을 JSON으로 저장한다.

- SKU와 unit 수
- autoscale 설정 전체
- provisioning state
- gateway URL과 리전
- API revision
- API 및 diagnostic policy hash
- App Insights sampling과 body byte 설정

Microsoft 문서는 APIM unit의 calls/sec를 대략적인 용량 계획값으로 설명하며, 실제 throughput과 latency는 연결, 정책, request/response 크기와 backend latency에 따라 달라진다고 명시한다. 따라서 Basic v2의 공개 RPS 값을 실험 입력으로 가정하지 않고 본 배포의 `R*`를 직접 찾는다.

### 4.2 Event Hubs

- auto-inflate: **OFF**
- partition 수: 주 실험 전체에서 고정
- partition key: 모든 이벤트가 한 partition에 쏠리지 않도록 미지정 또는 균등 분배가 검증된 키 사용
- consumer group: 실험 전용
- retention: 전체 실행과 drain 시간을 포함하도록 설정

주 실험의 고정 ingress 용량은 다음 식으로 사전 산정한다.

```text
required_ingress_bytes_per_sec
  = R* × 실제 직렬화된 EH 메시지 평균 바이트 × 1.30
```

30%는 envelope, 크기 편차와 순간 burst 여유다. 필요한 고정 용량을 SKU 한도 안에서 확보할 수 없으면 다음 중 하나를 선택하고 결과에 명시한다.

1. 자동확장 없이 충분한 고정 용량을 제공하는 상위 Event Hubs tier 사용
2. 해당 payload 크기를 "인프라 용량 부족으로 평가 불가" 처리

용량이 부족한 상태에서 나온 throttle/drop을 `log-to-eventhub` 정책의 APIM 성능 실패로 해석하지 않는다.

### 4.3 Azure Load Testing

- engine instance 수: 테스트 시작 전에 고정
- 테스트 도중 engine 수 변경 또는 자동 증가 없음
- engine당 thread 상한은 목표 offered RPS를 안정적으로 생성할 만큼 사전 산정
- 부하 생성기 리전 고정
- 연결 재사용, TLS, timeout과 retry 정책을 모든 셀에서 동일하게 유지
- HTTP client retry: **OFF**. 재시도는 원래 요청과 실패를 숨기므로 사용하지 않는다.

부하 생성기 CPU 또는 네트워크가 70%를 넘거나 목표 offered RPS의 99%를 생성하지 못한 런은 무효다.

---

## 5. 부하 모델

### 5.1 open workload 사용

고정 VU의 closed-loop 모델은 응답이 느려질수록 다음 요청도 늦게 보내므로 실제 offered RPS가 자동으로 감소한다. 이는 포화 시 성능 저하를 숨긴다.

본 실험은 **고정 도착률 open workload**를 사용한다.

- 입력: offered RPS
- 결과: achieved RPS, successful RPS, 오류율, latency
- 포화되더라도 offered RPS를 유지한다.

### 5.2 런 구조

각 측정 런은 다음 구간으로 나눈다.

| 구간 | 시간 | 집계 여부 |
|---|---:|---|
| ramp | 60초 | 제외 |
| stabilization | 60초 | 제외 |
| steady-state | 기본 300초, 최소 30,000 성공 요청까지 연장 | 포함 |
| EH drain | 최대 10분 또는 2분 연속 신규 이벤트 없음 | 감사 완전성만 집계 |

APIM 또는 정책 배포 직후 첫 런은 워밍업으로 폐기한다. 구성 전환 후에는 정책 전파가 완료됐음을 확인한 뒤 시작한다.

---

## 6. 단계별 실행

### Phase 0 — 계측과 부하 생성기 검증

1. 낮은 부하에서 `N8`, `A8`, `E8`의 정책 차이가 의도대로인지 확인한다.
2. `requestId`가 APIM 성공 요청과 EH 메시지에서 동일하게 조회되는지 확인한다.
3. App Insights `A8`에 8KB body가 저장되는지 확인한다.
4. `E8`의 실제 직렬화 메시지 크기를 측정한다.
5. 부하 생성기가 목표 RPS의 99% 이상을 안정적으로 생성하는지 확인한다.
6. APIM, Event Hubs와 부하 생성기에서 autoscale 또는 실행 중 용량 변경이 없음을 확인한다.

Phase 0 실패 시 본 측정을 시작하지 않는다.

### Phase 1 — App Insights 저하 구간 `R*` 탐색

#### 1차 탐색

- `N8`과 `A8`을 같은 offered RPS에서 교차 실행한다.
- 낮은 RPS에서 시작해 `100 → 200 → 400 → 800 → ...`처럼 증가한다.
- Basic v2의 공개 처리량을 최대치로 가정하지 않는다.
- `N8`이 아직 SLO를 통과하는 동안 `A8`이 처음 실패한 구간을 찾는다.
- 탐색 런은 셀당 1회이며 최종 증거로 사용하지 않는다.

#### 2차 정밀 탐색

- 1차 탐색에서 찾은 경계의 상·하한 사이를 약 10% 간격으로 나눈다.
- 각 지점에서 `N8`과 `A8`을 최소 3회 실행한다.
- 후보 `R*`와 바로 아래 지점을 선정한다.

#### 3차 확증

- 후보 `R*`에서 `N8`과 `A8`을 각각 **5회** 실행한다.
- 실행 순서는 `N8/A8`을 무작위화하되 각 조건이 앞·뒤 위치를 고르게 경험하게 한다.
- 시간대 drift 확인을 위해 `N8`을 블록 시작과 끝에 배치한다.

`R*`는 5회 확증에서 다음 조건을 만족하는 가장 낮은 offered RPS다.

- `N8`: 5회 모두 런별 SLO 통과
- `A8`: 5회 중 최소 4회가 같은 성능 SLO 항목을 위반
- `A8`의 위반 항목은 95% 신뢰구간 기준으로도 SLO 경계를 넘음

### Phase 2 — Event Hub 8KB 회복 검증

`R*`를 고정하고 `N8`, `A8`, `E8`을 각각 5회 균형·무작위 순서로 실행한다.

- `A8` 실패가 다시 재현되어야 한다.
- `E8`은 성능 SLO와 감사 완전성을 모두 통과해야 한다.
- `A8`이 Phase 2에서 더 이상 실패하지 않으면 환경 drift로 간주하고 `R*`를 다시 탐색한다.

### Phase 3 — Event Hub payload 확장 검증

각 크기에서 `N<size>`와 `E<size>`를 `R*`로 각각 5회 실행한다.

```text
N32 ↔ E32
N64 ↔ E64
N128 ↔ E128
N200 ↔ E200
```

- 각 크기 블록의 실행 순서는 교차·무작위화한다.
- 앞 크기가 실패해도 이후 크기를 최소 1회 진단 실행해 단조성 위반이나 일시적 이상을 확인한다.
- 보장 범위는 **연속으로 통과한 최대 크기**까지만 선언한다.
- `N<size>`가 먼저 실패하면 그 크기는 EH 판정에서 제외하고 APIM/부하 생성기 payload 한계로 별도 보고한다.

### Optional Phase 4 — Event Hubs 고정 용량 한계

주 실험 완료 후 별도 실행한다.

- Event Hubs를 Standard 1 TU, auto-inflate OFF 등 의도한 고정 저용량으로 설정한다.
- APIM과 부하 생성기 조건은 유지한다.
- payload × RPS를 높이며 throttle, drop, lag와 누락이 시작되는 지점을 찾는다.

이 결과는 "저용량 Event Hubs 구성의 한계"이며 Phase 2~3의 APIM + EH 성능 보장 결과와 합치지 않는다.

---

## 7. 성능 SLO와 판정 규칙

### 7.1 런별 필수 지표

- offered requests
- generated requests
- APIM total requests
- APIM successful requests
- successful RPS
- 오류 수와 오류율
- HTTP status별 수
- p50, p95, p99
- APIM `CpuPercent_Gateway`의 avg/max
- APIM gateway time의 p50/p95/p99
- Event Hubs incoming events/bytes, throttled requests, server errors
- EH consumer lag
- 고유 송신/수신 ID, 누락 ID, 중복 ID

`peak RPS` 한 개를 대표 처리량으로 사용하지 않는다. ramp와 stabilization을 제외한 300초 steady-state 전체의 successful RPS를 사용한다.

### 7.2 공통 성능 SLO

각 유효 런은 다음을 모두 만족해야 한다.

| 항목 | 통과 기준 |
|---|---|
| 부하 생성 성공 | generated requests / offered requests ≥ 99% |
| APIM 성공 처리 | successful requests / offered requests ≥ 99% |
| 오류율 | ≤ 1% |
| p99 | 같은 크기 `N<size>` p99의 120% 이하 |
| 자동 용량 변경 | 0회 |

H1의 `N8`은 자기 자신과 p99를 비교할 수 없으므로 저부하 `N8` p99의 2배와 50ms 중 큰 값을 실험 SLO로 사용한다. `A8`과 `E8`은 같은 블록의 `N8` p99 120% 기준도 함께 적용한다.

### 7.3 감사 완전성 SLO

각 `E<size>` 셀은 drain 완료 후 다음을 만족해야 한다.

| 항목 | 통과 기준 |
|---|---|
| 고유 수신율 | 100% |
| 누락 요청 | 0건 |
| payload 크기 | 정책상 기대 크기와 일치 |
| payload hash | 송신 hash와 일치 |
| 중복률 | 보고 필수, 0.01% 초과 시 실패 |
| 최소 성공 요청 | 셀당 30,000건 |

EH metric의 `0 dropped`만으로 무손실을 선언하지 않는다. APIM 성공 요청 ID 집합과 EH 소비 ID 집합을 직접 대조한다.

### 7.4 반복 셀 판정

- 구성별 확증 반복: 5회
- 최소 유효 반복: 5회
- 한 런이 무효화되면 같은 블록 안에서 재실행
- 모든 반복값, 평균, 중앙값과 min/max 보고
- successful RPS와 latency는 bootstrap 95% 신뢰구간, 성공률·오류율·수신율은 Wilson 95% 신뢰구간 보고
- 평균만 통과하고 일부 반복이 SLO를 위반하면 통과로 판정하지 않는다.

---

## 8. 자동 확장과 교란 제거 체크리스트

다음 항목은 각 실험 블록 시작 전과 종료 후 모두 확인한다.

- [ ] APIM Basic v2, 1 unit
- [ ] APIM autoscale 설정 없음
- [ ] APIM 리전과 unit 수 변경 없음
- [ ] APIM provisioning state가 `Succeeded`
- [ ] Event Hubs auto-inflate OFF
- [ ] Event Hubs TU/PU/CU 수 고정
- [ ] Event Hubs partition 수 고정
- [ ] Azure Load Testing engine 수 고정
- [ ] 부하 생성기 CPU/네트워크 < 70%
- [ ] 목표 offered RPS의 99% 이상 생성
- [ ] API revision과 policy hash 동일
- [ ] App Insights sampling 100%
- [ ] 공통 GatewayLogs 설정 동일
- [ ] retry OFF
- [ ] backend 호출 없음
- [ ] 리전 간 경로 변경 없음
- [ ] Azure resource health 이상 없음

하나라도 충족하지 못하면 해당 런은 최종 판정에서 제외하고 제외 사유를 기록한다.

---

## 9. 원시 증거와 재현성

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
- APIM resource ID, SKU, unit, 리전
- Event Hubs resource ID, tier, 고정 용량, partition 수
- load engine 수
- Git commit SHA
- JMX/config/policy hash
- App Insights diagnostic 설정
- warm-up 여부
- 유효/무효 판정과 사유

결과 보고서는 이 원시 데이터에서 다시 생성할 수 있어야 한다. 수기로 옮긴 평균값만으로 결론을 만들지 않는다.

---

## 10. 최종 결과표 형식

### 10.1 H1 — `R*` 확정

| offered RPS | N8 성공 RPS / 오류 / p99 | A8 성공 RPS / 오류 / p99 | 판정 |
|---:|---|---|---|
| 실측값 | 실측값 | 실측값 | 탐색/후보/확정 |

### 10.2 H2 — 8KB 회복

| 조건 | 성공 RPS 95% CI | 오류율 | p99 | APIM CPU | 고유 수신율 | 누락 | 판정 |
|---|---:|---:|---:|---:|---:|---:|---|
| N8 |  |  |  |  | 해당 없음 | 해당 없음 |  |
| A8 |  |  |  |  | 해당 없음 | 해당 없음 |  |
| E8 |  |  |  |  |  |  |  |

### 10.3 H3 — EH 보장 크기

| 크기 | N 통과 | E 성공 RPS 95% CI | 오류율 | p99 | 고유 수신율 | 누락 | EH throttle | 판정 |
|---:|---|---:|---:|---:|---:|---:|---:|---|
| 32KB |  |  |  |  |  |  |  |  |
| 64KB |  |  |  |  |  |  |  |  |
| 128KB |  |  |  |  |  |  |  |  |
| 200KB |  |  |  |  |  |  |  |  |

---

## 11. 허용되는 최종 결론

### 전체 통과

> Basic v2 1 unit에서 App Insights sampling 100% + 8KB body 로깅은 R\*에서 성능 SLO를 위반했다. 동일 R\*에서 Event Hub는 최대 N KB payload까지 successful RPS, 오류율, p99와 전건 수신 기준을 모두 충족했다. 따라서 본 실험 범위에서는 App Insights 8KB로 인해 잃은 처리량을 Event Hub가 더 큰 감사 payload에서도 확보했다.

### 부분 통과

> Event Hub는 동일 R\*에서 최대 N KB까지 통과했으나 다음 크기에서 성능 또는 감사 완전성 기준을 위반했다. 보장 범위는 N KB까지다.

### 비교 전제 실패

> App Insights 8KB의 재현 가능한 저하 구간 R\*를 찾지 못해 Event Hub의 처리량 회복 여부를 평가하지 못했다.

### Event Hubs 용량 부족

> 고정 Event Hubs ingress 용량이 요구량보다 작아 throttle 또는 누락이 발생했다. 이 결과는 APIM `log-to-eventhub` 방식의 성능 실패가 아니라 sink provisioning 한계이며, 충분한 고정 용량으로 재실험해야 한다.

### 금지되는 결론

- "Event Hub가 APIM을 더 빠르게 만든다."
- "Event Hub는 모든 환경에서 성능 저하가 없다."
- "정책 상한이 200KB이므로 200KB에서도 성능이 보장된다."
- "EH metric에서 drop이 0이므로 전건 무손실이다."
- "Basic v2 결과가 Standard v2 또는 운영 API에도 그대로 적용된다."

---

## 12. 공식 근거

- [Upgrade and scale an Azure API Management instance](https://learn.microsoft.com/azure/api-management/upgrade-and-scale)  
  APIM unit의 calls/sec는 대략적인 최대 throughput이며 실제 성능은 연결, 정책, payload와 backend latency에 따라 달라지므로 현실적인 API 시나리오에서 측정해야 한다.
- [Integrate Azure API Management with Application Insights](https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights#performance-implications-and-log-sampling)  
  sampling과 body logging의 성능 영향 및 고처리량 API에서의 제한.
- [`log-to-eventhub` policy](https://learn.microsoft.com/azure/api-management/log-to-eventhub-policy)  
  App Insights sampling의 영향을 받지 않으며 정책 호출마다 실행되고 메시지 크기 상한은 200KB다.
- [Log API Management events to Azure Event Hubs](https://learn.microsoft.com/azure/api-management/api-management-howto-log-event-hubs)  
  Event Hubs 기반 로깅 구성과 생산·소비 분리.

---

## 13. 실행 전 승인 게이트

- [ ] Basic v2 1 unit 비용 승인
- [ ] Event Hubs 주 실험 고정 용량 산정 및 비용 승인
- [ ] open workload가 목표 RPS를 유지하는지 사전 검증
- [ ] 셀당 5회, steady-state 5분 실행 시간 승인
- [ ] 고유 request ID 전수 저장과 EH 소비·대조 구현 확인
- [ ] 원시 데이터 보존 위치 확인
- [ ] Optional Phase 4 실행 여부 별도 결정
