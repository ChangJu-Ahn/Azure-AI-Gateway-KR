# Lab 13 최종 결과 보고서 — APIM 로깅 성능·로그 전달 벤치마크

## 용어와 검증 범위

이 보고서는 Azure API Management(APIM)에서 App Insights body 로깅과 `log-to-eventhub` 기반 Event Hub 전달을 비교한 고객용 최종 결과다. 판정은 `EXPERIMENT-SPEC.md`, `EXPERIMENT-LOG.md`, 그리고 보관된 검토 근거 `old/REVIEW.md`에 맞춰 증거 범위를 제한했다.

- **로그 저장소**: APIM 로그를 남기는 대상이다. 이 실험에서는 App Insights와 Event Hub를 비교했다.
- **무손실**: 요청 로그가 빠짐없이 도착했다는 뜻으로 쓰지만, 본 실험에서는 요청 단위 증명은 완료되지 않았다. 집계가 무손실과 양립하는 경우도 전건 요청 ID 대조와는 구분한다.
- **드롭**: 이 보고서의 Event Hub 드롭은 APIM `EventHubDroppedEvents`가 보고한 값이다. API 응답 실패와 같은 의미가 아니다.
- **RPS**: 초당 요청 수다. 본 실험의 활성 판정은 100~500 RPS 관측 창에 한정한다.
- **payload / 요청 데이터 크기**: 요청 body 크기다. 본 실험은 8KB와 64KB만 측정했다.
- **SKU**: APIM 성능 티어와 세대다. Developer v1을 중심으로 측정했고 Basic v2는 8KB 500 RPS 비교 한 건만 포함했다.
- **Capacity**: classic v1 APIM의 종합 부하 지표다. v2에서는 같은 의미로 비교하지 않고 CPU/메모리 지표가 필요하다.
- **Duration**: APIM 서버측 처리시간 지표다. 로그 전달 완전성 지표가 아니다.
- **metadata-only 기준선**: N8/N64 조건은 App Insights diagnostic을 완전히 끈 상태가 아니다. 모든 조건에 공통으로 켜진 App Insights 메타데이터만 기록한 기준선이다.
- **범위**: Korea Central의 기록된 APIM 배포, Developer v1과 Basic v2의 8KB 500 RPS 비교 한 건, 8KB·64KB 요청, 100~500 RPS 관측 창, 조건별 대부분 한 번만 실행한 결과에 한정한다. 1,000 RPS는 테스트하지 않았다. 제품 일반 보증이나 다른 SKU·region·backend 구성의 보증으로 확장하지 않는다.

## 요약

1. **App Insights 본문 로깅은 처리시간을 늘렸다.** 기록된 8KB RPS 포인트에서 A8 Duration은 App Insights 메타데이터만 기록한 기준선보다 높았다. 다만 사전 명세의 CPU/p99/3회 반복 기준은 그대로 수행되지 않았다.
2. **App Insights 집계는 무손실과 양립하지만 요청 단위 증명은 아니다.** A8 500 RPS 관측 창의 AppRequests 수는 발신 요청 수 이상이었지만, warmup 혼입과 요청 ID 대조 부재 때문에 전건 단위 증명으로 보지는 않는다.
3. **API 성공과 Event Hub 로그 전달 성공은 별개다.** E8/E64 런에서 클라이언트 요청은 200으로 성공할 수 있었고, 동시에 APIM은 Event Hub drop을 보고했다.
4. **관측된 드롭은 EH 스로틀링으로 설명되지 않았다.** EH 스로틀링은 측정창 집계에서 0으로 확인됐고, RPS 구간별 개별 확인은 일부만 기록됐다. 따라서 본 관측값은 EH throttling 때문이라는 설명과 맞지 않는다.
5. **8KB 드롭 전이는 300~400 RPS 사이에서 관측됐다.** E8에서 APIM-reported drop은 300 RPS에서 0, 400 RPS에서 2,933, 500 RPS에서 대량으로 기록됐다.
6. **큰 요청은 처리시간과 로깅 운영 범위에 영향을 줬다.** 64KB 요청은 metadata-only 기준선에서도 8KB보다 Duration이 뚜렷하게 높았고, E64는 300·500 RPS 모두에서 APIM-reported drop이 있었다.
7. **Developer v1과 Basic v2에서 전달 결과 차이가 관측됐다.** 동일한 8KB 500 RPS E8 비교에서 Developer v1은 대량 drop을 보였고 Basic v2 관측 창은 EH 도달 수가 발신량과 대체로 맞았다. 단, 지표 수집은 비대칭이었다.

