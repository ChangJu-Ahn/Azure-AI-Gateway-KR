# Lab 13 최종 결과 보고서 — APIM 로깅 성능·로그 전달 벤치마크

## 검증 범위
- 환경: Azure API Management(APIM) Developer v1 SKU, Korea Central; Basic v2 SKU는 Developer v1과 Basic v2의 8KB 500 RPS 비교 한 건에서만 보았다.
- 조건: 로그 저장소는 App Insights와 Event Hub이며, payload(요청 데이터 크기)는 8KB와 64KB, RPS는 초당 요청 수다.
- 기준선: metadata-only 기준선은 App Insights 메타데이터만 기록한 기준선이고, N8/N64 조건은 App Insights diagnostic을 완전히 끈 상태가 아니다; body bytes만 0이다.
- 정의: 무손실은 요청 로그가 모두 도착했다는 의미이나 요청 단위 증명은 완료되지 않았다; 드롭은 APIM `EventHubDroppedEvents`, Capacity는 classic v1 부하, Duration은 APIM 서버측 처리시간이다.
- 범위: Developer v1 중심, 100~500 RPS, 조건별 3회 반복 미완료 및 조건별 대부분 1회, 즉 대부분 한 번만 실행; 1,000 RPS는 테스트하지 않았다.

## 핵심 결론

| 질문 | 판정 | 핵심 근거 | 고객 의미 |
|---|---|---|---|
| Q1 App Insights 본문 로깅 영향 | 조건부 지지 | A8 Duration이 모든 8KB RPS 포인트에서 N8보다 높음 | body 기록은 처리시간 예산에 넣어야 함 |
| Q2 성능 저하 없는 모든 요청 로깅 | 미검증 | AppRequests 150,178/150,000은 집계상 양립하나 ID 대조 없음 | API 성공과 로그 완전성을 따로 검증해야 함 |
| Q3 Event Hub 무손실 보장 | 반박(본 Developer v1 고부하 조건) | E8 400 RPS부터 APIM-reported drop 관측 | EH 연결만으로 감사 로그 전달을 보장하지 않음 |
| Q4 요청 크기 영향 | 조건부 강함 | 64KB는 Duration과 EH drop 모두 커짐 | payload 크기를 로깅 용량 변수로 관리해야 함 |
| Q5 v1/v2 전달 결과 차이 | 조건부 지지 | Basic v2 EH 도달 수는 500 RPS 발신량과 대체로 일치 | v2가 다르게 관측됐지만 원인 단정은 금물 |

보조 Capacity 관측:

| RPS | N8 Capacity | A8 Capacity | E8 Capacity |
|---:|---:|---:|---:|
| 100 | 31.5% | 39% | 38% |
| 200 | 58% | 66% | 85% |
| 300 | 79% | 88.5% | 86.5% |
| 400 | 85.5% | 84.5% | 85.5% |
| 500 | 약 89% | 약 89% | 약 87% |

해석: 200 RPS에서 E8 Capacity는 85%였고 N8은 58%, A8은 66%였다; 400~500 RPS에서는 세 조건 모두 상단 범위에 가까워 Capacity만으로 로깅 효과를 분리할 수 없었다; 이 단일 실행들에서 보편 Capacity 임계값을 제시하지 않는다.

---

## 질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가
- **가설/판정:** App Insights body 8KB 로깅은 APIM 처리시간을 늘린다; **판정:** 조건부 지지 — CPU/p99/3회 반복은 부족하지만 Duration 방향은 일관됐다.
- **핵심 근거:** 100/200/300/400/500 RPS 포인트에서 A8이 N8 metadata-only 기준선보다 높았다.

| RPS | N8 — App Insights 메타데이터만 기록한 기준선 Duration | A8 — App Insights body 8KB Duration |
|---:|---:|---:|
| 100 | 0.01 ms | 0.03 ms |
| 200 | 0.02 ms | 0.05 ms |
| 300 | 0.06 ms | 0.13 ms |
| 400 | 0.03 ms | 0.64 ms |
| 500 | 0.1~0.35 ms | 0.9~2.5 ms |

**결론:** 본 환경의 8KB body 로깅은 고객 처리시간 예산에 포함해야 한다.

## 질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가
- **가설:** 성능 저하 없이 모든 요청 로그를 남길 수 있다.
- **판정:** 미검증 — 완전성과 무저하를 동시에 입증하지 못했다.
- **핵심 근거:** App Insights AppRequests 집계는 A8 500 RPS에서 150,178건으로 150,000 offered와 누락 없음에 양립하지만, 요청 단위 완전성 증명은 아니다.
- **반례:** E8 500 RPS는 클라이언트 150,000건이 모두 200이어도 APIM Event Hub drop을 대량 보고했다.
**결론:** 고객에게는 API 성공 SLO와 로깅-delivery SLO를 분리해 제시해야 한다.

## 질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가
- **가설:** Event Hub 연결은 요청 로그를 손실 없이 전달한다.
- **판정:** 반박(본 Developer v1 고부하 조건) — API 200 성공과 별도로 APIM-reported drop이 발생했다.
- **핵심 근거:** E8 400 RPS 2,933 drop과 500 RPS 대량 drop이 먼저 관측됐다; EH 스로틀링은 측정창 집계에서 0으로 확인됐고, RPS 구간별 개별 확인은 일부만 기록됐다.

