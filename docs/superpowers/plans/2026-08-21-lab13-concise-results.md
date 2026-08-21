# Lab 13 Concise Results Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the active Lab 13 `RESULTS.md` to a readable 100-120 line customer report using tables and bullets while preserving reviewed verdicts and measured values.

**Architecture:** Rewrite only the active Markdown structure. Consolidate repeated evidence caveats into one limitations section, replace the seven-item narrative summary with a five-question conclusion table, and retain compact measured tables under each question. Strengthen the existing Markdown contract test to enforce concise structure and preserved data.

**Tech Stack:** Markdown, Python `unittest`, regular expressions, Git

## Global Constraints

- Modify only `labs/lab13-logging-perf-benchmark/RESULTS.md` and
  `labs/lab13-logging-perf-benchmark/test_results_report.py`.
- Do not modify `REPORT.html`, `test_report_html.py`, archived reports,
  `DECISION-TREE.md`, experiment documents, raw JSON, IaC, or scripts.
- Target 100-120 lines for active `RESULTS.md`.
- Keep exactly five question sections and the reviewed verdicts:
  - Q1: 조건부 지지
  - Q2: 미검증
  - Q3: 반박(본 Developer v1 고부하 조건)
  - Q4: 조건부 강함
  - Q5: 조건부 지지
- Preserve all required measured Duration, Capacity, drop, and v1/v2 values.
- N8/N64 remain App Insights metadata-only baselines.
- Do not reintroduce stable 300 RPS threshold, request-level App Insights
  losslessness, Basic v2 inherent losslessness, SKU-only causality, 16x APIM
  latency, pure EH logging-cost, or Developer v1 maximum claims.
- Keep active RESULTS precedence over conflicting older `DECISION-TREE.md`
  wording.
- Prefer tables and bullets; shared qualifications belong in one limitations
  section.

---

### Task 1: Rewrite RESULTS.md into a concise structured report

**Files:**
- Modify: `labs/lab13-logging-perf-benchmark/RESULTS.md`
- Modify: `labs/lab13-logging-perf-benchmark/test_results_report.py`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-LOG.md`

**Interfaces:**
- Consumes: The active reviewed result report and its existing contract tests.
- Produces: A 100-120 line result report with a five-question summary table,
  five short detailed sections, one recommendation list, one limitations list,
  and a compact source table.

- [ ] **Step 1: Add failing concise-structure tests**

Extend `test_results_report.py`:

```python
def test_report_is_concise(self):
    line_count = len(self.text.splitlines())
    self.assertGreaterEqual(line_count, 100)
    self.assertLessEqual(line_count, 120)

def test_has_five_question_conclusion_table(self):
    table = re.search(
        r"^## 핵심 결론\s*(?P<body>.*?)(?=^---$)",
        self.text,
        re.MULTILINE | re.DOTALL,
    ).group("body")
    self.assertEqual(table.count("| Q"), 5)
    for verdict in (
        "조건부 지지",
        "미검증",
        "반박(본 Developer v1 고부하 조건)",
        "조건부 강함",
    ):
        self.assertIn(verdict, table)

def test_removes_duplicate_finding_sections(self):
    self.assertNotIn("## 직접 확인된 사실", self.text)
    self.assertNotIn("## 조건부로 지지되는 해석", self.text)

def test_each_question_is_compact(self):
    matches = list(re.finditer(r"^## 질문 [1-5] —", self.text, re.MULTILINE))
    self.assertEqual(len(matches), 5)
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else self.text.index("\n---", match.start())
        section_lines = self.text[match.start():end].splitlines()
        self.assertLessEqual(len(section_lines), 14)

def test_shared_caveats_are_consolidated(self):
    limitations = self.section_body("한계")
    for phrase in (
        "조건별 대부분 1회",
        "요청 ID",
        "warmup",
        "v2 CPU/메모리",
        "1,000 RPS",
    ):
        self.assertIn(phrase, limitations)
```

Keep all existing archive hashes, measured-value, verdict, terminology,
overclaim, precedence, and source-link tests.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_results_report.py -v
```

Expected failures:

- report exceeds 120 lines;
- `## 핵심 결론` table is missing;
- duplicate direct/conditional sections remain;
- question sections exceed compact limits.

