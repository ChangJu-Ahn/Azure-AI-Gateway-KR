# Lab 13 실험 근거 감사 보고서

## 1. 총평

이 실험은 사전 명세를 완전히 수행한 통제 실험은 아니다. 그러나 제한된
시간·비용·SKU 환경에서 RPS, 요청 크기, APIM 배포 프로필을 순차적으로
바꾸며 EH 드롭의 발생 조건을 좁힌 적응형 조사로서 실무 가치는 높다.

다만 RESULTS.md의 일부 문장은 관측보다 강한 인과·무손실·임계값을 주장한다.
따라서 고객이 사용할 수 있는 결론은 아래 네 등급으로 구분한다.

- **확정**: 기록된 카운터나 요청 결과만으로 방어 가능
- **조건부**: 방향은 지지되지만 반복·대조 또는 동일 지표 비교 부족
- **미검증**: 실험에서 필요한 지표나 조건을 수집하지 않음
- **반박/교정**: 명세 또는 실행 로그와 충돌

> 표의 `조건부 확정`, `조건부 강함`은 모두 상위 분류상 `조건부`에 속한다.

이 감사는 현재 작업 트리의 `EXPERIMENT-SPEC.md`, `EXPERIMENT-LOG.md`,
`RESULTS.md`, `DECISION-TREE.md`, `REPRODUCE.md`만을 근거로 삼는다. 아래 모든
판정은 **Korea Central의 본 APIM 배포, 기록된 payload(8KB·64KB), 관측된 단회
측정창**에 한정된다.

## 2. 검토 범위와 기준

- 가설과 판정 기준: `EXPERIMENT-SPEC.md`
- 실제 실행 조건과 원시 측정 요약: `EXPERIMENT-LOG.md`
- 최종 주장: `RESULTS.md`
- 고객 의사결정 정리: `DECISION-TREE.md`
- 재현 가능성 및 자산 보존: `REPRODUCE.md`

## 3. 이 실험이 잘한 점

이 실험은 원래 명세의 3회 반복 매트릭스를 완수하지는 못했지만, **실패 모드 탐지**라는
목적에는 유의미한 설계를 여러 개 포함했다.

- **open workload를 유지하고 offered RPS와 successful requests를 분리 기록**했다.
  그래서 API 응답 성공과 감사 로그 성공을 분리해서 볼 수 있었다.
- **APIM, Event Hubs, 부하 생성기를 같은 리전**에 두어 리전 간 네트워크 편차를 줄였다.
- **retry 비활성화, 커넥션 재사용, warmup 적용**으로 클라이언트 재시도나 콜드 스타트가
  결과를 오염시키는 것을 줄였다.
- 초기에 관찰된 **클라이언트 p99를 TLS/부하 생성기 아티팩트로 강등**하고, 이후 APIM 서버측
  메트릭을 권위 지표로 재정렬했다.
- **APIM 메트릭과 Event Hubs 메트릭을 대조**해 "APIM이 버렸는지"와 "EH가 못 받았는지"를
  분리하려고 했다.
- 최초 500 RPS 결과 뒤에 **400/300/200/100 RPS 스윕**을 추가해 드롭 전이 구간을 좁혔다.
- **8KB와 64KB를 모두 측정**해 payload 크기 변화가 운영 범위에 미치는 방향성을 확인했다.
- **Developer v1과 Basic v2를 운영 비교**해 SKU 변화 시 결과가 어떻게 달라지는지 관찰했다.
- **IaC, 스크립트, 재현 문서, 시간창**을 남겨 추후 재조회와 재현이 가능하도록 했다.

따라서 이 실험은 **원래의 완전한 반복 실험은 아니지만, 실제 장애·유실이 언제 드러나는지
찾아내는 적응형 현장 조사로서는 유용**하다.

## 4. 직접 근거로 방어 가능한 관찰 (`확정`)

아래 항목은 모두 **기록된 카운터, 요청 성공 수, 관측 창의 서버 메트릭**으로 직접 방어 가능하다.

