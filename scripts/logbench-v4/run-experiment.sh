#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/.env.logbench-v4"
RESULTS="$ROOT/labs/lab13-logging-perf-benchmark/results"
mkdir -p "$RESULTS"
URL="https://${LOGBENCH_APIM_NAME}.azure-api.net/logbench-v4/echo"

RATE="${LOGBENCH_RATE:-500}"
CONCURRENCY="${LOGBENCH_CONCURRENCY:-20}"
WARMUP="${LOGBENCH_WARMUP:-120}"
DURATION="${LOGBENCH_DURATION:-300}"
NSG="nsg-logbench-${LOGBENCH_SUFFIX}"
ORDER=(N8 A8 E8 E8 A8 N8 A8 N8 E8 N64 E64 E64 N64 N64 E64)

APIM_ID="$(az apim show -g "$LOGBENCH_APIM_RG" -n "$LOGBENCH_APIM_NAME" --query id -o tsv)"

# 구독 거버넌스가 NSG 인바운드 규칙을 제거할 수 있어, 매 런 전에 idempotent 재적용한다.
ensure_ssh_rule() {
  local ip
  ip="$(curl --fail --silent --max-time 10 https://api.ipify.org || echo "")"
  [ -n "$ip" ] || ip="${LOGBENCH_SSH_CIDR%%/*}"
  az network nsg rule create -g "$LOGBENCH_RG" --nsg-name "$NSG" \
    --name AllowSshFromCaller --priority 100 --access Allow --direction Inbound \
    --protocol Tcp --source-address-prefixes "${ip}/32" --destination-port-ranges 22 \
    -o none 2>/dev/null || true
}

ssh_retry() {
  # SSH with a few retries; re-apply NSG rule if it fails (rule may have been wiped)
  local tries=0
  while [ "$tries" -lt 4 ]; do
    if ssh -o ConnectTimeout=15 -o BatchMode=yes -i "$LOGBENCH_SSH_KEY" \
         "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}" "$@"; then
      return 0
    fi
    tries=$((tries + 1))
    echo "  ssh failed (try $tries), re-applying NSG rule + wait 15s" >&2
    ensure_ssh_rule
    sleep 15
  done
  return 1
}

collect_apim_metrics() {
  local start="$1" end="$2" out="$3"
  az monitor metrics list --resource "$APIM_ID" \
    --metric Capacity Duration --aggregation Average Maximum \
    --start-time "$start" --end-time "$end" --interval PT1M \
    --query "value[].{metric:name.value, points:timeseries[0].data[?average!=null || maximum!=null]}" \
    -o json > "$out" 2>/dev/null || echo '{"error":"metric query failed"}' > "$out"
}

for index in "${!ORDER[@]}"; do
  condition="${ORDER[$index]}"
  run_id="$(printf '%02d-%s' "$((index + 1))" "$condition")"
  local_dir="$RESULTS/$run_id"
  [ -f "$local_dir/result.json" ] && { echo "skip $run_id (already done)"; continue; }

  echo "=== run $run_id ($condition) ==="
  ensure_ssh_rule
  "$ROOT/scripts/logbench-v4/configure-condition.sh" "$condition" >/dev/null
  sleep 20
  [[ "$condition" = *64 ]] && bytes=65536 || bytes=8192
  remote_dir="logbench/results/$run_id"

  # 런처가 측정 창을 직접 기록(VM 코드 버전과 무관하게 서버측 메트릭 귀속 보장).
  run_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ssh_retry "mkdir -p '$remote_dir' && ~/logbench/.venv/bin/python ~/logbench/benchmark.py \
      --url '$URL' --condition '$condition' --run-id '$run_id' \
      --output '$remote_dir' --payload-bytes '$bytes' \
      --rate '$RATE' --concurrency '$CONCURRENCY' \
      --warmup-seconds '$WARMUP' --duration '$DURATION' \
      --eventhub-namespace '$LOGBENCH_EH_FQDN' \
      --eventhub-name '$LOGBENCH_EH_NAME' --consumer-group '$LOGBENCH_EH_CONSUMER'" \
    || { echo "  RUN FAILED: $run_id (ssh unrecoverable)"; continue; }
  run_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$local_dir"
  ensure_ssh_rule
  scp -o ConnectTimeout=15 -q -i "$LOGBENCH_SSH_KEY" -r \
    "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}:${remote_dir}/." "$local_dir/" \
    || echo "  WARN: scp failed for $run_id"
  echo "{\"runStartUtc\":\"$run_start\",\"runEndUtc\":\"$run_end\"}" > "$local_dir/run-window.json"

  sleep 90
  collect_apim_metrics "$run_start" "$run_end" "$local_dir/apim-metrics.json"
  echo "  saved: $local_dir"
done

echo "All runs complete: $RESULTS"
