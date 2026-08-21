# Lab 13 Concise Results Report Design

## Purpose

Restructure the active `labs/lab13-logging-perf-benchmark/RESULTS.md` into a
concise customer result report of approximately 100-120 lines.

The current report is already shorter than the archived report, but it feels
long because the same evidence limitations are repeated under the summary,
each question, direct findings, conditional findings, and limitations. The new
version will preserve the measured values and reviewed verdicts while moving
shared caveats to one limitations section.

`REPORT.html` is explicitly out of scope for this task. It will be aligned only
after the concise Markdown result is reviewed and accepted.

## Required Structure

1. **Title and tested scope**
   - Plain-language definitions only where needed.
   - Four to six bullets for region, deployment profiles, payload sizes, RPS,
     repetition, and the untested 1,000 RPS range.
2. **Five-question conclusion table**
   - Question
   - Verdict
   - Key evidence
   - Customer meaning
3. **Five short question sections**
   - Hypothesis: one line
   - Verdict: one line
   - Key numbers: one compact table or up to three bullets
   - Conclusion: one line
4. **Customer operating recommendations**
   - Five to seven bullets.
5. **Limitations**
   - One consolidated list for repetition, request-ID/hash reconciliation,
     warmup contamination, metadata-only baseline, client latency artifacts,
     v1/v2 metric asymmetry, and untested 1,000 RPS/production conditions.
6. **Source documents**
   - Compact table linking specification, log, archived prior result, archived
     review, decision guide, and HTML report.

## Content Rules

- Keep the five reviewed verdicts:
  - Q1: 조건부 지지
  - Q2: 미검증
  - Q3: 반박(본 Developer v1 고부하 조건)
  - Q4: 조건부 강함
  - Q5: 조건부 지지
- Preserve the measured Duration, Capacity, drop, and v1/v2 delivery values.
- N8/N64 remain App Insights metadata-only baselines.
- Keep the observed 300-to-400 RPS transition; do not call 300 RPS a stable
  lossless threshold.
- Keep the Basic v2 observed delivery difference; do not claim SKU-only
  causality or inherent losslessness.
- Do not use client p99 as authoritative APIM latency evidence.
- Do not call E-N Duration during drops pure Event Hub logging cost.
- State that active RESULTS takes precedence over conflicting older
  `DECISION-TREE.md` wording.

## Duplication to Remove

- Remove the separate `직접 확인된 사실` section when the same observations
  already appear in the question sections.
- Remove the separate `조건부로 지지되는 해석` section when the same caveats
  already appear in the verdicts and final limitations.
- Do not repeat warmup, repetition, request-ID reconciliation, or v1/v2 metric
  asymmetry under multiple questions.
- Replace multi-paragraph explanations with a single scoped conclusion.

## Readability Rules

- Prefer tables and bullets over paragraphs.
- No paragraph longer than three lines in typical Markdown preview.
- No question section longer than approximately 12 lines.
- Use plain Korean; retain only necessary product and metric names.
- Avoid defensive phrases such as “증명하지 못했다” repeatedly. State the
  measured conclusion first, then put shared qualification in `한계`.
- Target 100-120 lines, excluding unavoidable Markdown table wrapping.

## Validation

- Verify the report has exactly five question sections and five verdicts.
- Verify every required measured value remains present.
- Verify shared caveat phrases primarily occur in the limitations section.
- Verify prohibited overclaims remain absent.
- Verify active and archived document links resolve.
- Verify `old/RESULTS-Old.md`, `old/REVIEW.md`, `REPORT.html`, and all
  experiment sources remain unchanged.

## Non-Goals

- No HTML changes.
- No chart changes.
- No experiment reruns.
- No changes to `DECISION-TREE.md`.
- No changes to archived reports.