| 조건 | RPS | 클라이언트 성공 | APIM-reported EH drop | 해석 |
|---|---:|---:|---:|---|
| E8 | 300 | 54,000 / 54,000 | 0 | 이 관측 창에서는 APIM drop 보고 없음 |
| E8 | 400 | 72,000 / 72,000 | 2,933 | API 성공과 로그 전달 실패가 분리됨 |
| E8 | 500 | 150,000 / 150,000 | 대량, 약 절반으로 기록됨 | 정확한 비율은 미확정 |

**결론:** Event Hub 자체가 아니라 APIM EH 성공/drop과 Event Hubs ingress/throttling을 함께 보아야 한다.

## 질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가
- **가설:** payload 증가가 Duration과 로깅 전달 범위를 악화시킨다.
- **판정:** 조건부 강함 — 64KB 두 포인트 모두 drop을 동반했고 Duration도 8KB보다 컸다.
- **핵심 근거:** E64 300 RPS는 N64보다 Duration이 낮지만 APIM-reported drop 41,435건이 함께 발생했다.

| RPS | N64 — App Insights 메타데이터만 기록한 기준선 Duration | E64 — Event Hub 64KB Duration | E64 APIM-reported EH drop |
|---:|---:|---:|---:|
| 300 | 6.04 ms | 5.24 ms | 41,435 |
| 500 | 7.32 ms | 7.58 ms | 76,434 |

**결론:** Duration은 로그 전달 완전성 지표가 아니며, 순수 EH 로깅 비용이나 더 나은 성능으로 해석하지 않는다.

## 질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가
- **가설:** SKU/세대 변경 시 Event Hub 전달 관측 결과가 달라질 수 있다.
- **판정:** 조건부 지지 — Basic v2 관측 결과는 Developer v1과 다르지만 원인을 SKU 하나로 단정하지 않는다.
- **핵심 근거:** 동일 8KB 500 RPS E8 비교에서 EH 도달 수와 drop 지표가 서로 다른 방식으로 수집됐다.

| 지표 | Developer v1 관측 | Basic v2 관측 | 주의점 |
|---|---|---|---|
| EH 도달 | 약 절반만 도달한 것으로 기록, 대량 drop | 분당 약 30,000건 수준: 30056, 29900, 29926, 30108, 29796, 30186 | Basic v2는 EH 도달 수로 판단 |
| APIM EventHubDroppedEvents | 대량 drop 보고 | 직접 비교 가능한 drop 카운터 확보 못 함 | v1과 v2 지표가 달라 직접 비교 제한 |
| EH throttling | 0 | 0 | EH가 throttle한 증거는 없음 |
| 클라이언트 결과 | 요청 200 성공, p99 약 500 ms | 요청 200 성공, p99 약 30 ms | 클라이언트 p99는 참고 지표 |
| 게이트웨이 리소스 | classic Capacity 관측 | v2 CPU/메모리 미수집 | 메커니즘 확정 불가 |

**결론:** v2 효과를 고객 권고로 쓰려면 같은 지표 집합으로 재시험해야 한다.

---

## 고객 운영 권고
1. API 성공 SLO와 로깅-delivery SLO를 분리하고 downstream consumer 처리 성공률, APIM EH success/drop, Event Hubs ingress/throttling을 함께 본다.
2. runbook에 경보 대응을 두고 운영 목표 peak RPS × logged payload size로 capacity-test하며 retention/reprocessing 요구량을 포함한다.
3. v1은 classic Capacity, v2는 gateway CPU/Memory 계열 지표를 수집한다.
4. audit scope, retention, cost, PII masking을 정하고 기록할 본문 크기를 최소화한다.
5. 고객 환경에서 재시험해 region, SKU, unit 수, backend 지연, policy 조합을 반영한다.

## 한계
- 조건별 3회 반복 계획은 완료되지 않았고 조건별 대부분 1회, 즉 대부분 한 번만 실행했다.
- 요청 ID 집합, 페이로드 해시, 메시지 크기 대조는 완료되지 않았고 App Insights count 150,178에는 warmup 경계 records가 포함될 수 있다.
- 클라이언트 p95/p99에는 load-generator/TLS artifacts가 섞일 수 있어 서버측 Duration과 구분한다.
- v1과 v2의 지표 수집 범위가 달라 직접 비교가 제한된다: v2 CPU/메모리, v2 Duration, v2 drop 카운터가 없어 메커니즘은 미검증이고 1,000 RPS와 production multi-unit/region/backend scenarios도 미검증이다.

## 원천 문서

| 문서 | 역할 |
|---|---|
| `EXPERIMENT-SPEC.md` | 원래 가설, 성공 조건, 측정 계획 |
| `EXPERIMENT-LOG.md` | 실제 실행 창, RPS, 수치 출처 |
| `old/RESULTS-Old.md` | 보관된 이전 결과 원문 |
| `old/REVIEW.md` | 보관된 검토 근거 |
| `DECISION-TREE.md` | 앞선 의사결정 가이드; 손실 여부·임계값·지연·인과 표현이 충돌하면 활성 RESULTS.md가 우선한다 |
| `REPORT.html` | 시각 보고서 참조; 활성 고객 결과보고서는 이 문서다 |
