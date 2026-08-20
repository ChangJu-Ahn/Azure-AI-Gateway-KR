# Lab 13 HTML Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a customer-first, self-contained `REPORT.html` that summarizes the Lab 13 hypotheses, conditions, quantitative results, evidence limitations, and APIM/AI Gateway guidance with static charts.

**Architecture:** Author one offline HTML file directly, with embedded CSS, embedded tab-navigation JavaScript, and inline SVG/CSS charts. Add a Python standard-library contract test that validates tab structure, offline dependencies, source coverage, evidence labels, and the presence of every required source/result reference.

**Tech Stack:** HTML5, CSS, inline SVG, vanilla JavaScript, Python `unittest`, `html.parser`, browser validation

## Global Constraints

- Create `labs/lab13-logging-perf-benchmark/REPORT.html`.
- Use only `EXPERIMENT-SPEC.md`, `EXPERIMENT-LOG.md`, `RESULTS.md`, `DECISION-TREE.md`, and the 19 `results/*/result.json` files as evidence sources.
- Do not modify the source Markdown or JSON files.
- Do not use external CDNs, fonts, images, JavaScript libraries, or runtime data fetches.
- All essential content must remain readable when JavaScript is disabled.
- JavaScript is limited to tab navigation and small navigation conveniences.
- Charts are static inline SVG or CSS; there are no interactive chart filters.
- Never convert qualitative values such as “대량” or “약 절반” into fabricated exact numbers.
- Every major claim and chart must show a source and evidence label.
- Use green for confirmed, yellow for conditional, red for drops/risks, and gray for unverified; do not rely on color alone.
- Support desktop, mobile, and print; print mode displays all tab panels in sequence.
- The report is manually maintained and must say that source-number changes require a manual HTML update.
- Invoke the `web-artifacts-builder` skill before writing the HTML and follow its Clawpilot theme-variable requirements.

---

### Task 1: Add the offline report contract and tab shell

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/test_report_html.py`
- Create: `labs/lab13-logging-perf-benchmark/REPORT.html`

**Interfaces:**
- Consumes: The approved report design and existing Lab 13 source file names.
- Produces: A seven-tab HTML shell whose DOM contract is validated by `test_report_html.py`.

- [ ] **Step 1: Invoke the HTML artifact skill**

Invoke `web-artifacts-builder` before creating `REPORT.html`. Use the skill’s
required Clawpilot CSS variables for all color and typography tokens.

- [ ] **Step 2: Write the failing structural tests**

Create `test_report_html.py` using only the Python standard library:

```python
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).parent
REPORT = ROOT / "REPORT.html"

TAB_IDS = [
    "summary",
    "hypotheses",
    "conditions",
    "results",
    "limitations",
    "guidance",
    "sources",
]

SOURCE_DOCS = [
    "EXPERIMENT-SPEC.md",
    "EXPERIMENT-LOG.md",
    "RESULTS.md",
    "DECISION-TREE.md",
]


class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.tabs = []
        self.external_assets = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"])
        if values.get("role") == "tab":
            self.tabs.append(values)
        if tag in {"script", "link", "img"}:
            target = values.get("src") or values.get("href")
            if target and re.match(r"^(?:https?:)?//", target):
                self.external_assets.append(target)


class ReportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = REPORT.read_text(encoding="utf-8")
        cls.parser = ReportParser()
        cls.parser.feed(cls.html)

    def test_has_required_tabs_and_panels(self):
        self.assertEqual(
            [tab["data-tab"] for tab in self.parser.tabs],
            TAB_IDS,
        )
        for tab_id in TAB_IDS:
            self.assertIn(f"panel-{tab_id}", self.parser.ids)

    def test_is_self_contained(self):
        self.assertEqual(self.parser.external_assets, [])
        self.assertNotRegex(self.html, r"\bfetch\s*\(")

    def test_references_all_source_documents(self):
        for source in SOURCE_DOCS:
            self.assertIn(source, self.html)

    def test_has_accessible_tab_markup(self):
        for tab in self.parser.tabs:
            self.assertEqual(tab.get("aria-controls"), f"panel-{tab['data-tab']}")
        self.assertIn('role="tabpanel"', self.html)

    def test_print_and_no_script_fallbacks_exist(self):
        self.assertIn("@media print", self.html)
        self.assertIn("<noscript>", self.html)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the structural tests and verify failure**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
