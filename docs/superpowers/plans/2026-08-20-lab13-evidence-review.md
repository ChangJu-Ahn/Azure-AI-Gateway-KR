# Lab 13 Evidence Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a customer-oriented narrative audit in `REVIEW.md` that separates directly verified Lab 13 findings from partial evidence, contradictions, and untested assumptions.

**Architecture:** The report is a read-only evidence synthesis over the existing hypothesis, specification, execution log, results, and decision guide. It preserves `RESULTS.md`, cites exact source locations, grades confidence explicitly, and ends with scoped APIM/AI Gateway recommendations.

**Tech Stack:** Markdown, Git, ripgrep, existing Lab 13 experiment artifacts

## Global Constraints

- Do not modify `RESULTS.md`, `EXPERIMENT-SPEC.md`, `EXPERIMENT-LOG.md`, `DECISION-TREE.md`, or raw result files.
- Treat the experiment as a constrained adaptive investigation, not as an ideal controlled benchmark.
- Distinguish observations from mechanisms and customer recommendations.
- Do not claim end-to-end losslessness without request-ID reconciliation.
- Do not present a one-run boundary as a stable threshold.
- Do not present Developer v1 versus Basic v2 as a clean single-variable SKU experiment.
- Use plain Korean and explain unavoidable technical terms.

---

### Task 1: Write the narrative evidence audit

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/REVIEW.md`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-LOG.md`
- Read: `labs/lab13-logging-perf-benchmark/RESULTS.md`
- Read: `labs/lab13-logging-perf-benchmark/DECISION-TREE.md`
- Read: `labs/lab13-logging-perf-benchmark/REPRODUCE.md`

**Interfaces:**
- Consumes: Existing Markdown claims, recorded measurements, and official-document links.
- Produces: One standalone Korean audit report with confidence categories `확정`, `조건부`, `미검증`, and `반박/교정`.

- [ ] **Step 1: Create the report header and review method**

Create `REVIEW.md` with:

```markdown
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

## 2. 검토 범위와 기준

- 가설과 판정 기준: `EXPERIMENT-SPEC.md`
- 실제 실행 조건과 원시 측정 요약: `EXPERIMENT-LOG.md`
- 최종 주장: `RESULTS.md`
- 고객 의사결정 정리: `DECISION-TREE.md`
```

- [ ] **Step 2: Document what the experiment did well**

Include a narrative section covering these defensible strengths:

- open workload with offered RPS recorded separately from successful requests;
- same-region APIM, Event Hubs, and load generator;
- retries disabled, connections reused, and warmup used;
- client latency demoted after detecting TLS/load-generator artifacts;
- APIM and Event Hubs metrics compared to separate where loss occurred;
- RPS sweep after the initial 500 RPS result;
- 8 KB versus 64 KB probe;
- Developer v1 versus Basic v2 operational comparison;
- infrastructure and reproduction assets retained.

State that these choices make the experiment useful for finding failure modes
even though they do not satisfy the original full repeat matrix.

- [ ] **Step 3: Write the directly supported findings**

Include these findings as `확정` within the tested environment:

1. API requests can return HTTP 200 while APIM reports
   `EventHubDroppedEvents > 0`.
2. The tested Event Hubs namespace did not report throttling during the
   observed APIM-side drops.
3. APIM-reported EH drops decreased as 8 KB offered load moved from 500 to
   400 to 300 RPS.
4. A 64 KB request had materially higher APIM Duration than an 8 KB request,
   even without EH body logging.
5. Adding 8 KB App Insights body logging increased APIM Duration relative to
   the metadata-only baseline at the tested RPS points.
6. The Basic v2 run delivered approximately the offered 500 RPS message count
   to Event Hubs for the observed window.

Scope every statement to the actual APIM deployment, region, payload, and
single-run measurements.

- [ ] **Step 4: Write the partial and inferential findings**

Classify and explain:

- App Insights losslessness: `150,178 >= 150,000` is compatible with no loss,
  but warmup records in the query window prevent request-level proof.
- 8 KB lossless boundary: one 300 RPS run had zero APIM-reported drops and the
  400 RPS run had drops; the safe statement is “the observed transition lies
  between tested points,” not a stable 300 RPS threshold.
- Payload effect on EH delivery: direction is strongly suggested, but only two
  sizes and limited RPS points were measured.