---

## 질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가

**판정: 조건부 지지.** 기록된 8KB 조건에서 App Insights body 로깅(A8)의 APIM Duration은 App Insights 메타데이터만 기록한 기준선보다 높았다. 이는 본문 로깅이 게이트웨이 처리시간을 늘렸다는 방향을 지지한다.

| RPS | N8 — App Insights 메타데이터만 기록한 기준선 Duration | A8 — App Insights body 8KB Duration |
|---:|---:|---:|
| 100 | 0.01 ms | 0.03 ms |
| 200 | 0.02 ms | 0.05 ms |
| 300 | 0.06 ms | 0.13 ms |
| 400 | 0.03 ms | 0.64 ms |
| 500 | 0.1~0.35 ms | 0.9~2.5 ms |

Capacity 관측값은 다음과 같다. N은 App Insights 메타데이터만 기록한 기준선이지 diagnostics-off 조건이 아니다.

| RPS | N8 Capacity | A8 Capacity | E8 Capacity |
|---:|---:|---:|---:|
| 100 | 31.5% | 39% | 38% |
| 200 | 58% | 66% | 85% |
| 300 | 79% | 88.5% | 86.5% |
| 400 | 85.5% | 84.5% | 85.5% |
| 500 | 약 89% | 약 89% | 약 87% |

200 RPS에서 E8 Capacity는 85%였고 N8은 58%, A8은 66%였다. 그러나 400~500 RPS에서는 세 조건 모두 상단 범위에 가까워 Capacity만으로 로깅 효과를 분리할 수 없었다. 이 단일 실행들에서 보편 Capacity 임계값을 제시하지 않는다.

고객 해석은 다음 범위가 안전하다. 본 실험의 100/200/300/400/500 RPS 포인트에서는 body 로깅이 Duration을 늘렸다. 그러나 원래 H1은 CPU, p99, 성공 처리율, 조건별 3회 반복을 기준으로 삼았고 실제 실행은 Duration/Capacity 중심의 대부분 1회 측정이었으므로, 공식 문서의 1,000 RPS 초과 처리량 저하 수치를 재현했다고 말하지 않는다.

## 질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가

**판정: 미검증.** 본 실험은 “모든 요청”과 “성능 저하 없음”을 end-to-end로 동시에 증명하지 못했다.

- A8 500 RPS 관측 창에서는 클라이언트 150,000 요청에 대해 AppRequests 150,178건이 조회됐다. 이 집계는 누락 없음과 양립하지만, warmup 잔여가 섞였다고 기록돼 있고 요청 ID별 대조가 없었다.
- E8 500 RPS에서는 클라이언트 요청이 150,000건 모두 200으로 성공했지만 APIM은 Event Hub drop을 대량 보고했다.
- 원래 통과 조건에 있던 성공 요청 ID 집합, EH 수신 ID 집합, 페이로드 해시, 메시지 크기 대조가 최종 판정의 주된 근거로 수집되지 않았다.

따라서 고객에게는 “이번 환경에서는 로깅 방식 선택만으로 무손실과 무저하를 함께 입증하지 못했다”고 말하는 것이 안전하다.

## 질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가

**판정: 반박(본 Developer v1 고부하 조건).** 본 Developer v1의 8KB·64KB 고부하 관측에서는 API 요청이 성공해도 APIM이 Event Hub 로그 drop을 보고했다. 이 결과는 “Event Hub 연결 자체가 무손실 전달을 보장한다”는 주장을 본 조건에서 반박한다.

| 조건 | RPS | 클라이언트 성공 | APIM-reported EH drop | 해석 |
|---|---:|---:|---:|---|
| E8 | 300 | 54,000 / 54,000 | 0 | 이 관측 창에서는 APIM drop이 보고되지 않음 |
| E8 | 400 | 72,000 / 72,000 | 2,933 | API 성공과 로그 전달 실패가 분리됨 |
| E8 | 500 | 150,000 / 150,000 | 대량, 약 절반으로 기록됨 | 정확한 비율은 warmup 경계 때문에 미확정 |