1. **확정** — API 요청은 HTTP 200으로 성공할 수 있고, 동시에 APIM의
   `EventHubDroppedEvents > 0`가 발생할 수 있다. 즉 API 성공과 감사 로그 성공은 같은 사건이 아니다.
2. **확정** — 관측된 APIM 측 드롭 동안, **테스트된 Event Hubs 네임스페이스는 throttling을 보고하지 않았다**.
   따라서 관찰된 드롭은 최소한 "이번 런에서 EH가 throttle을 걸었다"는 주장으로 설명되지 않는다.
3. **확정** — 8KB EH 로깅에서 **APIM이 보고한 drop은 500 → 400 → 300 RPS로 갈수록 감소**했다.
   기록상 500 RPS는 대량 드롭, 400 RPS는 2,933 드롭, 300 RPS는 0 드롭이다.
4. **확정** — **64KB 요청은 EH body 로깅이 없어도 8KB 요청보다 APIM Duration이 materially 높았다.**
   이는 payload 자체가 게이트웨이 처리시간에 영향을 준다는 관찰이다.
5. **확정** — **8KB App Insights body 로깅을 추가하면 metadata-only 기준선보다 APIM Duration이 증가**했다.
   적어도 기록된 100/300/400/500 RPS 포인트에서는 A8이 N8보다 모두 높다.
6. **확정** — **Basic v2 비교 런은 관측 창에서 Event Hubs에 대략 offered 500 RPS에 해당하는 메시지 수를 전달**했다.
   이는 "해당 창에서는 발신량과 거의 맞는 EH 도달 수가 관찰됐다"는 수준까지는 방어 가능하다.

## 5. 부분적으로만 지지되는 해석 (`조건부` / `미검증`)

1. **조건부** — **App Insights가 완전히 무손실이었다**는 해석은 방향상 강하게 지지되지만,
   `150,178 >= 150,000`만으로 요청 단위 완전성을 증명한 것은 아니다. 측정창에 warmup 잔여가 섞였다고
   기록되어 있어, 이 값은 "누락이 없어 보인다"까지는 말할 수 있지만 요청별 ID 대조 증거는 아니다.
2. **조건부** — **8KB 무손실 경계가 300 RPS**라는 표현은 강하다. 현재 증거가 말해 주는 것은
   "관측된 전이 구간이 300과 400 RPS 사이에 있었다"는 점이다. 안정적 임계값으로 일반화하려면 반복이 더 필요하다.
3. **조건부 강함** — **payload가 커질수록 EH 전달 가능 운영 범위가 줄어든다**는 방향은 강하게 시사된다.
   다만 측정 payload가 8KB와 64KB 두 점뿐이고, RPS 포인트도 제한적이어서 임계 곡선 자체를 확정한 것은 아니다.
4. **조건부** — **배포 프로필/세대 효과**는 관찰됐다. Developer v1은 드롭했고 Basic v2는 offered count에 가까운
   EH 도달을 보였다. 그러나 서로 다른 세대/인스턴스를 비교했고 v2 CPU·memory를 수집하지 않았으므로
   "왜 좋아졌는지"를 메커니즘 수준으로 확정할 수는 없다.
5. **조건부** — **logger buffer가 직접 원인**이라는 설명은 상당히 그럴듯하지만 여전히 추론을 포함한다.
   APIM 메트릭 정의는 queue size limit reached를 말하고, EH 로거는 buffered 설정이 맞다. 다만 이것이
   classic `Capacity`의 일반적 network queue 구성요소와 정확히 어떻게 대응하는지는 문서로 직접 계측되지 않았다.
6. **미검증** — **App Insights와 Event Hub 중 어느 쪽이 항상 더 빠르다**는 일반론은 본 데이터로 증명되지 않는다.
   기록은 조건과 드롭 상태에 따라 해석이 달라지며, 환경·SKU·payload가 바뀌면 결과도 달라질 수 있다.

## 6. 명세·로그와 충돌하거나 과장된 표현 (`반박/교정`)

1. **반박/교정** — `EXPERIMENT-SPEC.md`는 **각 셀 3회 반복**을 요구했지만,
   `EXPERIMENT-LOG.md`의 실제 실행 셀 다수는 **1회 런**이다. 따라서 반복 기반 안정성 결론은 약화해서 읽어야 한다.
