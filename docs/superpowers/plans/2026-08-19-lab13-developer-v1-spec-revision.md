# Lab 13 Developer v1 Specification Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Basic v2 saturation experiment specification with a cost-bounded Developer v1 experiment that validates 500 offered RPS for 8KB and 64KB logging in 15 base runs.

**Architecture:** Preserve the superseded Basic v2 specification under `old/` before rewriting the active specification. The active document will define five configurations (`N8`, `A8`, `E8`, `N64`, `E64`), three falsifiable hypotheses, fixed SLOs, fixed load-generator and Event Hubs capacity conditions, and narrowly scoped allowed conclusions.

**Tech Stack:** Markdown, Azure API Management Developer v1, k6 open workload, Azure Event Hubs Standard, Azure Monitor.

## Global Constraints

- APIM scope is the existing Developer v1 instance; do not claim applicability to Basic v2, Standard v2, or production APIs.
- Offered load is fixed at 500 RPS; do not search for a saturation point `R*`.
- Required payload sizes are 8KB and 64KB only; exclude 32KB, 128KB, and 200KB.
- Base execution count is 15: `N8/A8/E8` three times each and `N64/E64` three times each.
- Add two repeats only for a cell with a boundary result or one contradictory repetition.
- Use `모든 요청` terminology for all-request logging.
- Do not claim Event Hub improves APIM performance.
- Do not treat the portal's 500 RPS figure as a guaranteed or maximum throughput.
- Do not require full-request GatewayLogs ingestion.

---

## File Structure

- `labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md`: immutable archive of the superseded Basic v2 and `R*` specification.
- `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`: active Developer v1, 500 RPS, 8KB/64KB experiment specification.

---

### Task 1: Archive the superseded Basic v2 specification

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`

**Interfaces:**
- Consumes: the currently committed Basic v2 experiment specification at commit `94f2533` and later wording fixes through `1f1602b`.
- Produces: an unchanged historical copy that preserves the old `Basic v2`, `R*`, 32/128/200KB, and 65-run design.

- [ ] **Step 1: Create the archive directory and move the active file**

Run:

```bash
mkdir -p labs/lab13-logging-perf-benchmark/old/experiment-basic-v2
git mv \
  labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md \
  labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md
```

Expected: Git reports a staged rename after the active file is recreated in Task 2.

- [ ] **Step 2: Verify that the archived file still contains the superseded scope**

Run:

```bash
grep -nE 'Basic v2|R\\*|E200|구성별 확증 반복: 5회' \
  labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md
```

Expected: all four superseded-design markers are found.

- [ ] **Step 3: Commit the archive**

```bash
git add labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md
git commit -m "docs(lab13): archive Basic v2 experiment specification" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: one committed file move; no other workspace changes are included.

---

### Task 2: Write the active Developer v1 experiment specification

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`
- Reference: `docs/superpowers/specs/2026-08-19-lab13-developer-v1-experiment-redesign.md`
- Reference: `labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md`

**Interfaces:**
- Consumes: the approved redesign's exact H1-H3 thresholds and execution conditions.
- Produces: the sole active specification for the next Lab 13 run.

- [ ] **Step 1: Create the document header and evidence boundary**

Create `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md` with:

```markdown
# Lab 13 — Developer v1에서 App Insights와 Event Hub 로깅 비교

> **상태**: 실행 전 실험 명세
> **적용 범위**: 기존 Azure API Management Developer v1 인스턴스, 단일 리전
> **목표 부하**: 500 offered RPS
> **필수 크기**: 8KB, 64KB

이 실험은 Developer v1의 최대 처리량을 측정하거나 Basic v2 결과를 추정하지 않는다.
500 RPS는 본 실험의 목표 부하이며 보장 처리량 또는 최대 처리량으로 해석하지 않는다.
```

Then retain the official Microsoft quotations and links from the archived specification, but change their interpretation:

- App Insights official 1,000+ RPS result is background evidence only.
- `log-to-eventhub` sampling and 200KB statements are product behavior evidence only.
- The active experiment does not test 1,000 RPS or 200KB.

- [ ] **Step 2: Define the five configurations**

Add this exact table:

```markdown
| ID | 감사 레코드 | App Insights | Event Hub |
|---|---:|---|---|
| N8 | 8KB | sampling 100%, body 0B | 없음 |
| A8 | 8KB | sampling 100%, body 8KB | 없음 |
| E8 | 8KB | sampling 100%, body 0B | 8KB 전체 메시지 |
| N64 | 64KB | sampling 100%, body 0B | 없음 |
| E64 | 64KB | sampling 100%, body 0B | 64KB 전체 메시지 |
```

State that all conditions return the same small fixed response and make no backend call.

- [ ] **Step 3: Add H1 and its two-level verdict**

Document:

```markdown
### H1 — App Insights 8KB의 500 RPS 성능 영향

- 리소스 오버헤드 지지:
  - A8 평균 gateway CPU가 N8보다 5%p 이상 높거나
  - A8 p99가 N8보다 20% 이상 높고
  - 세 반복이 모두 같은 방향이다.
- 처리량 저하 확정:
  - N8은 성공 RPS 495 이상이며 오류율 1% 이하이고
  - A8은 성공 RPS 495 미만이거나 오류율이 1%를 초과한다.