```

Expected: ERROR because `REPORT.html` does not exist.

- [ ] **Step 4: Create the minimal self-contained tab shell**

Create `REPORT.html` with:

- `<!doctype html>` and `<html lang="ko">`;
- embedded `<style>` using Clawpilot theme variables;
- a header containing the report title, tested scope, evidence legend, and the
  manual-maintenance notice;
- seven `<button role="tab">` elements in this exact order:
  `summary`, `hypotheses`, `conditions`, `results`, `limitations`, `guidance`,
  `sources`;
- seven corresponding `<section role="tabpanel" id="panel-...">` elements;
- embedded JavaScript that toggles panels, `aria-selected`, and `tabindex`;
- `<noscript>` text explaining that all panels remain visible without
  JavaScript;
- `@media print` that hides tab navigation and displays every panel;
- `@media (max-width: 760px)` that stacks cards and makes tables horizontally
  scrollable.

Use this tab button contract exactly:

```html
<button
  type="button"
  role="tab"
  data-tab="summary"
  aria-controls="panel-summary"
  aria-selected="true"
>
  요약
</button>
```

Use progressively enhanced panel behavior: panels are visible by default;
JavaScript adds `document.documentElement.classList.add("js")`, and only
`.js [role="tabpanel"]:not(.is-active)` is hidden.

- [ ] **Step 5: Run the structural tests**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
```

Expected: all Task 1 tests PASS.

- [ ] **Step 6: Commit the shell**

```bash
git add \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
git commit -m "docs(lab13): add offline report shell

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add authoritative content and static charts

**Files:**
- Modify: `labs/lab13-logging-perf-benchmark/REPORT.html`
- Modify: `labs/lab13-logging-perf-benchmark/test_report_html.py`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md`
- Read: `labs/lab13-logging-perf-benchmark/EXPERIMENT-LOG.md`
- Read: `labs/lab13-logging-perf-benchmark/RESULTS.md`
- Read: `labs/lab13-logging-perf-benchmark/DECISION-TREE.md`
- Read: `labs/lab13-logging-perf-benchmark/results/*/result.json`

**Interfaces:**
- Consumes: The seven-panel DOM contract from Task 1.
- Produces: Complete Korean report content, nine static visualizations, source
  labels, confidence labels, and references to all 19 JSON files.

- [ ] **Step 1: Extend tests for content and source completeness**

Add these constants and tests to `test_report_html.py`:

```python
RESULT_FILES = sorted(
    str(path.relative_to(ROOT))
    for path in (ROOT / "results").glob("*/result.json")
)

REQUIRED_CHARTS = [
    "chart-capacity-8k",
    "chart-duration-8k",
    "chart-drops-8k",
    "chart-duration-64k",
    "chart-drops-64k",
    "chart-client-latency",
    "chart-request-success",
    "chart-sku-comparison",
    "chart-confidence",
]

REQUIRED_EVIDENCE_LABELS = [
    "확정",
    "조건부",
    "미검증",
    "교정",
]
```

```python
def test_references_all_19_client_results(self):
    self.assertEqual(len(RESULT_FILES), 19)
    for result_file in RESULT_FILES:
        self.assertIn(result_file, self.html)

def test_has_all_required_charts(self):
    for chart_id in REQUIRED_CHARTS:
        self.assertIn(chart_id, self.parser.ids)

def test_uses_all_evidence_labels(self):
    for label in REQUIRED_EVIDENCE_LABELS:
        self.assertIn(label, self.html)

def test_contains_required_scope_and_cautions(self):
    required = [
        "Korea Central",
        "Developer v1",
        "Basic v2",
        "8KB",
        "64KB",
        "100~500 RPS",
        "3회 반복",
        "metadata-only",
        "1,000 RPS",
        "warmup",
        "request ID",
    ]
    for phrase in required:
        self.assertIn(phrase, self.html)

def test_does_not_invent_exact_500_rps_e8_drop_count(self):
    self.assertIn("정확한 드롭률 미확정", self.html)
    self.assertNotRegex(
        self.html,
        r'data-run="real-E8"[^>]*data-drop-count="\d+"',
    )
```