EH 스로틀링은 측정창 집계에서 0으로 확인됐고, RPS 구간별 개별 확인은 일부만 기록됐다. 중요한 운영 메시지는 두 가지다. 첫째, HTTP 200 성공률만으로 감사 로그 성공률을 판단할 수 없다. 둘째, APIM의 Event Hub drop/success 카운터와 Event Hubs ingress/throttling을 함께 모니터링해야 한다. 이 판정은 본 Developer v1 고부하 조건에 한정하며 모든 SKU·부하로 일반화하지 않는다.

## 질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가

**판정: 조건부 강함.** 두 payload 크기만 측정했지만, 큰 요청이 처리시간과 Event Hub 전달 운영 범위에 영향을 준다는 방향은 강하게 지지된다.

| RPS | N64 — App Insights 메타데이터만 기록한 기준선 Duration | E64 — Event Hub 64KB Duration | E64 APIM-reported EH drop |
|---:|---:|---:|---:|
| 300 | 6.04 ms | 5.24 ms | 41,435 |
| 500 | 7.32 ms | 7.58 ms | 76,434 |

E64 300 RPS는 N64보다 Duration이 낮지만 APIM-reported drop 41,435건이 함께 발생했다. Duration은 로그 전달 완전성 지표가 아니며, 이 차이를 순수 EH 로깅 비용이나 더 나은 성능으로 해석하지 않는다.

64KB 조건은 metadata-only 기준선만으로도 8KB보다 Duration이 뚜렷하게 높았다. 또한 E64는 300 RPS와 500 RPS 모두에서 APIM-reported drop을 보였다. 다만 8KB와 64KB 두 크기, 제한된 RPS 포인트, 대부분 1회 측정에 기반하므로 정확한 임계 곡선은 후속 측정이 필요하다.

## 질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가

**판정: 조건부 지지.** 동일한 8KB 500 RPS E8 비교에서 Developer v1과 Basic v2의 관측 전달 결과는 달랐다. 다만 지표가 비대칭이므로 원인을 SKU 하나로 단정하지 않는다.

| 지표 | Developer v1 관측 | Basic v2 관측 | 주의점 |
|---|---|---|---|
| EH 도달 | 약 절반만 도달한 것으로 기록, 대량 drop | 분당 약 30,000건 수준: 30056, 29900, 29926, 30108, 29796, 30186 | Basic v2는 EH 도달 수로 판단 |
| APIM EventHubDroppedEvents | 대량 drop 보고 | 직접 비교 가능한 drop 카운터 확보 못 함 | v2 메트릭 수집 비대칭 |
| EH throttling | 0 | 0 | EH가 throttle한 증거는 없음 |
| 클라이언트 결과 | 요청 200 성공, p99 약 500 ms | 요청 200 성공, p99 약 30 ms | 클라이언트 p99는 참고 지표 |
| 게이트웨이 리소스 | classic Capacity 관측 | v2 CPU/메모리 미수집 | 메커니즘 확정 불가 |

고객에게 말할 수 있는 것은 “이번 Basic v2 관측 창에서는 EH 도달 수가 발신량과 대체로 맞았고 Developer v1과 다른 운영 결과가 관측됐다”는 점이다. “왜 좋아졌는지”는 v2 CPU/메모리와 drop 카운터를 포함한 대칭 측정이 필요하다.

---

## 직접 확인된 사실

1. 8KB A8 Duration은 기록된 100/200/300/400/500 RPS 포인트에서 App Insights 메타데이터만 기록한 기준선보다 높았다.
2. 8KB Capacity는 200 RPS에서 N8 58%, A8 66%, E8 85%였고, 400~500 RPS에서는 N8/A8/E8 모두 상단 범위에 가까웠다.
3. E8/E64 런에서 클라이언트 요청은 200으로 성공할 수 있었고, APIM `EventHubDroppedEvents`는 별도로 증가했다.
4. EH 스로틀링은 측정창 집계에서 0으로 확인됐고, RPS 구간별 개별 확인은 일부만 기록됐다.
5. E8 APIM-reported drop은 300 RPS에서 0, 400 RPS에서 2,933, 500 RPS에서 대량으로 기록됐다.
6. 64KB metadata-only 기준선 Duration은 300 RPS 6.04 ms, 500 RPS 7.32 ms로 기록돼 8KB보다 컸다.
7. Basic v2 비교 관측 창의 EH IncomingMessages는 분당 약 30,000건 수준으로 발신량과 대체로 맞았다.