2. **반박/교정** — 명세는 **EH consumer ID, hash, message-size reconciliation**을 필수 통과 조건으로 뒀다.
   하지만 실제 결과 문서는 주로 **서버 카운터**로 판정했다. 방법론이 실행 중 바뀌었음을 명시해야 한다.
3. **반박/교정** — 명세는 **drop=0만으로 delivery를 결론내지 말라**고 금지했다.
   그런데 결과 문서는 300 RPS를 "무손실"로 서술한다. ID reconciliation이 없으므로 더 안전한 표현은
   "이 런에서는 APIM-reported drop이 0이었다"이다.
4. **반박/교정** — N8/N64를 "무로깅 baseline"이라고 부를 때는 주의가 필요하다.
   `EXPERIMENT-LOG.md`는 **모든 조건에서 App Insights metadata sampling 100%가 켜져 있었다**고 적었다.
   따라서 N은 "App Insights를 완전히 끈 baseline"이 아니라 **metadata-only baseline**이다.
5. **반박/교정** — H1은 사전등록상 **CPU/p99 기준**으로 판정해야 했다. 실제 결과는 이를 그대로 평가하지 않고
   **Duration과 Capacity**를 대체 지표로 사용했다. 판정 기준 변경을 명시하는 것이 정확하다.
6. **반박/교정** — 결과 문서가 **400 RPS를 normal/lossless EH point처럼 읽히게 하는 서술**을 포함하지만,
   실행 로그에는 **2,933 drops**가 기록돼 있다. 400 RPS는 정상/무손실 점이 아니다.
7. **반박/교정** — "no-logging Duration이 모든 RPS/payload에서 더 낮다"는 식의 문장은
   **300 RPS에서 N64=6.04 ms, E64=5.24 ms**와 충돌한다. 대용량 구간에서는 단조 관계가 아니다.
8. **반박/교정** — "App Insights가 lossless range에서 더 빠르다"는 요약은 100/200/300 RPS 전체에서
   일관되게 성립했다고 보기 어렵다. 현재는 **결론 유보 또는 inconclusive**가 더 적절하다.
9. **반박/교정** — "Developer v1 practical limit is near 500 RPS"는 과장이다.
   500 RPS에서 요청은 모두 성공했고 더 높은 부하는 시험하지 않았다. 게다가 명세는 **최대 처리량 주장**을 금지했다.
10. **반박/교정** — Developer v1 대비 Basic v2의 **16배 APIM latency improvement**를 말하는 것은 부정확하다.
    그 수치는 **클라이언트 p99**이고, 이 지표는 이미 부하 생성기 아티팩트 가능성 때문에 권위 지표에서 제외됐다.
11. **반박/교정** — "Basic v2 had gateway headroom"은 측정된 사실이 아니다.
    v2 CPU·memory가 수집되지 않았으므로, 관측된 것은 **EH 도달 수가 offered count와 대체로 맞았다**는 점까지다.
12. **반박/교정** — "App Insights fails by delay and EH fails by loss"는 이번 환경에서 유용한 **관찰 패턴**이지만,
    보편적 시스템 아키텍처 법칙으로 확정한 표현은 과하다. 다른 SKU·payload·backend 조건에서는 달라질 수 있다.

## 7. 고객이 가져가도 되는 교훈과 아직 시험하지 않은 설계 고려사항

### 7.1 측정으로 지지되는 교훈

- **확정** — HTTP 성공 SLO와 감사 로그 성공 SLO는 분리해 설계해야 한다.
- **확정** — APIM의 EH drop/success 메트릭과 Event Hubs ingress/throttling을 함께 봐야,
  "게이트웨이가 버렸는지"와 "EH가 못 받았는지"를 분리할 수 있다.
- **확정** — 실제 운영 최대 부하와 현실적인 request/log size에서 로깅을 직접 검증해야 한다.
- **확정** — classic tier는 `Capacity`, v2 tier는 gateway CPU/memory 계열 지표를 사용해야 한다.
- **조건부** — 현재 관측된 safe operating range는 환경별 값이지, 제품 일반 보증이 아니다.

