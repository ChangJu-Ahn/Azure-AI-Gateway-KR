#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/.env.logbench-v4"
RESULTS="$ROOT/labs/lab13-logging-perf-benchmark/results"
mkdir -p "$RESULTS"
URL="https://${LOGBENCH_APIM_NAME}.azure-api.net/logbench-v4/echo"
ORDER=(N8 A8 E8 E8 A8 N8 A8 N8 E8 N64 E64 E64 N64 N64 E64)

for index in "${!ORDER[@]}"; do
  condition="${ORDER[$index]}"
  run_id="$(printf '%02d-%s' "$((index + 1))" "$condition")"
  local_dir="$RESULTS/$run_id"
  [ -f "$local_dir/result.json" ] && continue
  "$ROOT/scripts/logbench-v4/configure-condition.sh" "$condition"
  [[ "$condition" = *64 ]] && bytes=65536 || bytes=8192
  remote_dir="logbench/results/$run_id"
  ssh -i "$LOGBENCH_SSH_KEY" "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}" \
    "mkdir -p '$remote_dir' && ~/logbench/.venv/bin/python ~/logbench/benchmark.py \
      --url '$URL' --condition '$condition' --run-id '$run_id' \
      --output '$remote_dir' --payload-bytes '$bytes' \
      --eventhub-namespace '$LOGBENCH_EH_FQDN' \
      --eventhub-name '$LOGBENCH_EH_NAME' --consumer-group '$LOGBENCH_EH_CONSUMER'"
  mkdir -p "$local_dir"
  scp -i "$LOGBENCH_SSH_KEY" -r \
    "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}:${remote_dir}/." "$local_dir/"
done
echo "All runs complete: $RESULTS"
