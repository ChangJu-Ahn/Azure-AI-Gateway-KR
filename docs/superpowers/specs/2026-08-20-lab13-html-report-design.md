# Lab 13 HTML Report Design

## Purpose

Create a single, self-contained HTML report that allows a customer or
architect to understand the Lab 13 APIM logging experiment without first
reading the Markdown sources.

The report will summarize the hypotheses, actual conditions, quantitative
results, evidence limitations, and APIM/AI Gateway design considerations. It
will preserve links to the source files for readers who want to inspect the
details.

## Audience and Reading Order

The primary audience is customers and architects evaluating APIM as an AI
Gateway. The first screen will therefore present conclusions, risks, and
actions before implementation detail.

Engineering evidence remains available in later tabs:

1. Summary
2. Hypotheses and verdicts
3. Experiment conditions
4. Results and charts
5. Validation scope and cautions
6. Customer guidance
7. Source references

## Output

- Create `labs/lab13-logging-perf-benchmark/REPORT.html`.
- Deliver one HTML file with all CSS, JavaScript, text, and charts embedded.
- Do not use external CDNs, fonts, images, or JavaScript libraries.
- The report must remain readable when copied outside the repository.
- Relative source links are optional supporting navigation and may require the
  repository directory to remain beside the HTML file.
- State that the HTML is manually maintained and must be updated when source
  numbers change.

## Authoritative Sources

The report will use only:

- `EXPERIMENT-SPEC.md`
- `EXPERIMENT-LOG.md`
- `RESULTS.md`
- `DECISION-TREE.md`
- the 19 `results/*/result.json` client result files

`EXPERIMENT-SPEC.md` defines the intended hypotheses and original pass/fail
criteria. `EXPERIMENT-LOG.md` is the authority for actual execution conditions,
server metrics, run windows, and discovered deviations. `RESULTS.md` supplies
the current narrative conclusions. `DECISION-TREE.md` supplies the existing
customer guidance. The JSON files supply client offered/success counts and
latency distributions.

The HTML must not introduce numbers that are absent from these sources.

## Evidence Model

Every major conclusion and chart must show its evidence status:

- **Confirmed**: directly supported by a recorded counter or request result.
- **Conditional**: directionally supported but limited by repetition,
  reconciliation, or asymmetric metrics.
- **Unverified**: required evidence was not collected.
- **Corrected**: the source documents contain conflicting or overly broad
  wording.

The report must distinguish:

- API request success from audit-log delivery success;
- an APIM-reported drop count of zero from end-to-end request-ID
  reconciliation;
- measured behavior from an inferred internal mechanism;
- Developer v1 classic Capacity from v2 gateway CPU and memory metrics;
- exact numeric values from qualitative statements such as "large" or "about
  half."

## Tab Content

### Summary

Show:

- the experiment question;
- three to five scoped conclusions;
- a compact confidence legend;
- customer actions: validate at peak load, monitor APIM and EH separately,
  include payload size in capacity planning, and use the correct v1/v2 load
  metrics;
- a visible scope statement: Korea Central, Developer v1 plus one Basic v2
  comparison, 8 KB and 64 KB, 100-500 RPS, mostly one run per cell.

### Hypotheses and Verdicts

For each final question, show:

- original hypothesis;
- intended criterion from the specification;
- actual evidence used;
- current verdict;
- evidence grade;
- the wording a customer may safely reuse.

This tab must reveal where the execution method differed from the original
specification, including the planned three repeats and request-ID/hash
reconciliation.

### Experiment Conditions

Show:

- APIM deployment profiles and region;
- Event Hubs Standard 40 TU, 32 partitions, auto-inflate disabled;
- D8as_v5 load VM and open-workload generator;
- retry disabled, connection reuse, concurrency 20, warmup;
- N8, A8, E8, N64, and E64 condition definitions;
- the shared App Insights metadata background in every condition;
- requested RPS and payload matrix;
- the difference between classic Capacity and v2 CPU/memory metrics.

### Results and Charts

Include static inline SVG or CSS charts:

1. 8 KB APIM Capacity versus RPS for N8, A8, and E8.
2. 8 KB APIM Duration versus RPS for N8, A8, and E8.
3. 8 KB APIM-reported EH drops versus RPS.
4. 64 KB N64 versus E64 Duration at 300 and 500 RPS.
5. 64 KB APIM-reported EH drops at 300 and 500 RPS.
6. Client p50, p95, and p99 by run, clearly labeled as supporting evidence.
7. Offered versus successful request counts.
8. Developer v1 versus Basic v2 using only comparable observed fields.
9. A compact hypothesis confidence summary.

For 500 RPS E8, do not convert "large/about half" into a fabricated exact bar.
Use a qualitative annotation or an unscaled marker with "exact rate
unconfirmed."

Charts must display:

- units;
- run or condition identifiers;
- source file;
- confidence or caution label;
- explanatory captions where a metric is not directly comparable.

### Validation Scope and Cautions

Summarize contradictions found by comparing the four Markdown sources:

- most cells were run once despite a three-repeat specification;
- request-ID, payload-hash, and message-size reconciliation was not completed;
- N is a metadata-only App Insights baseline, not a true diagnostics-off
  baseline;
- App Insights aggregate counts include warmup boundary contamination;
- a zero APIM drop counter does not prove end-to-end delivery;
- the observed 300-to-400 RPS transition is not a stable universal threshold;
- Developer v1 and Basic v2 used asymmetric metrics;
- Basic v2 CPU and memory were not collected;
- client p99 contains load-generator/TLS artifacts;
- 1,000 RPS and the official 40-50% throughput warning were not tested.

### Customer Guidance

Use the decision tree content to cover:

- monitoring/diagnostics versus all-log audit requirements;
- App Insights versus Event Hubs based on purpose, not assumed losslessness;
- peak RPS multiplied by logged payload size;
- APIM-side drop metrics plus Event Hubs ingress/throttling;
- SKU/capacity headroom and v1/v2 metric differences;
- logging payload minimization;
- the requirement to run environment-specific load tests.

Clearly separate measured lessons from broader production considerations that
were not tested.

### Source References

List and link:

- the four Markdown source files;
- all 19 result JSON files grouped by RPS, payload, and condition.

Show a short description of what each source contributes.

## Visual Design

- Use a customer-oriented executive dashboard layout.
- Use tabs for navigation; charts themselves remain static.
- Use green for confirmed observations, yellow for conditional claims, red for
  drops and risks, and gray for unverified items.
- Do not rely on color alone; every status needs a text label.
- Use plain Korean and define unavoidable English terms.
- Support desktop and mobile widths.
- In print mode, show all tabs as consecutive sections and hide navigation.
- With JavaScript disabled, all sections must remain readable.

## Interaction

JavaScript is limited to tab selection and small navigation conveniences.
There are no dynamic chart filters, external data fetches, or runtime file
loading. All content is present in the document at load time.

## Validation

Before completion:

1. Open the file directly with network access disabled.
2. Verify every tab.
3. Verify responsive layout and print layout.
4. Confirm no browser-console errors.
5. Reconcile every chart value with a named Markdown table or JSON field.
6. Confirm qualitative values were not converted into invented numbers.
7. Confirm every major conclusion has an evidence grade and scope.
8. Confirm source links and the list of 19 JSON files are complete.
9. Confirm the document remains understandable when source links are
   unavailable.

## Non-Goals

- No automatic HTML generator.
- No external charting library.
- No live Azure metric queries.
- No advanced cross-run filters.
- No modification of the four Markdown sources or JSON results.
- No claim that this report establishes production-wide APIM limits.