- Deployment-profile effect: Developer v1 dropped and Basic v2 delivered the
  offered count, but the comparison used separate generations/instances and
  did not collect v2 CPU or memory.
- Logger-buffer mechanism: the APIM metric documents queue-limit skips and the
  logger is buffered; the exact relationship to the generic network queue
  component of classic Capacity remains inferential.

- [ ] **Step 5: Write contradictions and overstatements**

Name the source conflict for each item:

1. The specification required three repeats; most executed cells have one run.
2. The specification required EH consumer ID, hash, and message-size
   reconciliation; the final experiment used server counters instead.
3. The specification forbade concluding delivery from drop=0 alone, but the
   report calls 300 RPS “lossless” without recorded ID reconciliation.
4. N8/N64 are called no-logging baselines even though App Insights metadata
   sampling 100% remained enabled.
5. H1 preregistered CPU/p99 criteria were not evaluated as written; the result
   substitutes Duration and Capacity.
6. The report calls 400 RPS a normal/lossless EH point although 2,933 drops
   were recorded.
7. The statement that no-logging Duration is lower at every RPS/payload
   conflicts with 300 RPS N64=6.04 ms and E64=5.24 ms.
8. “App Insights is faster in the lossless range” is not consistent across
   100/200/300 RPS and should be inconclusive.
9. “Developer v1 practical limit is near 500 RPS” is not established because
   500 RPS requests all succeeded and higher rates were not tested; it also
   conflicts with the specification’s prohibited maximum-throughput claim.
10. The observed client p99 difference between v1 and v2 cannot establish a
    16x APIM latency improvement because the client p99 was already classified
    as a load-generator artifact.
11. “Basic v2 had gateway headroom” is not measured because v2 CPU and memory
    were not collected.
12. “App Insights fails by delay and EH fails by loss” is a useful observed
    pattern, not a proven universal failure-mode architecture.

- [ ] **Step 6: Write customer implications**

Separate measured lessons from non-measured design considerations.

Measured lessons:

- HTTP success and audit-log success require separate SLOs.
- Monitor APIM EH drop/success metrics together with Event Hubs ingress and
  throttling.
- Validate logging at peak RPS and realistic request/log sizes.
- Use `Capacity` for classic tiers and gateway CPU/memory metrics for v2.
- Treat the current safe operating range as environment-specific.

Design considerations not tested:

- backend/model latency and failures;
- streaming/SSE responses and long-lived connections;
- response-body logging;
- multiple APIM units, autoscale, zones, and multiple regions;
- Standard/Premium production SKUs;
- redaction, PII/secrets, retention, RBAC, and data residency;
- App Insights ingestion caps and Event Hubs downstream consumer recovery;
- logging cost and alerting operations.

- [ ] **Step 7: Add the final confidence table**

Use a table with columns `주장`, `등급`, `고객이 사용해도 되는 표현`, and
`피해야 할 표현`. Include at least:

- APIM can drop EH logs while API responses succeed — `확정`
- EH was not throttled in these runs — `확정`
- App Insights body logging increased Duration — `조건부 확정`
- App Insights was fully lossless — `조건부`
- 8 KB lossless threshold is 300 RPS — `미검증`
- Basic v2 is inherently lossless — `미검증`
- SKU alone caused the improvement — `조건부`
- payload size reduces the logging operating envelope — `조건부 강함`
- Event Hub is faster than App Insights — `반박/교정`
- Developer v1 maximum is 500 RPS — `반박/교정`

- [ ] **Step 8: Validate document consistency**

Run:

```bash
rg -n "확정|조건부|미검증|반박|교정" \
  labs/lab13-logging-perf-benchmark/REVIEW.md
```

Expected: Every major claim appears with an explicit confidence grade.

Run:

```bash
rg -n "300 RPS.*무손실|16배|실질 처리 한계|이중 인과 확정|항상|보장" \
  labs/lab13-logging-perf-benchmark/REVIEW.md
```

Expected: Matches, if any, occur only in criticism, prohibited wording, or
clearly scoped quotations—not as unqualified conclusions.

Run:

```bash
git diff --check -- labs/lab13-logging-perf-benchmark/REVIEW.md
```

Expected: No whitespace errors.

- [ ] **Step 9: Commit the audit report**

```bash
git add labs/lab13-logging-perf-benchmark/REVIEW.md
git commit -m "docs(lab13): add evidence audit report

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: The commit contains only `REVIEW.md`; existing experiment documents
remain unchanged.
