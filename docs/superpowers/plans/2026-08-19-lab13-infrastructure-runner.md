# Lab 13 Infrastructure and Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Bicep and scripts that attach a reusable benchmark API to an existing APIM Developer v1 instance, deploy all other resources into a disposable resource group, and run the approved 15-run 500 RPS experiment from a dedicated VM.

**Architecture:** Bicep owns only disposable Event Hubs, monitoring, VM, and network resources. Local shell scripts own the existing APIM configuration and orchestrate condition changes; a k6/Python package on the VM generates load, consumes Event Hub messages, and reconciles every successful request ID.

**Tech Stack:** Bicep, Azure CLI, Bash, k6 JavaScript, Python 3.11+, `azure-identity`, `azure-eventhub`, standard-library `unittest`.

## Global Constraints

- Never delete, purge, redeploy, or change the SKU of the existing APIM.
- Keep `logbench-v4` API, operation, loggers, diagnostic, subscription, policy, and APIM system-assigned MI after teardown.
- Create every non-APIM resource in one disposable resource group tagged `managed-by=lab13-v4`.
- Teardown deletes only that tagged disposable resource group.
- Use Developer v1, 500 offered RPS, 8KB/64KB, and 15 base runs.
- Use one fixed `Standard_D8as_v5` Linux VM with a public IP; SSH is restricted to the detected caller IP `/32`.
- Use Event Hubs Standard, 40 fixed TU, 32 partitions, auto-inflate OFF.
- Use managed identity for APIM send and VM receive; do not use Event Hubs connection strings.
- Use `모든 요청`; do not use the superseded terminology.
- Do not require full GatewayLogs ingestion.
- Never commit subscription keys, SSH private keys, `.env.logbench-v4`, or result artifacts.

---

## File Map

```text
infra/logbench-v4.bicep
scripts/logbench-v4/common.sh
scripts/logbench-v4/deploy.sh
scripts/logbench-v4/configure-condition.sh
scripts/logbench-v4/run-experiment.sh
scripts/logbench-v4/download-results.sh
scripts/logbench-v4/teardown.sh
labs/lab13-logging-perf-benchmark/runner/package.json
labs/lab13-logging-perf-benchmark/runner/payload.js
labs/lab13-logging-perf-benchmark/runner/load.js
labs/lab13-logging-perf-benchmark/runner/collector.py
labs/lab13-logging-perf-benchmark/runner/consume.py
labs/lab13-logging-perf-benchmark/runner/reconcile.py
labs/lab13-logging-perf-benchmark/runner/run.sh
labs/lab13-logging-perf-benchmark/runner/bootstrap.sh
labs/lab13-logging-perf-benchmark/runner/requirements.txt
labs/lab13-logging-perf-benchmark/runner/tests/test_payload.mjs
labs/lab13-logging-perf-benchmark/runner/tests/test_reconcile.py
labs/lab13-logging-perf-benchmark/README.md
```

---

### Task 1: Implement payload generation and reconciliation

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/runner/package.json`
- Create: `labs/lab13-logging-perf-benchmark/runner/payload.js`
- Create: `labs/lab13-logging-perf-benchmark/runner/reconcile.py`
- Create: `labs/lab13-logging-perf-benchmark/runner/tests/test_payload.mjs`
- Create: `labs/lab13-logging-perf-benchmark/runner/tests/test_reconcile.py`

**Interfaces:**
- `buildPayload(requestId: string, sentAt: string, targetBytes: number, hashFn: (text: string) => string): {body: string, payloadHash: string}`
- `reconcile(success_path: Path, event_path: Path, expected_size: int) -> dict`
- Reconciliation result keys: `success_count`, `received_unique_count`, `missing_ids`, `duplicate_ids`, `hash_mismatches`, `size_mismatches`, `passed`.

- [ ] **Step 1: Write the payload tests**

```javascript
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { buildPayload } from "../payload.js";