- [ ] **Step 2: Run the new tests and verify failure**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
```

Expected: FAIL for missing charts, result references, evidence labels, and
scope/caution text.

- [ ] **Step 3: Populate Summary, Hypotheses, and Conditions**

Add customer-first content:

- Summary cards:
  - API success does not prove EH log delivery.
  - The tested EH namespace did not throttle during APIM-reported drops.
  - Larger payloads narrowed the observed operating range.
  - App Insights body logging increased APIM Duration versus metadata-only.
  - Basic v2 delivered the offered message count in the observed comparison
    window, but the mechanism is not proven.
- Scope strip:
  `Korea Central · Developer v1 + Basic v2 comparison · 8KB/64KB ·
  100~500 RPS · mostly one run per cell`.
- Hypothesis cards showing intended criterion, actual evidence, verdict, and
  evidence grade.
- Conditions table for N8/A8/E8/N64/E64.
- Explicit warning that N means App Insights metadata-only, not diagnostics
  disabled.
- Planned versus executed comparison:
  three repeats and ID/hash reconciliation planned; mostly one run and server
  counters used.

- [ ] **Step 4: Add the 8 KB server-metric charts**

Use inline SVG/CSS with the following reported values:

Capacity:

| RPS | N8 | A8 | E8 |
|---:|---:|---:|---:|
| 100 | 31.5 | 39 | 38 |
| 200 | 58 | 66 | 85 |
| 300 | 79 | 88.5 | 86.5 |
| 400 | 85.5 | 84.5 | 85.5 |
| 500 | ~89 | ~89 | ~87 |

Duration in milliseconds:

| RPS | N8 | A8 | E8 |
|---:|---:|---:|---:|
| 100 | 0.01 | 0.03 | 0.03 |
| 200 | 0.02 | 0.05 | 0.04 |
| 300 | 0.06 | 0.13 | 0.36 |
| 400 | 0.03 | 0.64 | 1.00 |
| 500 | 0.10-0.35 | 0.90-2.50 | 0.40-1.70 |

EH drops:

| RPS | E8 drops |
|---:|---:|
| 100 | 0 |
| 200 | 0 |
| 300 | 0 |
| 400 | 2,933 |
| 500 | qualitative: large/about half; exact rate unconfirmed |

At 500 RPS, render min/max range marks for Duration instead of converting
ranges into a single invented point. For E8 drops, render a labeled unscaled
warning marker with no numeric `data-drop-count`.

- [ ] **Step 5: Add the 64 KB and client charts**

Use these server values:

| RPS | N64 Duration | E64 Duration | E64 drops |
|---:|---:|---:|---:|
| 300 | 6.04 | 5.24 | 41,435 |
| 500 | 7.32 | 7.58 | 76,434 |

For client latency, read and display the exact p50/p95/p99 values from all 19
JSON files. Show the chart as supporting evidence with a visible warning:
client p95/p99 contains load-generator/TLS artifacts and is not the
authoritative APIM latency measure.

For offered versus successful requests, show that each of the 19 JSON files
has `offered == successful` and errors `0`, while stating that API success does
not establish audit-log success.

- [ ] **Step 6: Add SKU comparison and confidence visuals**

SKU comparison:

- Developer v1: 8 KB, 500 RPS, APIM-reported large drops/about half,
  EH throttled 0.
- Basic v2: observed EH arrival approximately 30,000/minute, EH throttled 0,
  client requests all 200.
- Do not show a common Capacity chart because v2 classic Capacity is
  unsupported and v2 CPU/memory was not collected.
- Label the comparison `조건부`: operational difference observed, mechanism
  and SKU-only causality unproven.

Confidence chart:

- Confirmed: HTTP 200 can coexist with APIM EH drops; EH throttling was zero in
  the tested runs; observed APIM drops decreased with lower 8 KB RPS.
- Conditional: App Insights aggregate losslessness; payload operating-envelope
  effect; deployment-profile effect.
- Unverified: stable 300 RPS lossless threshold; Basic v2 inherent
  losslessness; exact queue mechanism.
- Corrected: Event Hub always faster; Developer v1 maximum is 500 RPS.

- [ ] **Step 7: Populate Limitations, Guidance, and Sources**

Limitations must include:

- planned three repeats versus mostly one run;
- missing request-ID/hash/message-size reconciliation;
- metadata-only baseline;
- warmup contamination in App Insights counts;
- drop=0 versus end-to-end losslessness;
- 300-to-400 RPS transition versus stable threshold;
- asymmetric v1/v2 metrics and missing v2 CPU/memory;
- client p99 artifacts;
- untested 1,000 RPS official warning.

Guidance must cover:

- separate API and logging SLOs;
- monitor APIM EH success/drop metrics with EH ingress/throttling;
- plan for peak RPS multiplied by logged payload size;
- use classic Capacity for v1 and CPU/memory metrics for v2;
- reduce logged body size;
- retest in the customer environment.

Sources must list the four Markdown files and all 19 relative JSON paths.

- [ ] **Step 8: Run all contract tests**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
```