- [ ] **Step 3: Rewrite the opening into scope plus a conclusion table**

Use this structure:

```markdown
# Lab 13 최종 결과 보고서 — APIM 로깅 성능·로그 전달 벤치마크

## 검증 범위

- 환경: ...
- 조건: ...
- 기준선: ...
- 반복: ...
- 미검증: ...

## 핵심 결론

| 질문 | 판정 | 핵심 근거 | 고객 의미 |
|---|---|---|---|
| Q1 App Insights 본문 로깅 영향 | 조건부 지지 | ... | ... |
| Q2 성능 저하 없는 모든 요청 로깅 | 미검증 | ... | ... |
| Q3 Event Hub 무손실 보장 | 반박(본 Developer v1 고부하 조건) | ... | ... |
| Q4 요청 크기 영향 | 조건부 강함 | ... | ... |
| Q5 v1/v2 전달 결과 차이 | 조건부 지지 | ... | ... |
```

Keep the scope concise. Move definitions into parentheses at first use instead
of a separate long terminology list, except `metadata-only` must be explained.

- [ ] **Step 4: Rewrite each question to at most 14 lines**

Use a consistent compact form:

```markdown
## 질문 N — ...

- **가설:** ...
- **판정:** ...
- **핵심 근거:** ...

| compact data table when needed |

**결론:** one scoped customer sentence.
```

Required data:

- Q1:
  - Duration table at 100/200/300/400/500 RPS for N8/A8.
  - State N8 is App Insights metadata-only.
- Q2:
  - AppRequests 150,178 versus 150,000 offered.
  - Warmup/ID caveat deferred to limitations.
- Q3:
  - E8 APIM drops 300=0, 400=2,933, 500=large/about half exact rate
    unconfirmed.
  - EH throttling wording scoped to recorded measurement windows.
- Q4:
  - 64 KB table: N64/E64 Duration and E64 drops at 300/500.
  - One-line caution that Duration is not delivery completeness.
- Q5:
  - Developer v1 versus Basic v2 observed delivery table.
  - State metric asymmetry in one line; details deferred to limitations.

- [ ] **Step 5: Consolidate recommendations, limitations, and sources**

Use:

```markdown
## 고객 운영 권고

1. ...

## 한계

- ...

## 원천 문서

| 문서 | 역할 |
```

Recommendations:

1. Separate API success and logging-delivery SLOs.
2. Monitor APIM EH success/drop with EH ingress/throttling.
3. Capacity-test peak RPS × logged payload size.
4. Use classic Capacity for v1 and gateway CPU/memory for v2.
5. Reduce logged body size.
6. Retest in the customer environment.

Limitations:

- mostly one run per condition;
- planned request-ID/hash/message-size reconciliation not completed;
- App Insights count may include warmup boundary records;
- client p95/p99 contains load-generator/TLS artifacts;
- v1/v2 metrics asymmetric and v2 CPU/memory absent;
- 1,000 RPS and production multi-unit/region/backend scenarios untested.

Sources:

- `EXPERIMENT-SPEC.md`
- `EXPERIMENT-LOG.md`
- `old/RESULTS-Old.md`
- `old/REVIEW.md`
- `DECISION-TREE.md` with active RESULTS precedence note
- `REPORT.html`

- [ ] **Step 6: Run contract tests and verify line target**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_results_report.py -v
wc -l labs/lab13-logging-perf-benchmark/RESULTS.md
git diff --check -- \
  labs/lab13-logging-perf-benchmark/RESULTS.md \
  labs/lab13-logging-perf-benchmark/test_results_report.py
```

Expected:

- all result-report tests PASS;
- line count is between 100 and 120;
- no whitespace errors.

- [ ] **Step 7: Verify no out-of-scope file changed**

Run:

```bash
git diff --name-only HEAD -- \
  labs/lab13-logging-perf-benchmark
```

Expected task-owned paths only:

```text
labs/lab13-logging-perf-benchmark/RESULTS.md
labs/lab13-logging-perf-benchmark/test_results_report.py
```

- [ ] **Step 8: Commit**

```bash
git add \
  labs/lab13-logging-perf-benchmark/RESULTS.md \
  labs/lab13-logging-perf-benchmark/test_results_report.py
git commit -m "docs(lab13): streamline reviewed results report

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
