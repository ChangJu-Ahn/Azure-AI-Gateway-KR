# Lab 13 Reviewed Results and HTML Alignment Design

## Purpose

Replace the active Lab 13 results report with a reviewed, evidence-scoped
version while preserving the current results and audit report under `old/`.
Align `REPORT.html` with the new `RESULTS.md` so the HTML remains the visual
form of the official result report rather than a separate audit narrative.

## File Roles

- `RESULTS.md`: active and authoritative customer-facing result report.
- `REPORT.html`: visual representation of the active `RESULTS.md`, including
  the same summary, questions, verdicts, scope, and customer conclusions.
- `old/RESULTS.md`: exact copy of the current working-tree `RESULTS.md` before
  the rewrite.
- `old/REVIEW.md`: archived evidence-audit report that explains why the active
  result wording was corrected.
- `EXPERIMENT-SPEC.md`: original hypotheses and intended pass/fail criteria.
- `EXPERIMENT-LOG.md`: authority for conditions actually executed and recorded
  server-side measurements.

The active directory will no longer contain `REVIEW.md`.

## Archive Rules

1. Create `labs/lab13-logging-perf-benchmark/old/`.
2. Preserve the current working-tree `RESULTS.md`, including any uncommitted
   user edits, as `old/RESULTS.md` before replacing it.
3. Move the current `REVIEW.md` to `old/REVIEW.md`.
4. Do not overwrite either archived file after creation.
5. Do not move experiment specifications, logs, raw results, reproduction
   assets, or the decision tree.

## New RESULTS.md Structure

### 1. Title, terminology, and tested scope

Retain plain-language definitions for:

- log destination;
- lossless logging;
- dropped events;
- RPS;
- payload;
- SKU;
- Capacity and Duration.

State the tested scope prominently:

- Korea Central;
- Developer v1 and one Basic v2 comparison;
- 8 KB and 64 KB requests;
- 100-500 RPS;
- mostly one run per condition;
- 1,000 RPS official App Insights warning not tested.

### 2. Customer summary

Use scoped conclusions:

1. App Insights 8 KB body logging increased APIM Duration relative to the
   metadata-only baseline at recorded RPS points.
2. Aggregate App Insights counts were compatible with no loss, but warmup
   contamination and missing request-ID reconciliation prevent a request-level
   losslessness proof.
3. API requests can return HTTP 200 while APIM reports Event Hub log drops.
4. During the observed drops, the tested Event Hubs namespace reported no
   throttling; the drops were reported by APIM.
5. For 8 KB EH logging, APIM-reported drops were zero at the tested 300 RPS
   point and nonzero at 400 RPS, so the observed transition lies between those
   tested points rather than defining a universal 300 RPS threshold.
6. Larger requests materially increased APIM Duration and were associated with
   a narrower observed EH logging operating range.
7. Developer v1 and Basic v2 produced different delivery outcomes at the
   compared 8 KB 500 RPS condition, but asymmetric metrics and missing v2
   CPU/memory prevent a SKU-only causal claim.

### 3. Questions and verdicts

For each question, use:

- hypothesis;
- intended test criterion;
- actual evidence used;
- verdict grade;
- customer-safe conclusion.

Questions:

1. Does App Insights body logging affect APIM performance?
2. Can all requests be logged without performance degradation?
3. Does connecting Event Hub guarantee lossless log delivery?
4. Does payload size affect APIM processing and logging delivery?
5. Did the Developer v1 and Basic v2 comparison produce different results?

Verdict grades:

- Confirmed observation;
- Conditionally supported;
- Unverified;
- Corrected/rejected.

### 4. Directly verified findings

Include:

- HTTP 200 and `EventHubDroppedEvents > 0` can coexist.
- EH throttling was zero in the recorded drop windows.
- APIM-reported 8 KB EH drops decreased as offered RPS decreased.
- 64 KB requests had materially greater APIM Duration than 8 KB requests.
- A8 Duration exceeded the metadata-only N8 baseline at recorded RPS points.
- Basic v2 EH arrivals approximately matched offered volume in its observed
  comparison window.

### 5. Conditional findings

Include:

- App Insights aggregate losslessness;
- payload effect on the operating envelope;
- deployment-profile/SKU comparison;
- logger-buffer mechanism;
- an observed 300-to-400 RPS transition rather than a stable threshold.

Do not claim:

- Event Hub is always faster than App Insights;
- Developer v1 has a measured maximum of 500 RPS;
- Basic v2 is inherently lossless;
- SKU alone caused the improvement;
- client p99 proves a 16x APIM latency improvement;
- EH Duration differences during drops represent pure logging overhead.

### 6. Customer operational guidance

Include:

- separate API success and audit-log delivery SLOs;
- monitor APIM Event Hub success/drop metrics with EH ingress/throttling;
- capacity-test at peak RPS and realistic logged payload sizes;
- use classic `Capacity` for v1 and gateway CPU/memory for v2;
- minimize logged body size;
- repeat the test in the customer environment.

### 7. Limitations and unverified areas

Include:

- three repeats were planned but mostly one run was executed;
- request-ID, payload-hash, and message-size reconciliation was not completed;
- N conditions are metadata-only, not diagnostics disabled;
- App Insights aggregate count includes possible warmup boundary records;
- client p95/p99 contains load-generator/TLS artifacts;
- v1/v2 metrics are asymmetric and v2 CPU/memory was not collected;
- 1,000 RPS and production Standard/Premium behavior were not tested;
- no backend/model latency, streaming response, multi-unit, autoscale,
  multi-region, cost, retention, or governance testing.

## REPORT.html Alignment

`REPORT.html` must present `RESULTS.md` as its primary narrative.

### Summary

The HTML summary must use the same seven scoped conclusions and order as the
new Markdown summary. Evidence cautions remain visible but must not replace the
result narrative.

### Hypotheses

The five question cards must match the active Markdown hypotheses, evidence,
verdict grades, and safe customer conclusions.

### Results and charts

Keep all existing verified chart values and geometry. Update only wording,
badges, captions, and source descriptions needed to align with the new
Markdown. Do not modify quantitative source data.

### Limitations

Keep the audit findings in the limitations tab. Reference
`old/REVIEW.md` as the archived review basis.

### Sources

Link the active `RESULTS.md`, archived `old/RESULTS.md`, and
`old/REVIEW.md`. The active HTML must not imply that archived results remain
authoritative.

## Validation

Add or update tests to verify:

1. `old/RESULTS.md` exists and is byte-for-byte equal to the pre-rewrite
   working-tree result captured for the task.
2. `old/REVIEW.md` exists and active `REVIEW.md` does not.
3. The new `RESULTS.md` contains the seven scoped summary conclusions.
4. Prohibited overclaims are absent from active result conclusions.
5. N8/N64 are described as metadata-only baselines.
6. The active HTML summary contains the same seven conclusion identifiers and
   order as `RESULTS.md`.
7. The HTML five-question verdicts match `RESULTS.md`.
8. Existing 36 HTML report tests continue to pass.
9. The HTML links active and archived sources correctly.
10. Only Lab 13 result/report/archive/test files are committed.

## Non-Goals

- Do not change `EXPERIMENT-SPEC.md`, `EXPERIMENT-LOG.md`,
  `DECISION-TREE.md`, raw JSON result files, IaC, or execution scripts.
- Do not rerun Azure experiments.
- Do not delete the existing historical interpretation.
- Do not turn conditional findings into product-wide guarantees.