Expected: all tests PASS.

Run:

```bash
git diff --check -- \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
```

Expected: no output.

- [ ] **Step 9: Commit complete content**

```bash
git add \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
git commit -m "docs(lab13): populate evidence-based HTML report

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Validate the report in a browser and polish delivery

**Files:**
- Modify: `labs/lab13-logging-perf-benchmark/REPORT.html`
- Modify: `labs/lab13-logging-perf-benchmark/test_report_html.py` only if a
  browser-discovered regression needs a contract test

**Interfaces:**
- Consumes: The complete self-contained report from Task 2.
- Produces: Browser-verified desktop, mobile, print, offline, and no-JavaScript
  behavior.

- [ ] **Step 1: Start a local static server**

Run as a detached background server:

```bash
python3 -m http.server 8765 --directory \
  labs/lab13-logging-perf-benchmark
```

Expected: server listens on `http://localhost:8765/REPORT.html`.

- [ ] **Step 2: Validate desktop behavior**

Open `http://localhost:8765/REPORT.html` in the browser and verify:

- the Summary tab is selected on load;
- each of the seven tab buttons displays its corresponding panel;
- keyboard focus and arrow/tab navigation remain visible;
- no horizontal clipping occurs at 1440px width;
- chart captions, sources, units, and evidence labels are legible;
- the browser console contains no errors or failed network requests.

- [ ] **Step 3: Validate mobile and print behavior**

At 390px width verify:

- tab navigation is scrollable or wrapped;
- cards stack vertically;
- tables scroll inside their containers;
- SVG text remains readable and does not overflow.

Use print preview and verify:

- tab navigation is hidden;
- all seven panels print in sequence;
- charts are not clipped across pages;
- status labels remain understandable in grayscale.

- [ ] **Step 4: Validate no-JavaScript and offline behavior**

Disable JavaScript or remove the `js` class in browser developer tools:

- all panels remain visible;
- no essential conclusion or chart disappears.

Stop the local server and open `REPORT.html` directly:

- content and charts render;
- no external request is attempted;
- only optional relative source links depend on repository placement.

- [ ] **Step 5: Add any regression tests and polish**

If browser validation reveals a defect, first add a failing test to
`test_report_html.py` that captures the issue, then update `REPORT.html`.

Examples:

- missing mobile viewport:

```python
def test_has_mobile_viewport(self):
    self.assertIn(
        'name="viewport" content="width=device-width, initial-scale=1"',
        self.html,
    )
```

- tab JavaScript without keyboard handling:

```python
def test_tabs_have_keyboard_navigation(self):
    self.assertIn('"ArrowRight"', self.html)
    self.assertIn('"ArrowLeft"', self.html)
    self.assertIn('"Home"', self.html)
    self.assertIn('"End"', self.html)
```

- [ ] **Step 6: Run final verification**

Run:

```bash
python3 -m unittest \
  labs/lab13-logging-perf-benchmark/test_report_html.py -v
git diff --check -- \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
```

Expected: all tests PASS and no whitespace errors.

- [ ] **Step 7: Commit browser polish**

If Task 3 changed files:

```bash
git add \
  labs/lab13-logging-perf-benchmark/REPORT.html \
  labs/lab13-logging-perf-benchmark/test_report_html.py
git commit -m "docs(lab13): validate and polish HTML report

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

If no files changed, record browser verification results without creating an
empty commit.
