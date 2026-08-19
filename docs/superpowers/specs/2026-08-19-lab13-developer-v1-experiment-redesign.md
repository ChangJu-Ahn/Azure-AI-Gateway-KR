# Lab 13 Developer v1 실험 재설계

## 목적

기존 APIM Developer v1 인스턴스를 활용해 비용을 제한하면서 다음 두 질문에 답한다.

1. App Insights sampling 100%와 8KB body 로깅은 500 offered RPS에서 APIM 성능 또는 자원 사용에 어떤 영향을 주는가?
2. Event Hub는 모든 요청의 8KB 또는 64KB 로그를 전달하면서 같은 500 RPS SLO를 만족하는가?

이 설계는 Basic v2의 포화점 R* 또는 200KB 한계를 검증하지 않는다. 결론은 사용한 Developer v1 인스턴스, 정책, 리전과 측정 시점에만 적용한다.

## 구성

| ID | 요청 감사 레코드 | App Insights | Event Hub |
|---|---:|---|---|
| N8 | 8KB | sampling 100%, body 0B | 없음 |
| A8 | 8KB | sampling 100%, body 8KB | 없음 |
| E8 | 8KB | sampling 100%, body 0B | 8KB 전체 메시지 |
| N64 | 64KB | sampling 100%, body 0B | 없음 |
| E64 | 64KB | sampling 100%, body 0B | 64KB 전체 메시지 |

응답은 모든 조건에서 동일한 작은 고정 body이며 backend를 호출하지 않는다.

## H1 — App Insights 8KB의 500 RPS 성능 영향

Developer v1에서 N8과 A8에 동일한 500 offered RPS를 주었을 때 App Insights 100% + 8KB body 로깅이 gateway CPU, p99 또는 성공 처리율에 추가 비용을 만든다.

### 판정

- 리소스 오버헤드 지지:
  - A8 평균 gateway CPU가 N8보다 5%p 이상 높거나
  - A8 p99가 N8보다 20% 이상 높고
  - 세 반복이 모두 같은 방향이다.
- 처리량 저하 확정:
  - N8은 성공 RPS 495 이상이며 오류율 1% 이하인데
  - A8은 성공 RPS 495 미만이거나 오류율이 1%를 초과한다.
- 두 조건이 모두 성립하지 않으면 "본 Developer v1·500 RPS 조건에서는 유의한 저하를 관찰하지 못함"으로 판정한다.

공식 문서의 1,000 RPS 초과 내부 테스트 결과를 500 RPS에 그대로 적용하지 않는다.

## H2 — Event Hub 8KB의 500 RPS 유지

E8이 모든 요청의 8KB 로그를 Event Hub consumer까지 전달하면서 500 RPS SLO를 충족한다.

### 필수 통과 조건

- 부하 생성 성공률 99% 이상
- 성공 RPS 495 이상
- 오류율 1% 이하
- p99가 같은 블록 N8의 120% 이하
- APIM 성공 요청의 모든 고유 ID가 EH consumer에서 확인
- payload hash 일치
- 전체 EH 메시지 크기 8KB 일치

A8도 SLO를 통과하면 Event Hub가 성능 손실을 회복했다고 표현하지 않는다. "Event Hub도 500 RPS를 유지했다"라고만 결론 내리고 CPU와 p99 차이를 별도 보고한다.

## H3 — Event Hub 64KB의 500 RPS 유지

E64가 모든 요청의 64KB 로그를 Event Hub consumer까지 전달하면서 500 RPS SLO를 충족한다.

### 필수 통과 조건

H2와 동일한 기준을 사용하되 p99는 같은 블록 N64와 비교하고 메시지 크기는 64KB여야 한다.

N64가 SLO를 실패하면 E64를 Event Hub 실패로 판정하지 않고 해당 Developer v1 또는 부하 생성기의 64KB 처리 한계로 분리한다.

## 부하와 반복

- offered RPS: 500 고정
- 부하 모델: open workload
- 부하 생성기: Japan East의 고정 단일 Standard_D8as_v5 Linux VM + k6
- autoscale: 사용하지 않음
- 조건별 반복: 3회
- 실행 수:
  - N8/A8/E8 각 3회 = 9회
  - N64/E64 각 3회 = 6회
  - 합계 15회