const sha256 = text => createHash("sha256").update(text, "utf8").digest("hex");
for (const size of [8192, 65536]) {
  const result = buildPayload("run-1-000001", "2026-08-19T00:00:00.000Z", size, sha256);
  assert.equal(Buffer.byteLength(result.body, "utf8"), size);
  const parsed = JSON.parse(result.body);
  assert.equal(parsed.requestId, "run-1-000001");
  assert.equal(parsed.payloadHash, sha256(parsed.payload));
}
assert.throws(() => buildPayload("x", "t", 10, sha256), /too small/);
```

- [ ] **Step 2: Write reconciliation tests**

Use temporary JSONL files with these exact cases:

```python
def test_all_received_passes(self):
    # successes: a,b; events: a,b with matching hash and 8192 bytes
    self.assertTrue(result["passed"])

def test_missing_duplicate_hash_and_size_fail(self):
    # successes: a,b,c; events: a,a,b; b has bad hash and size
    self.assertEqual(result["missing_ids"], ["c"])
    self.assertEqual(result["duplicate_ids"], ["a"])
    self.assertEqual(result["hash_mismatches"], ["b"])
    self.assertEqual(result["size_mismatches"], ["b"])
    self.assertFalse(result["passed"])
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
cd labs/lab13-logging-perf-benchmark/runner
node tests/test_payload.mjs
python3 -m unittest tests/test_reconcile.py -v
```

Expected: both fail because the modules do not exist.

- [ ] **Step 4: Implement `payload.js`**

Build an ASCII-only JSON object with keys `requestId`, `sentAt`, `payloadHash`, and `payload`. Calculate the padding using a 64-character hash placeholder, hash the final padding, serialize again, and reject any byte length not exactly `targetBytes`.

- [ ] **Step 5: Implement `reconcile.py`**

Read success JSONL records `{requestId,payloadHash}` and event JSONL records `{requestId,payloadHash,byteSize,enqueuedTime}`. Detect duplicate event IDs before building the unique map. Pass only when missing, duplicate, hash mismatch, and size mismatch lists are all empty.

Provide CLI:

```bash
python3 reconcile.py \
  --success successes.jsonl \
  --events events.jsonl \
  --expected-size 8192 \
  --output reconciliation.json
```

- [ ] **Step 6: Run tests**

Expected:

```text
payload tests passed
Ran 2 tests ... OK
```

- [ ] **Step 7: Commit**

```bash
git add labs/lab13-logging-perf-benchmark/runner
git commit -m "feat(lab13): add payload and reconciliation core" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Implement the VM runtime package

**Files:**
- Create: `labs/lab13-logging-perf-benchmark/runner/load.js`
- Create: `labs/lab13-logging-perf-benchmark/runner/collector.py`
- Create: `labs/lab13-logging-perf-benchmark/runner/consume.py`
- Create: `labs/lab13-logging-perf-benchmark/runner/run.sh`
- Create: `labs/lab13-logging-perf-benchmark/runner/bootstrap.sh`
- Create: `labs/lab13-logging-perf-benchmark/runner/requirements.txt`

**Interfaces:**
- Environment consumed by `load.js`: `RUN_ID`, `TARGET_URL`, `SUBSCRIPTION_KEY`, `PAYLOAD_BYTES`, `CONDITION`, `POLICY_HASH`, `RATE`, `RAMP_SECONDS`, `STABILIZE_SECONDS`, `STEADY_SECONDS`, `COLLECTOR_URL`.
- `collector.py --port 8787 --output <path>` accepts `POST /record` JSON.
- `consume.py --namespace <fqdn> --eventhub <name> --consumer-group <name> --run-id <id> --output <path> --idle-seconds 120 --max-seconds 600`.
- `run.sh <condition> <repeat>` creates one self-contained result directory.

- [ ] **Step 1: Add runtime dependencies**

`requirements.txt`:

```text
azure-eventhub==5.15.0
azure-identity==1.25.1
```

`package.json`:

```json
{"type":"module","scripts":{"test":"node tests/test_payload.mjs"}}
```

- [ ] **Step 2: Implement `collector.py` and test locally**

Use `ThreadingHTTPServer` bound to `127.0.0.1`. Accept only `/record`; validate `requestId`, `payloadHash`, `success`, and append one JSON object per line under a lock. Return 204. Return 400 for invalid JSON and 404 for other paths.

Run:

```bash
python3 collector.py --port 8787 --output /tmp/collector.jsonl &
pid=$!
curl -fsS -X POST http://127.0.0.1:8787/record \
  -H 'Content-Type: application/json' \
  -d '{"requestId":"a","payloadHash":"h","success":true}'
kill "$pid"
grep -q '"requestId": "a"' /tmp/collector.jsonl
```

Expected: exit 0.

- [ ] **Step 3: Implement `load.js`**

Support `PHASE=warmup` with `ramping-arrival-rate` from 1 to `RATE=500` for 60 seconds followed by 60 seconds at 500, and `PHASE=measure` with `constant-arrival-rate` at 500 for 300 seconds. Allocate enough VUs through environment values `PRE_ALLOCATED_VUS=100` and `MAX_VUS=250`. Use `k6/crypto.sha256` with `buildPayload`. Send:

```text
POST TARGET_URL
Ocp-Apim-Subscription-Key: SUBSCRIPTION_KEY
x-logbench-request-id: <RUN_ID>-<scenario iteration>
Content-Type: application/json
```

Tag the APIM request `target=apim`. Verify status 200 and response headers `x-logbench-request-id`, `x-logbench-condition`, and `x-logbench-policy-hash`. POST the result to the local collector with `target=collector`. Configure thresholds only on `{target:apim}`.

- [ ] **Step 4: Implement `consume.py`**

Authenticate with `DefaultAzureCredential`, receive from `@latest`, signal readiness only after the receive loop starts, ignore messages whose JSON lacks the current `runId` prefix, and write JSONL containing request ID, hash, byte size, enqueued time, and receive time. Exit after 120 seconds without a matching event or after 600 seconds total, whichever occurs first, and close the consumer cleanly.

- [ ] **Step 5: Implement `run.sh`**

Use `set -euo pipefail` and traps. Start collector and consumer, wait for both readiness files, run the discarded warm-up k6 phase, then run the measured 300-second k6 phase into a separate summary file. Wait for the consumer's own quiet-period exit, stop the collector, run reconciliation, and write `manifest.json` with process exit codes and validity. Never aggregate warm-up metrics into the measured result.

- [ ] **Step 6: Implement `bootstrap.sh`**

Install k6 from the official apt repository, create `.venv`, install pinned requirements, print versions, and write `versions.json`. Make reruns idempotent.

- [ ] **Step 7: Validate**

Run:

```bash
bash -n bootstrap.sh run.sh
python3 -m py_compile collector.py consume.py reconcile.py
node tests/test_payload.mjs
python3 -m unittest tests/test_reconcile.py -v
```

Expected: all exit 0.

- [ ] **Step 8: Commit**

```bash
git add labs/lab13-logging-perf-benchmark/runner
git commit -m "feat(lab13): add VM benchmark runtime" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Add disposable Azure infrastructure

**Files:**
- Create: `infra/logbench-v4.bicep`

**Interfaces:**
- Parameters: `location`, `suffix`, `adminUsername`, `sshPublicKey`, `sshSourceCidr`, `apimPrincipalId`.
- Outputs: VM public IP/FQDN, EH namespace/name/consumer group, App Insights resource ID/connection string, VM principal ID.

- [ ] **Step 1: Write the Bicep resources**

Create:

- VNet/subnet
- NSG with SSH source `sshSourceCidr` and no wildcard inbound
- static Standard public IP and NIC with accelerated networking
- Ubuntu 22.04 `Standard_D8as_v5` VM with system MI and SSH key auth only
- Log Analytics `PerGB2018`, 30-day retention
- workspace-based Application Insights
- Event Hubs Standard namespace with capacity 40 and `isAutoInflateEnabled: false`
- event hub with 32 partitions and one-day retention
- consumer group `logbench-v4`
- APIM principal role assignment `Azure Event Hubs Data Sender`
- VM principal role assignment `Azure Event Hubs Data Receiver`
- tag every resource `managed-by: lab13-v4`

- [ ] **Step 2: Compile**

Run:

```bash
az bicep build --file infra/logbench-v4.bicep
```

Expected: exit 0 and generated JSON.

- [ ] **Step 3: Verify safety markers**

Run:

```bash
grep -q \"capacity: 40\" infra/logbench-v4.bicep
grep -q \"isAutoInflateEnabled: false\" infra/logbench-v4.bicep
grep -q \"partitionCount: 32\" infra/logbench-v4.bicep
! grep -q \"Microsoft.ApiManagement/service\" infra/logbench-v4.bicep
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add infra/logbench-v4.bicep infra/logbench-v4.json
git commit -m "feat(lab13): add disposable benchmark infrastructure" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Add APIM configuration and deployment scripts