### 7.2 아직 측정되지 않은 설계 고려사항

- **미검증** — backend/model latency와 backend failure가 섞이면 같은 결론이 유지되는지
- **미검증** — streaming/SSE 응답, 장수 연결(long-lived connections)에서의 영향
- **미검증** — response-body logging의 비용과 유실 패턴
- **미검증** — multiple APIM units, autoscale, zone, multi-region 구성의 차이
- **미검증** — Standard/Premium 등 production SKU에서의 운영 범위
- **미검증** — redaction, PII/secrets, retention, RBAC, data residency 요구 충족 방식
- **미검증** — App Insights ingestion cap, Event Hubs downstream consumer recovery의 실제 영향
- **미검증** — 로깅 비용, 경보 운영, 재처리 절차까지 포함한 운영 총비용

## 8. 최종 신뢰도 표

| 주장 | 등급 | 고객이 사용해도 되는 표현 | 피해야 할 표현 |
|---|---|---|---|
| APIM can drop EH logs while API responses succeed | 확정 | 본 환경에서는 API 200 응답과 EH 로그 드롭이 동시에 관측됐다. | API가 성공하면 감사 로그도 항상 성공한다. |
| EH was not throttled in these runs | 확정 | 관측된 드롭 창에서 테스트된 EH namespace throttling은 보이지 않았다. | 이번 드롭은 EH throttle 때문이었다. |
| App Insights body logging increased Duration | 조건부 확정 | 기록된 RPS 포인트에서는 A8 Duration이 metadata-only baseline보다 높았다. | App Insights는 항상 체감 지연을 크게 만든다. |
| App Insights was fully lossless | 조건부 | 관측값은 무손실과 양립하지만 warmup 혼입 때문에 요청 단위 완전성 증명은 아니다. | App Insights는 전건 무손실이 확정됐다. |
| 8 KB lossless threshold is 300 RPS | 미검증 | 관측된 전이 구간은 300~400 RPS 사이였다. | 300 RPS가 안정적 무손실 임계값이다. |
| Basic v2 is inherently lossless | 미검증 | 이번 Basic v2 관측 창에서는 offered count에 가까운 EH 도달이 보였다. | Basic v2면 언제나 무손실이다. |
| SKU alone caused the improvement | 조건부 | SKU/배포 프로필 변화와 결과 개선이 함께 관측됐다. | 개선 원인은 SKU 하나로 인과 확정됐다. |
| payload size reduces the logging operating envelope | 조건부 강함 | 큰 payload일수록 무손실 운영 범위가 줄어드는 방향이 강하게 시사된다. | payload만 보면 정확한 임계 곡선을 이미 안다. |
| Event Hub is faster than App Insights | 반박/교정 | 속도 비교는 드롭 여부와 지표 종류를 분리해 다시 말해야 한다. | Event Hub가 App Insights보다 빠르다. |
| Developer v1 maximum is 500 RPS | 반박/교정 | 본 실험은 500 RPS까지 관측했고 그 이상은 미시험이다. | Developer v1의 실질 처리 한계는 500 RPS로 확정됐다. |

## 9. 결론

고객이 현재 문서 세트를 사용할 때 가장 안전한 메시지는 다음이다.

- **확정**: 본 환경에서는 **Event Hub 로그 드롭이 API 성공과 분리되어 발생할 수 있다.**
- **조건부**: App Insights 8KB body 로깅은 **기록된 포인트에서 Duration을 늘렸고, losslessness는 강하게 시사되지만 전건 증명은 아니다.**
- **조건부**: SKU 상향과 payload 축소는 운영 범위를 넓힐 가능성이 크지만, **어떤 SKU가 어느 부하에서 안전한지는 고객 환경에서 재측정**해야 한다.
- **반박/교정**: 현재 RESULTS/DECISION-TREE의 일부 표현은 **무손실·임계값·인과를 실제 증거보다 강하게 말한다.** 고객 문서에는 위 표의 안전한 표현만 사용하는 편이 좋다.