## 조건부로 지지되는 해석

- App Insights body 로깅은 본 환경의 8KB 조건에서 APIM 처리시간을 늘린 것으로 해석할 수 있다.
- App Insights AppRequests 집계는 A8 500 RPS에서 누락 없음과 양립하지만, 요청 단위 완전성 증명은 아니다.
- Event Hub drop은 본 관측에서 EH throttling보다 APIM 쪽 처리·버퍼 조건과 더 일치한다. 다만 내부 메커니즘은 직접 계측하지 않았다.
- payload가 커질수록 로깅 전달 가능 운영 범위가 좁아지는 방향은 강하게 시사된다.
- Basic v2 관측 결과는 Developer v1과 다르지만, SKU/세대/메트릭 체계 차이가 함께 있으므로 대칭 재측정이 필요하다.

## 고객이 고려할 운영 사항

- 감사 로그 성공 SLO를 API 성공 SLO와 분리해 정의한다.
- APIM `EventHubDroppedEvents`, `EventHubSuccessfulEvents`, Event Hubs `IncomingMessages`, `ThrottledRequests`를 함께 모니터링하고 drop 알림을 둔다.
- 운영 목표 RPS와 실제 request/log 크기로 사전 부하 테스트를 수행한다.
- classic tier는 Capacity/Duration을 참고하되, v2 tier는 Capacity 대신 gateway CPU/Memory 계열 지표를 수집한다.
- 기록할 본문 크기를 최소화하고, 필요한 필드·요약·해시 중심으로 감사 요구를 재설계한다.
- 리전, SKU, 정책 조합, 백엔드 지연, payload 분포가 다른 고객 환경에서 재시험한다.
- App Insights body 로깅은 성능 완화책(sampling 축소, body 생략)과 감사 요구가 충돌할 수 있으므로 감사 범위, 보존, 비용, 개인정보 마스킹을 별도 설계한다.
- Event Hub 전달을 쓰더라도 downstream consumer, retention, 재처리 절차, 경보 대응 runbook까지 포함해 운영 설계를 검증한다.

## 한계와 미검증 영역

- 사전 명세는 조건별 3회 반복을 요구했지만 실제 기록은 대부분 1회 측정이며, 일부 RPS 스윕으로 방향성을 보강했다.
- 원래 통과 조건이던 요청 ID 집합 대조, 페이로드 해시 일치, 메시지 크기 검증은 최종 판정의 주된 근거로 완료되지 않았다.
- App Insights AppRequests 집계에는 warmup 잔여가 섞일 수 있어 요청 단위 완전성 증명으로 사용하지 않는다.
- Azure Monitor 분 단위 집계와 측정창 경계 때문에 E8 500 RPS의 정확한 drop 비율은 확정하지 않았다.
- v2 CPU/메모리, v2 drop 카운터, v2 Duration 등 대칭 지표가 없어 Basic v2의 메커니즘 해석은 조건부다.
- 본 실험은 최대 500 RPS까지 관측했다. Microsoft 문서의 1,000 RPS 초과 App Insights throughput 영향은 본 실험에서 재현·검증하지 않았다.
- 32KB, 128KB, 200KB, Standard/Premium SKU, multiple units, autoscale, multi-region, backend/model latency, streaming/SSE, response-body logging은 측정하지 않았다.

## 실험 조건과 원천 문서

- 원래 실험 명세: `EXPERIMENT-SPEC.md`
- 실제 실행 로그와 측정창: `EXPERIMENT-LOG.md`
- 보관된 검토 근거: `old/REVIEW.md`
- 보관된 이전 결과 원문: `old/RESULTS.md`
- 앞선 의사결정 가이드: `DECISION-TREE.md` — 이전 의사결정 가이드이며, 손실 여부·임계값·지연·인과 표현이 충돌하면 활성 RESULTS.md가 우선한다.
- 본 보고서의 계약 테스트: `test_results_report.py`

본 문서는 활성 고객 결과보고서이며, `old/REVIEW.md`는 감사 성격의 보관 근거로만 참조한다.
