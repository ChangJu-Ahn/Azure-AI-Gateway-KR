# Lab 13 Evidence Review Design

## Purpose

Create a separate narrative audit report at
`labs/lab13-logging-perf-benchmark/REVIEW.md` without rewriting the existing
`RESULTS.md`.

The report will evaluate whether the Lab 13 conclusions are supported by:

- the original hypotheses and pass/fail criteria in `EXPERIMENT-SPEC.md`;
- the conditions actually executed and recorded in `EXPERIMENT-LOG.md`;
- the claims currently presented in `RESULTS.md`; and
- the practical decisions an APIM or AI Gateway customer can safely make.

The review will treat the work as a constrained, adaptive experiment. It will
not judge it against an ideal laboratory setup only. It will distinguish
between the best evidence obtainable under the actual constraints and claims
that exceed that evidence.

## Report Structure

1. **Executive assessment**
   - State whether the experiment was useful, where it was methodologically
     sound, and where the final report overstates certainty.
2. **What the experiment did well**
   - Cover fixed-arrival load, same-region placement, retry disabling,
     connection reuse, server-side metrics, and adaptive RPS/payload/SKU
     probes.
3. **Claims that are directly supported**
   - Include only observations defensible from the recorded runs without
     requiring an undocumented mechanism.
4. **Claims that are partially supported or inferential**
   - Preserve useful directional findings while identifying missing repeats,
     missing controls, asymmetric metrics, and unresolved mechanisms.
5. **Contradictions and overstatements**
   - Compare the preregistered criteria, actual execution, and final wording.
6. **Customer implications for APIM and AI Gateway**
   - Separate experimental findings from broader design considerations.
7. **Final confidence classification**
   - Summarize claims as confirmed, conditionally supported, unverified, or
     contradicted.

## Evidence Rules

- A server counter or request result can establish an observation, but not an
  internal mechanism unless Microsoft documentation explicitly describes it.
- `EventHubDroppedEvents > 0` establishes APIM-side skipped events. A zero
  counter alone does not establish end-to-end losslessness.
- Aggregate App Insights counts that include warmup traffic cannot prove that
  every measured request was stored unless request IDs are reconciled.
- A single run can establish that an event occurred, but not a stable
  threshold, variance, or universal performance relationship.
- Developer v1 versus Basic v2 is an operational comparison between two
  deployment profiles. It is not a clean single-variable SKU experiment.
- Client p99 affected by load-generator connection behavior cannot be used as
  authoritative APIM latency evidence.
- Customer recommendations must be labeled either as measured findings or as
  design considerations outside the experiment.

## Required Issues to Cover

- The specification required three repeats, balanced ordering, consumer ID
  reconciliation, payload hashes, and message-size verification; most were not
  executed.
- The N conditions still had App Insights metadata diagnostics enabled, so
  they are metadata-only baselines rather than true no-logging baselines.
- The H1 preregistered CPU/p99 criteria were replaced in practice by
  `Capacity` and `Duration`; therefore the original H1 was not tested exactly.
- `150,178 >= 150,000` is compatible with no loss but does not prove it because
  the query window included warmup records.
- The claimed 8 KB lossless threshold is bounded between tested points and was
  not verified by end-to-end request-ID reconciliation.
- The report treats 400 RPS as a normal/lossless EH point in one comparison,
  even though 2,933 drops were recorded.
- At 300 RPS and 64 KB, E64 Duration was lower than N64, contradicting the
  statement that every payload/RPS point showed no-logging latency below
  logging latency.
- The claim that App Insights is faster than Event Hub in the lossless range is
  not consistently supported by the 100/200/300 RPS measurements.
- The claim that Developer v1 has a practical 500 RPS processing limit exceeds
  the evidence and conflicts with the specification's prohibited conclusions.
- Basic v2 CPU and memory were not collected, so the explanation that it had
  gateway headroom remains inferential.
- The link between the APIM logger buffer and the generic network queue lengths
  used by the classic Capacity metric is plausible but not explicitly proven
  by the cited documentation.

## Customer-Facing Outcome

The report will preserve the strongest actionable lessons:

- API success does not prove audit-log delivery.
- APIM-side Event Hub drop counters and Event Hub ingress/throttling metrics
  must be monitored together.
- Request/log size materially changes the operating envelope.
- Capacity planning must include logging policies and should be validated at
  expected peak traffic.
- v1 and v2 use different gateway load metrics.

It will also state what the experiment did not cover for production AI Gateway
design: backend/model latency, streaming responses, response-body logging,
multiple units or regions, production SKUs, redaction and data governance,
cost, retention, and failure recovery.

## Acceptance Criteria

- Every criticism names the source mismatch that creates it.
- Every retained conclusion states its tested scope.
- No exact threshold or causal mechanism is presented as confirmed when only a
  single run or indirect metric supports it.
- The report remains constructive and customer-oriented rather than dismissing
  the experiment for not meeting an ideal design.
- `RESULTS.md` remains unchanged by this task.