- 런 구조:
  - ramp 60초
  - stabilization 60초
  - steady-state 300초
  - EH 조건은 consumer drain 후 대조 완료
- 실행 순서: 조건이 앞·중간·뒤 위치를 고르게 경험하도록 블록별 균형 무작위화
- 한 반복만 반대 방향이거나 판정 경계에 있으면 해당 셀만 2회 추가

## 부하 생성기 유효성

다음 중 하나라도 발생하면 런을 무효화한다.

- VM CPU 평균 70% 초과
- VM network가 공식 최대치의 70% 초과
- k6 dropped iterations 발생
- generated/offered requests 99% 미만
- socket 또는 TLS 오류

## Event Hubs 고정 조건

### E8

- 예상 payload ingress: 약 4.1MB/s
- Standard 5 TU 이상 고정

### E64

- 예상 payload ingress: 약 32.8MB/s
- Standard 40 TU 고정
- auto-inflate OFF
- 실제 직렬화 메시지가 64KB를 넘지 않도록 요청 body 자체를 EH content로 사용
- 실험 중 TU와 partition 수 변경 금지

EH throttling, server error 또는 consumer lag가 발생하면 APIM 성능과 별도로 sink 용량 조건 실패를 보고한다. 모든 요청 수신 조건을 충족하지 못하면 H2 또는 H3는 실패다.

## 수집 지표

- k6: offered/generated/successful RPS, 오류율, p50/p95/p99, dropped iterations
- APIM: CpuPercent_Gateway avg/max, 전체·성공·실패 요청 수
- Event Hubs: incoming requests/bytes, throttled requests, server errors, consumer lag
- 대조: 성공 request ID 집합, EH 수신 ID 집합, 누락·중복 ID, payload hash와 메시지 크기

GatewayLogs 전체 수집은 필수로 두지 않는다. 비용을 줄이기 위해 k6 응답 ID와 EH consumer ID를 권위 데이터로 사용하고, GatewayLogs는 설정 확인용 소량 호출에만 사용한다.

## 허용 결론

### H1 지지

> Developer v1의 본 조건에서 App Insights 100% + 8KB body 로깅은 500 offered RPS에서 기준선 대비 CPU 또는 p99 오버헤드를 보였다.

처리량 SLO까지 실패한 경우에만 처리량 저하를 별도로 명시한다.

### H2 통과

> Developer v1의 본 조건에서 Event Hub는 모든 요청의 8KB 로그를 consumer까지 전달하면서 500 RPS SLO를 충족했다.

### H3 통과

> Developer v1의 본 조건에서 Event Hub는 모든 요청의 64KB 로그를 consumer까지 전달하면서 500 RPS SLO를 충족했다.

## 금지 결론

- Event Hub가 APIM 성능을 향상시킨다.
- App Insights는 항상 APIM throughput을 저하시킨다.
- Developer v1 결과가 Basic v2, Standard v2 또는 운영 API에 그대로 적용된다.
- 500 RPS 통과가 APIM의 최대 처리량 또는 공식 보장 처리량이다.
- EH metric의 drop 0만으로 모든 요청이 전달됐다고 결론 낸다.
- 64KB 통과 결과로 200KB 성능을 추정한다.

## 제외 범위

- Basic v2
- 포화점 R*
- 1,000 RPS 초과 공식 수치 재현
- 32KB, 128KB와 200KB
- Event Hubs 최대 용량 탐색
- Azure Load Testing을 이용한 분산 부하

## 완료 기준

- EXPERIMENT-SPEC.md가 본 설계로 개정된다.
- 기존 Basic v2·R* 설계는 old/에 보존된다.
- H1~H3의 판정 기준과 허용 결론이 서로 일치한다.
- 총 기본 실행 수가 15회로 명시된다.
- 모든 로그 요청은 `모든 요청`으로 표현한다.
- 비용을 키우는 GatewayLogs 전체 수집과 200KB 실험이 필수 범위에서 제외된다.
