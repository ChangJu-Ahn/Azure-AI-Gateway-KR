# Lab 13 예비 결과 문서 설계

## 목적

`labs/lab13-logging-perf-benchmark/old/`에 보존된 실제 측정 요약을 현재 `EXPERIMENT-SPEC.md`의 H1~H4에 소급 적용해 `RESULTS-PRELIMINARY.md`를 작성한다.

이 문서는 신규 Basic v2 실험 결과가 아니다. 과거 Standard v2 측정에서 현재 가설을 얼마나 지지할 수 있는지와 어떤 증거가 부족한지를 분리하는 예비 결과다.

## 문서 구조

1. 문서 상태와 해석 제한
2. 현재 실험과 과거 실험의 조건 차이
3. 사용한 과거 측정 출처
4. H1~H4 소급 판정표
5. H1: App Insights CPU 비용과 R* 미확정
6. H2: Event Hub 8KB의 유리한 방향과 회복 미확정
7. H3: 64KB 모호, 200KB 열세
8. H4: 개별 메시지 확인과 모든 요청 대조 부재
9. 현재까지 확인된 사실
10. 확인되지 않은 주장
11. 최소 추가 측정

## 판정

### H1 — App Insights 저하 구간 재현

`부분 지지 / R* 미확정`으로 판정한다.

- Standard v2 고부하 측정에서 App Insights 8KB는 기준선보다 CPU가 각각 +8.0%p, +12.5%p 높았다.
- APIM이 포화되지 않아 throughput SLO 실패는 관측되지 않았다.
- Basic v2의 R*로 재해석하지 않는다.

### H2 — Event Hub 8KB 처리량 회복

`방향성 지지 / 평가 전제 미충족`으로 판정한다.

- 두 고부하 세트에서 Event Hub는 App Insights보다 CPU가 낮고 관측 RPS가 높았다.
- App Insights가 실패한 R*에서의 비교가 아니며 반복 수와 원시 데이터가 부족하다.
- 성능 회복 또는 보장으로 확정하지 않는다.

### H3 — Event Hub 대용량 보장

`미확정`으로 판정한다.

- 64KB는 Event Hub가 CPU와 RPS 모두 높아 우열을 판정할 수 없다.
- 200KB는 Event Hub가 기준선보다 CPU가 높고 RPS가 낮았다.
- 과거 측정은 현재 R*와 다른 저부하 조건이므로 H3 실패로 확정하지 않는다.

### H4 — 모든 요청 로그 도달

`평가 불가`로 판정한다.

- Event Hub consumer에서 8KB와 64KB 개별 메시지 크기가 확인됐다.
- 성공 요청 ID 집합과 Event Hub 수신 ID 집합의 전체 대조가 없다.
- 모든 요청 전달, 누락률 0 또는 중복률을 주장하지 않는다.

## 증거 사용 규칙

- 숫자는 `old/`의 Markdown 또는 HTML에 기록된 실제 측정값만 사용한다.
- 각 표와 주장은 과거 파일의 절대 경로 링크와 줄 번호를 포함한다.
- 차트는 필요할 때 기존 이미지를 참조하며 새 데이터를 암시하는 차트를 만들지 않는다.
- 원시 JSON/CSV가 없으므로 신뢰구간, p99, steady-state 성공 RPS와 요청별 수신율을 새로 계산하지 않는다.
- 과거 문서의 `무손실`, `확정`, `우위` 표현은 현재 판정 기준으로 재검토하고 그대로 복사하지 않는다.

## 반드시 명시할 조건 차이

| 항목 | 과거 측정 | 현재 실험 |
|---|---|---|
| APIM | Standard v2, 1 unit | Basic v2, 1 unit |
| 부하 모델 | closed-loop 고정 VU | open workload 고정 offered RPS |
| 기준선 | App Insights 진단 삭제 | sampling 100%, body 0B |
| payload | 주로 응답 body | 요청 감사 레코드 |
| 판정 지표 | peak RPS, CPU max 중심 | successful RPS, 오류율, p99, 감사 완전성 |
| 반복 | 주로 2회 | 기본 3회, 경계 시 5회 |

## 최소 추가 측정

예비 결과 이후 남는 필수 측정은 다음이다.

1. Basic v2에서 `N8/A8`의 R* 탐색과 확정
2. 동일 R*에서 `N8/A8/E8` 비교
3. 동일 R*에서 `N64/E64` 비교
4. E8/E64의 성공 요청 ID와 Event Hub 수신 ID 전체 대조
5. 결과가 판정 경계이거나 반복 편차가 클 때만 2회 추가

200KB는 비용과 Event Hubs 고정 용량을 산정한 후 별도 승인하는 선택 측정으로 둔다.

## 완료 기준

- `RESULTS-PRELIMINARY.md`가 `EXPERIMENT-SPEC.md` 옆에 생성된다.
- H1~H4 각각에 판정, 근거 수치, 해석 제한과 부족한 증거가 있다.
- 신규 실험을 수행한 것처럼 읽히는 문장이 없다.
- 과거 실측값과 출처가 일치한다.
- 모든 로그 요청을 지칭할 때는 `모든 요청`으로 표현한다.
- placeholder, 상충 판정과 출처 없는 정량 주장이 없다.
