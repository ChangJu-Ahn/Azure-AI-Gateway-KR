# Lab 13 Reviewed Results Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Archive the current Lab 13 results and review, replace `RESULTS.md` with an evidence-scoped official result report, and align `REPORT.html` with that report.

**Architecture:** Task 1 preserves the current working-tree documents byte-for-byte and writes a new authoritative Markdown report with contract tests. Task 2 changes only the HTML narrative and its tests so the visual report uses the same ordered summary, five question verdicts, limitations, and source roles while retaining all verified chart data.

**Tech Stack:** Markdown, HTML5, CSS, vanilla JavaScript, Python `unittest`, `html.parser`, browser validation, Git

## Global Constraints

- Preserve the current working-tree `RESULTS.md` exactly as `old/RESULTS.md`.
- Preserve the current `REVIEW.md` as `old/REVIEW.md`; active `REVIEW.md` must no longer exist.
- Expected archive SHA-256 values at plan creation:
  - `old/RESULTS.md`: `123d2e9cac909bbca65e209029e8db02693f0960c07b43fb108b6413413d2e1e`
  - `old/REVIEW.md`: `d63a309f29e31ccd235d4664fa55375cafc39acf2d48e1493eca332040f01ed6`
- `RESULTS.md` remains the active authoritative customer result report.
- `REPORT.html` remains the visual form of active `RESULTS.md`.
- Do not modify `EXPERIMENT-SPEC.md`, `EXPERIMENT-LOG.md`,
  `DECISION-TREE.md`, raw JSON results, IaC, scripts, or unrelated dirty files.
- Do not rerun Azure experiments.
- Use only recorded values from the current Lab 13 sources.
- Do not claim request-level losslessness without request-ID reconciliation.
- Do not claim a stable 300 RPS threshold, Basic v2 inherent losslessness,
  SKU-only causality, a 16x APIM latency improvement, or a measured Developer
  v1 maximum of 500 RPS.
- N8/N64 are App Insights metadata-only baselines, not no-logging baselines.
- Preserve the self-contained Clawpilot HTML theme, chart geometry, numerical
  values, offline behavior, tabs, print behavior, and accessibility.

---

### Task 1: Archive prior reports and write the reviewed RESULTS.md

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/old/RESULTS.md`
- Move: `labs/lab13-logging-perf-benchmark/REVIEW.md` → `labs/lab13-logging-perf-benchmark/old/REVIEW.md`
- Replace: `labs/lab13-logging-perf-benchmark/RESULTS.md`
- Create: `labs/lab13-logging-perf-benchmark/test_results_report.py`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-LOG.md`

**Interfaces:**
- Consumes: Current working-tree results and audit, original specification,
  actual execution log.
- Produces: Immutable archived copies and one active customer result report
  with seven ordered summary conclusions and five evidence-scoped questions.

- [ ] **Step 1: Snapshot and verify archive inputs before editing**

Run:

```bash
mkdir -p .superpowers/sdd/lab13-reviewed-results
cp labs/lab13-logging-perf-benchmark/RESULTS.md \
  .superpowers/sdd/lab13-reviewed-results/RESULTS.before.md
cp labs/lab13-logging-perf-benchmark/REVIEW.md \
  .superpowers/sdd/lab13-reviewed-results/REVIEW.before.md
shasum -a 256 \
  .superpowers/sdd/lab13-reviewed-results/RESULTS.before.md \
  .superpowers/sdd/lab13-reviewed-results/REVIEW.before.md
```

Expected hashes:

```text
123d2e9cac909bbca65e209029e8db02693f0960c07b43fb108b6413413d2e1e
d63a309f29e31ccd235d4664fa55375cafc39acf2d48e1493eca332040f01ed6
```

If either hash differs, stop and report that the user changed an archive source
after plan approval.

- [ ] **Step 2: Write the failing archive and active-report contract tests**

Create `test_results_report.py`:

```python
import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
ACTIVE = ROOT / "RESULTS.md"
OLD_RESULTS = ROOT / "old" / "RESULTS.md"
OLD_REVIEW = ROOT / "old" / "REVIEW.md"
ACTIVE_REVIEW = ROOT / "REVIEW.md"

EXPECTED_HASHES = {
    OLD_RESULTS: "123d2e9cac909bbca65e209029e8db02693f0960c07b43fb108b6413413d2e1e",
    OLD_REVIEW: "d63a309f29e31ccd235d4664fa55375cafc39acf2d48e1493eca332040f01ed6",
}

SUMMARY_HEADINGS = [
    "App Insights 본문 로깅은 처리시간을 늘렸다",
    "App Insights 집계는 무손실과 양립하지만 요청 단위 증명은 아니다",
    "API 성공과 Event Hub 로그 전달 성공은 별개다",
    "관측된 드롭은 EH 스로틀링으로 설명되지 않았다",
    "8KB 드롭 전이는 300~400 RPS 사이에서 관측됐다",
    "큰 요청은 처리시간과 로깅 운영 범위에 영향을 줬다",
    "Developer v1과 Basic v2에서 전달 결과 차이가 관측됐다",
]

QUESTION_HEADINGS = [
    "질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가",
    "질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가",
    "질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가",
    "질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가",
    "질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가",
]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ReviewedResultsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = ACTIVE.read_text(encoding="utf-8")

    def test_archived_files_are_exact(self):
        for path, expected in EXPECTED_HASHES.items():
            self.assertTrue(path.exists(), path)
            self.assertEqual(sha256(path), expected)

    def test_review_is_archived_only(self):
        self.assertTrue(OLD_REVIEW.exists())
        self.assertFalse(ACTIVE_REVIEW.exists())

    def test_summary_has_required_order(self):
        summary = re.search(
            r"^## 요약\s*(?P<body>.*?)(?=^---$)",
            self.text,
            re.MULTILINE | re.DOTALL,
        ).group("body")
        positions = [summary.index(f"**{heading}.**") for heading in SUMMARY_HEADINGS]
        self.assertEqual(positions, sorted(positions))

    def test_has_five_reviewed_questions(self):
        for heading in QUESTION_HEADINGS:
            self.assertIn(f"## {heading}", self.text)

    def test_uses_metadata_only_baseline_wording(self):
        self.assertIn("App Insights 메타데이터만 기록한 기준선", self.text)
        self.assertNotIn("N8 무로깅", self.text)
        self.assertNotIn("N64 (무로깅)", self.text)

    def test_prohibited_overclaims_are_absent(self):
        banned = [
            "App Insights(100%)가 EH보다 기록 완전성이 높았다",
            "이중 인과 확정",
            "8KB는 300 RPS까지 무손실",
            "약 16배 안정화",
            "실질 처리 한계는 500 RPS",
            "정상(무손실) 구간에서는 App Insights가",
            "Basic v2로 올리면 EH가 무손실로 모든 로그를 남긴다",
            "EH 로깅 순수 비용",
        ]
        for phrase in banned:
            self.assertNotIn(phrase, self.text)

    def test_limitations_cover_execution_deviations(self):
        required = [
            "조건별 3회 반복",
            "요청 ID",
            "페이로드 해시",
            "대부분 1회",
            "warmup",
            "v2 CPU/메모리",
            "1,000 RPS",
        ]
        for phrase in required:
            self.assertIn(phrase, self.text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the new tests and verify failure**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_results_report.py -v
```

Expected: FAIL because `old/` does not exist and active results still contain
the overclaims.

- [ ] **Step 4: Create the archives**

Run:

```bash
mkdir -p labs/lab13-logging-perf-benchmark/old
cp .superpowers/sdd/lab13-reviewed-results/RESULTS.before.md \
  labs/lab13-logging-perf-benchmark/old/RESULTS.md
git mv labs/lab13-logging-perf-benchmark/REVIEW.md \
  labs/lab13-logging-perf-benchmark/old/REVIEW.md
shasum -a 256 \
  labs/lab13-logging-perf-benchmark/old/RESULTS.md \
  labs/lab13-logging-perf-benchmark/old/REVIEW.md
```

Expected: hashes match `EXPECTED_HASHES`.

- [ ] **Step 5: Replace active RESULTS.md**