**Files:**
- Create: `scripts/logbench-v4/common.sh`
- Create: `scripts/logbench-v4/deploy.sh`
- Create: `scripts/logbench-v4/configure-condition.sh`
- Create: `scripts/logbench-v4/teardown.sh`

**Interfaces:**
- Required input: `LOGBENCH_APIM_NAME`, `LOGBENCH_APIM_RG`.
- Optional input: `LOGBENCH_SUBSCRIPTION_ID`, `LOGBENCH_LOCATION=japaneast`, `LOGBENCH_SSH_CIDR`.
- Produced secret file: `.env.logbench-v4`, mode 0600.

- [ ] **Step 1: Implement `common.sh`**

Provide `require_cmd`, `require_env`, `az_retry`, `load_env`, `assert_managed_rg`, `apim_resource_id`, and `sha256_file`. Every failure prints the failed operation and exits nonzero.

- [ ] **Step 2: Implement deploy preflight**

Verify Azure login, selected subscription, APIM exists, SKU is Developer, location is Japan East, and no conflicting `logbench-v4` API/logger exists. Mark the API and logger descriptions with `managed-by=lab13-v4`, the subscription display name with `managed-by=lab13-v4`, and the policy with an XML comment containing that marker. If an object with the fixed ID exists without its marker, stop. Treat the diagnostic as managed only when its parent API passed the marker check.

Detect source IP with:

```bash
curl --fail --silent --show-error --max-time 10 https://api.ipify.org
```

Validate IPv4 and append `/32`. If detection fails, require `LOGBENCH_SSH_CIDR`.

- [ ] **Step 3: Implement APIM and Bicep deployment**

Enable APIM system MI only when absent and re-read its principal ID. Generate an SSH key only when the configured key path is absent. Create the tagged RG, run Bicep, assign/update API `logbench-v4`, operation, API-scoped subscription, AI/EH loggers, and API diagnostic using `az rest`. Retry EH logger creation until RBAC propagates.

Write `.env.logbench-v4.tmp`, verify every required value, `chmod 600`, then atomically rename it.

- [ ] **Step 4: Implement `configure-condition.sh`**

Generate policy XML that:

- checks VM source IP
- validates and echoes `x-logbench-request-id`
- reads body once with `preserveContent: true`
- calls `log-to-eventhub` only for E8/E64
- returns condition and policy hash headers

Set API diagnostic body bytes to 8192 only for A8 and 0 otherwise. Probe until response headers match condition/hash.

- [ ] **Step 5: Implement safe teardown**

Load env, verify RG tag `managed-by=lab13-v4`, and run only:

```bash
az group delete --name "$LOGBENCH_RG" --yes --no-wait
```

Do not alter APIM objects or MI.

- [ ] **Step 6: Validate scripts**

Run:

