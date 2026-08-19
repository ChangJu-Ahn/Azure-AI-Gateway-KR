#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/.env.logbench-v4"
RESULTS="$ROOT/labs/lab13-logging-perf-benchmark/results"
mkdir -p "$RESULTS"
URL="https://${LOGBENCH_APIM_NAME}.azure-api.net/logbench-v4/echo"

# 부하 파라미터. 부하 생성기 검증: concurrency=20 에서 500 RPS·0 오류·p50 4ms.
RATE="${LOGBENCH_RATE:-500}"
CONCURRENCY="${LOGBENCH_CONCURRENCY:-20}"
WARMUP="${LOGBENCH_WARMUP:-120}"
DURATION="${LOGBENCH_DURATION:-300}"

# 균형 순서: 각 조건이 앞/중간/뒤 위치를 고루 경험.
ORDER=(N8 A8 E8 E8 A8 N8 A8 N8 E8 N64 E64 E64 N64 N64 E64)

APIM_ID="$(az apim show -g "$LOGBENCH_APIM_RG" -n "$LOGBENCH_APIM_NAME" --query id -o tsv)"

collect_apim_metrics() {
  local result="$1" out="$2"
  local start end
  start="$(python3 -c "import json;print(json.load(open('$result'))['summary']['measureStartUtc'])" 2>/dev/null || echo "")"
  end="$(python3 -c "import json;print(json.load(open('$result'))['summary']['measureEndUtc'])" 2>/dev/null || echo "")"
  [ -n "$start" ] && [ -n "$end" ] || { echo '{"error":"no measure window"}' > "$out"; return; }
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
  "$ROOT/scripts/logbench-v4/configure-condition.sh" "$condition" >/dev/null
  sleep 20
  [[ "$condition" = *64 ]] && bytes=65536 || bytes=8192
  remote_dir="logbench/results/$run_id"

  ssh -i "$LOGBENCH_SSH_KEY" "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}" \
    "mkdir -p '$remote_dir' && ~/logbench/.venv/bin/python ~/logbench/benchmark.py \
      --url '$URL' --condition '$condition' --run-id '$run_id' \
      --output '$remote_dir' --payload-bytes '$bytes' \
      --rate '$RATE' --concurrency '$CONCURRENCY' \
      --warmup-seconds '$WARMUP' --duration '$DURATION' \
      --eventhub-namespace '$LOGBENCH_EH_FQDN' \
      --eventhub-name '$LOGBENCH_EH_NAME' --consumer-group '$LOGBENCH_EH_CONSUMER'"

  mkdir -p "$local_dir"
  scp -q -i "$LOGBENCH_SSH_KEY" -r \
    "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}:${remote_dir}/." "$local_dir/"

  sleep 90
  collect_apim_metrics "$local_dir/result.json" "$local_dir/apim-metrics.json"
  echo "  saved: $local_dir"
done

echo "All runs complete: $RESULTS"