- 어느 조건도 성립하지 않으면 본 Developer v1·500 RPS 조건에서는 유의한 저하를 관찰하지 못한 것으로 판정한다.
```

Do not state that App Insights must fail at 500 RPS.

- [ ] **Step 4: Add H2 and H3**

For H2, require E8 to satisfy:

```markdown
- generated/offered requests ≥ 99%
- 성공 RPS ≥ 495
- 오류율 ≤ 1%
- p99 ≤ 같은 블록 N8 p99의 120%
- APIM 성공 요청의 모든 고유 ID가 EH consumer에서 확인
- payload hash 일치
- 전체 EH 메시지 크기 8KB
```

For H3, repeat the criteria with N64 as the latency baseline and a 64KB message. State that N64 failure prevents attributing E64 failure to Event Hub.

- [ ] **Step 5: Add fixed infrastructure conditions**

Document:

```markdown
- APIM: existing Developer v1, no infrastructure changes during the experiment
- load generator: one fixed Standard_D8as_v5 Linux VM in Japan East
- load tool: k6 constant-arrival-rate
- load-generator invalidation:
  - CPU average > 70%
  - network > 70% of documented VM maximum
  - dropped_iterations > 0
  - generated/offered < 99%
  - socket or TLS errors
- E8 Event Hubs: Standard, at least 5 fixed TU
- E64 Event Hubs: Standard, 40 fixed TU
- Event Hubs auto-inflate: OFF
- no TU or partition-count changes within a condition
```

State that EH throttle, server error, or unresolved consumer lag fails the all-request delivery requirement.

- [ ] **Step 6: Add the 15-run execution matrix**

Document:

```markdown
| Block | Conditions | Repeats | Runs |
|---|---|---:|---:|
| 8KB | N8, A8, E8 | 3 each | 9 |
| 64KB | N64, E64 | 3 each | 6 |
| Total |  |  | 15 |
```

For every run:

```markdown
- ramp: 60 seconds
- stabilization: 60 seconds
- steady-state: 300 seconds
- EH drain: until two consecutive minutes contain no new event, capped at 10 minutes
```

Use balanced randomized order within each block. Add two repeats only to the boundary or contradictory cell.

- [ ] **Step 7: Add metrics, evidence, and allowed conclusions**

Require:

- k6 offered/generated/successful RPS, error rate, p50/p95/p99, dropped iterations
- APIM CPU avg/max and request totals
- EH incoming bytes/events, throttle, server errors, consumer lag
- sent success-ID set versus received-ID set, duplicates, missing IDs, hash, exact size

Explicitly make full GatewayLogs optional and limited to setup verification.

Allowed conclusions:

```markdown
- App Insights showed CPU or p99 overhead at 500 RPS.
- App Insights caused throughput degradation only if the H1 throughput condition passed.
- Event Hub delivered all 8KB logs while meeting the 500 RPS SLO only if H2 passed.
- Event Hub delivered all 64KB logs while meeting the 500 RPS SLO only if H3 passed.
```

Forbidden conclusions:

```markdown
- Event Hub makes APIM faster.
- App Insights always reduces APIM throughput.
- Developer v1 results apply to Basic v2, Standard v2, or production APIs.
- Passing 500 RPS proves maximum or guaranteed APIM throughput.
- A zero EH drop metric proves all requests arrived.
- A 64KB result predicts 200KB behavior.
```

- [ ] **Step 8: Verify the active specification**

Run:

```bash
grep -nE 'Developer v1|500 offered RPS|N8|A8|E8|N64|E64|합계 15|40 fixed TU|모든 요청' \
  labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md
```

Expected: every active-scope marker is found.

Run:

```bash
if grep -nE 'Basic v2|R\\*|E200|N200|65회|구성별 확증 반복: 5회|전건' \
  labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md; then
  exit 1
fi
```

Expected: exit 0 with no matches.

Run:

```bash
git diff --check
```

Expected: exit 0 with no whitespace errors.

- [ ] **Step 9: Commit the active specification**

```bash
git add labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md
git commit -m "docs(lab13): scope experiment to Developer v1" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: one new active specification committed without unrelated workspace changes.

---

### Task 3: Cross-check active and archived specifications

**Files:**
- Verify: `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`
- Verify: `labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md`

**Interfaces:**
- Consumes: both completed documents.
- Produces: evidence that the current and superseded scopes are unambiguous and recoverable.

- [ ] **Step 1: Verify the active root layout**

Run:

```bash
find labs/lab13-logging-perf-benchmark -mindepth 1 -maxdepth 1 -print | sort
```

Expected:

```text
labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md
labs/lab13-logging-perf-benchmark/old
```

- [ ] **Step 2: Verify scope separation**

Run:

```bash
grep -q 'Developer v1' labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md
grep -q 'Basic v2' labs/lab13-logging-perf-benchmark/old/experiment-basic-v2/EXPERIMENT-SPEC.md
```

Expected: both commands exit 0.

- [ ] **Step 3: Verify repository state**

Run:

```bash
git status --short -- labs/lab13-logging-perf-benchmark
git log -3 --oneline -- labs/lab13-logging-perf-benchmark
```

Expected: no uncommitted Lab 13 changes; recent history shows the archive and active-spec commits.