```bash
bash -n scripts/logbench-v4/*.sh
! grep -RE 'az apim delete|deletedservice purge|az group delete.*APIM' scripts/logbench-v4
grep -q 'managed-by=lab13-v4' scripts/logbench-v4/teardown.sh
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/logbench-v4
git commit -m "feat(lab13): add safe APIM benchmark deployment" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Add the 15-run orchestrator and documentation

**Files:**
- Create: `scripts/logbench-v4/run-experiment.sh`
- Create: `scripts/logbench-v4/download-results.sh`
- Create: `labs/lab13-logging-perf-benchmark/README.md`

**Interfaces:**
- `run-experiment.sh [--smoke] [--resume] [--condition ID] [--repeat N]`
- Local results: `labs/lab13-logging-perf-benchmark/results/<run-id>/`.

- [ ] **Step 1: Implement the balanced run matrix**

Use this deterministic three-block order:

```text
8KB: N8 A8 E8 | E8 A8 N8 | A8 N8 E8
64KB: N64 E64 | E64 N64 | N64 E64
```

Write it to `experiment-manifest.json` before execution. Skip a run only when its downloaded manifest says `valid: true`.

- [ ] **Step 2: Implement run orchestration**

For each run:

1. call `configure-condition.sh`
2. SSH to invoke VM `run.sh`
3. SCP the run directory locally
4. query APIM CPU and request metrics for the exact UTC window
5. merge metric JSON into the run directory
6. fail the overall command on an invalid run but preserve resume state

`--smoke` uses 1 RPS, 10 seconds, and N8/A8/E8 once.

- [ ] **Step 3: Implement result download**

`download-results.sh` accepts an optional run ID and uses `scp` with the env key/user/host. Never overwrite an existing local run directory unless `--force` is passed.

- [ ] **Step 4: Write README**

Document:

- prerequisites and required APIM inputs
- cost warning for 40 TU and D8as v5
- deploy, smoke, full run, resume, download, teardown commands
- explicit statement that teardown never deletes APIM
- portal checks after RG deletion
- result directory contents and validity rules

- [ ] **Step 5: Validate**

Run:

```bash
bash -n scripts/logbench-v4/*.sh
grep -q 'N8 A8 E8' scripts/logbench-v4/run-experiment.sh
grep -q 'E64 N64' scripts/logbench-v4/run-experiment.sh
grep -q 'APIM.*삭제하지' labs/lab13-logging-perf-benchmark/README.md
git diff --check
```

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/logbench-v4 labs/lab13-logging-perf-benchmark/README.md
git commit -m "feat(lab13): orchestrate benchmark runs" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Final non-destructive validation

**Files:**
- Verify all files from Tasks 1-5.

- [ ] **Step 1: Run local tests**

```bash
cd labs/lab13-logging-perf-benchmark/runner
node tests/test_payload.mjs
python3 -m unittest discover -s tests -v
python3 -m py_compile collector.py consume.py reconcile.py
```

Expected: all pass.

- [ ] **Step 2: Run syntax and IaC validation**

```bash
cd "$(git rev-parse --show-toplevel)"
bash -n scripts/logbench-v4/*.sh labs/lab13-logging-perf-benchmark/runner/*.sh
az bicep build --file infra/logbench-v4.bicep
git diff --check
```

Expected: exit 0.

- [ ] **Step 3: Run destructive-scope audit**

```bash
! grep -RE 'az apim delete|deletedservice purge' \
  scripts/logbench-v4 labs/lab13-logging-perf-benchmark/runner
grep -q 'assert_managed_rg' scripts/logbench-v4/teardown.sh
```

Expected: exit 0.

- [ ] **Step 4: Validate Azure plan without applying**

With `.env.logbench-v4` inputs or explicit environment values loaded, run:

```bash
az group create \
  --name "$LOGBENCH_RG" \
  --location "$LOGBENCH_LOCATION" \
  --tags managed-by=lab13-v4 \
  --output none
az deployment group what-if \
  --resource-group "$LOGBENCH_RG" \
  --template-file infra/logbench-v4.bicep \
  --parameters \
    suffix="$LOGBENCH_SUFFIX" \
    adminUsername="$LOGBENCH_VM_USER" \
    sshPublicKey="$(cat "$LOGBENCH_SSH_PUBLIC_KEY_PATH")" \
    sshSourceCidr="$LOGBENCH_SSH_CIDR" \
    apimPrincipalId="$LOGBENCH_APIM_PRINCIPAL_ID"
```

Expected: the change set contains only resources in the disposable RG and role assignments scoped to its Event Hubs namespace. It contains no `Microsoft.ApiManagement/service` deletion or replacement. If Azure credentials or required environment values are unavailable, skip this step and record the exact reason.

- [ ] **Step 5: Record validation**

Add a `Validation` section to the Lab 13 README with commands, timestamp, and whether Azure what-if was run or skipped due to credentials. Do not claim live validation when it was skipped.

- [ ] **Step 6: Commit validation record**

```bash
git add labs/lab13-logging-perf-benchmark/README.md
git commit -m "docs(lab13): record benchmark validation" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