Write a concise customer report with this exact section order:

```markdown
# Lab 13 최종 결과 보고서 — APIM 로깅 성능·로그 전달 벤치마크

## 용어와 검증 범위
## 요약
---
## 질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가
## 질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가
## 질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가
## 질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가
## 질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가
---
## 직접 확인된 사실
## 조건부로 지지되는 해석
## 고객이 고려할 운영 사항
## 한계와 미검증 영역
## 실험 조건과 원천 문서
```

The summary must use these exact bold headings and order:

```markdown
1. **App Insights 본문 로깅은 처리시간을 늘렸다.**
2. **App Insights 집계는 무손실과 양립하지만 요청 단위 증명은 아니다.**
3. **API 성공과 Event Hub 로그 전달 성공은 별개다.**
4. **관측된 드롭은 EH 스로틀링으로 설명되지 않았다.**
5. **8KB 드롭 전이는 300~400 RPS 사이에서 관측됐다.**
6. **큰 요청은 처리시간과 로깅 운영 범위에 영향을 줬다.**
7. **Developer v1과 Basic v2에서 전달 결과 차이가 관측됐다.**
```

Use these verdicts:

- Q1: `조건부 지지` — recorded A8 Duration exceeded metadata-only N8, but
  original CPU/p99/repeat criterion was not executed exactly.
- Q2: `미검증` — neither “all requests” nor “without degradation” was proven
  end-to-end under the original criterion.
- Q3: `반박(본 Developer v1 고부하 조건)` — APIM reported Event Hub drops
  while requests returned 200; do not generalize to every SKU/load.
- Q4: `조건부 강함` — payload direction is strongly supported, but only two
  sizes and limited points were tested.
- Q5: `조건부 지지` — operational result difference observed; metrics were
  asymmetric and v2 CPU/memory was absent.

Include the recorded tables without inventing values:

- 8 KB N8/A8 Duration at 100/300/400/500 RPS.
- 8 KB E8 APIM-reported drops: 300=0, 400=2,933, 500=large/about half with
  exact rate unconfirmed.
- 64 KB N64/E64 Duration and E64 drops at 300/500 RPS.
- Developer v1 versus Basic v2 observed delivery fields, with explicit metric
  asymmetry.

Reference `old/REVIEW.md` as the archived review basis, not as the active result.

- [ ] **Step 6: Run Markdown contract tests**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_results_report.py -v
git diff --check -- \
  labs/lab13-logging-perf-benchmark/RESULTS.md \
  labs/lab13-logging-perf-benchmark/old/RESULTS.md \
  labs/lab13-logging-perf-benchmark/old/REVIEW.md \
  labs/lab13-logging-perf-benchmark/test_results_report.py
```

Expected: all tests PASS and no whitespace errors.

- [ ] **Step 7: Commit Task 1**

```bash
git add \
  labs/lab13-logging-perf-benchmark/RESULTS.md \
  labs/lab13-logging-perf-benchmark/old/RESULTS.md \
  labs/lab13-logging-perf-benchmark/old/REVIEW.md \
  labs/lab13-logging-perf-benchmark/test_results_report.py
git commit -m "docs(lab13): publish reviewed results report

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Align REPORT.html with the reviewed RESULTS.md

**Files:**
- Modify: `labs/lab13-logging-perf-benchmark/REPORT.html`
- Modify: `labs/lab13-logging-perf-benchmark/test_report_html.py`
- Read: `labs/lab13-logging-perf-benchmark/RESULTS.md`
- Read: `labs/lab13-logging-perf-benchmark/old/REVIEW.md`

**Interfaces:**
- Consumes: Task 1's seven ordered summary headings and five reviewed verdicts.
- Produces: A customer-facing visual report whose primary narrative matches
  active `RESULTS.md` while preserving charts and audit cautions.

- [ ] **Step 1: Add failing alignment tests**

Add to `test_report_html.py`:

```python
RESULT_SUMMARY_HEADINGS = [
    "App Insights 본문 로깅은 처리시간을 늘렸다",
    "App Insights 집계는 무손실과 양립하지만 요청 단위 증명은 아니다",
    "API 성공과 Event Hub 로그 전달 성공은 별개다",
    "관측된 드롭은 EH 스로틀링으로 설명되지 않았다",
    "8KB 드롭 전이는 300~400 RPS 사이에서 관측됐다",
    "큰 요청은 처리시간과 로깅 운영 범위에 영향을 줬다",
    "Developer v1과 Basic v2에서 전달 결과 차이가 관측됐다",
]

RESULT_VERDICTS = {
    "q1": "조건부 지지",
    "q2": "미검증",
    "q3": "반박(본 Developer v1 고부하 조건)",
    "q4": "조건부 강함",
    "q5": "조건부 지지",
}
```

```python
def test_html_summary_matches_active_results_order(self):
    summary = re.search(
        r'id="panel-summary"[\s\S]*?</section>',
        self.html,
    ).group(0)
    positions = [summary.index(f'data-result-key="{index}"') for index in range(1, 8)]
    self.assertEqual(positions, sorted(positions))
    for heading in RESULT_SUMMARY_HEADINGS:
        self.assertIn(heading, summary)

def test_html_question_verdicts_match_active_results(self):
    hypotheses = re.search(
        r'id="panel-hypotheses"[\s\S]*?</section>',
        self.html,
    ).group(0)
    for question, verdict in RESULT_VERDICTS.items():
        card = re.search(
            rf'data-question="{question}"[\s\S]*?</article>',
            hypotheses,
        ).group(0)
        self.assertIn(verdict, card)

def test_sources_link_active_and_archived_reports(self):
    for href in (
        "RESULTS.md",
        "old/RESULTS.md",
        "old/REVIEW.md",
    ):
        self.assertIn(f'href="{href}"', self.html)
    self.assertNotIn('href="REVIEW.md"', self.html)
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
```

Expected: FAIL because the summary has five audit-first cards, the question
verdicts differ, and source links still point to active `REVIEW.md`.

- [ ] **Step 3: Align the HTML summary**

Replace the current five summary cards with seven cards in the exact active
Markdown order. Add `data-result-key="1"` through `"7"`.

Each card must:

- use the exact bold summary heading as its `<h3>`;
- contain the scoped explanation from active `RESULTS.md`;
- use the same evidence grade as active `RESULTS.md`;
- cite `RESULTS.md` and the underlying log/spec source.

Keep customer action items after the seven result conclusions.

- [ ] **Step 4: Align the five question cards**

Set `data-question="q1"` through `"q5"` and use the exact verdict strings:

- Q1: 조건부 지지
- Q2: 미검증
- Q3: 반박(본 Developer v1 고부하 조건)
- Q4: 조건부 강함
- Q5: 조건부 지지

For each card, copy the active Markdown's hypothesis, actual evidence, reason
for the verdict, and safe customer conclusion. Do not restore archived
overclaims.

- [ ] **Step 5: Preserve graphs and move audit framing to limitations**

- Do not change chart numeric attributes, bar widths, positions, ranges, or
  JSON tables.
- Update chart captions only where active `RESULTS.md` wording changed.
- Keep repetition, reconciliation, warmup, metadata-only, client latency, and
  v1/v2 metric-asymmetry cautions in the limitations panel.
- Add `old/REVIEW.md` as the archived audit basis.
- Source panel must mark:
  - `RESULTS.md`: active official result report;
  - `old/RESULTS.md`: prior interpretation;
  - `old/REVIEW.md`: archived review basis.

- [ ] **Step 6: Validate HTML and Markdown together**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_results_report.py \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
git diff --check -- \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
```

Expected: all tests PASS and no whitespace errors.

- [ ] **Step 7: Browser validation**

Open `REPORT.html` directly and through a local server. Verify:

- light and dark themes;
- seven summary cards in the active Markdown order;
- five question verdicts match active Markdown;
- result narrative precedes limitations;
- desktop, 1024px, 390px, print media, no-JavaScript, and offline behavior;
- no console errors or external requests;
- existing graph geometry is unchanged.

- [ ] **Step 8: Commit Task 2**

```bash
git add \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
git commit -m "docs(lab13): align HTML with reviewed results

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
