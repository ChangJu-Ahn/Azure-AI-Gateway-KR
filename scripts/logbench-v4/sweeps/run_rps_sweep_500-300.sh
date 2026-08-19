#!/usr/bin/env bash
set -uo pipefail
cd "/Users/changjuahn/Repo/AI Gateway"
source .env.logbench-v4
URL="https://${LOGBENCH_APIM_NAME}.azure-api.net/logbench-v4/echo"
NSG="nsg-logbench-${LOGBENCH_SUFFIX}"
SSH="ssh -o ConnectTimeout=15 -o BatchMode=yes -i $LOGBENCH_SSH_KEY ${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}"
WINLOG="labs/lab13-logging-perf-benchmark/results/rps-sweep-windows.txt"
echo "run,condition,rps,startUtc,endUtc" > "$WINLOG"

ensure_rule() {
  local ip; ip=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null)
  [ -n "$ip" ] && az network nsg rule create -g "$LOGBENCH_RG" --nsg-name "$NSG" --name AllowSshFromCaller --priority 100 --access Allow --direction Inbound --protocol Tcp --source-address-prefixes "${ip}/32" --destination-port-ranges 22 -o none 2>/dev/null || true
}

for RPS in 400 300; do
  for COND in N8 A8 E8; do
    RUN="r${RPS}-${COND}"
    echo "=== $RUN 시작 $(date -u +%H:%M:%SZ) ==="
    ensure_rule
    ./scripts/logbench-v4/configure-condition.sh "$COND" >/dev/null 2>&1
    sleep 15
    $SSH "cd ~/logbench && nohup ./.venv/bin/python benchmark.py --url '$URL' --condition '$COND' --run-id '$RUN' --output ~/logbench/results/$RUN --payload-bytes 8192 --rate $RPS --concurrency 20 --warmup-seconds 60 --duration 180 > ~/logbench/$RUN.log 2>&1 & echo started"
    # warmup 60 + measure 180 = 240s, poll up to 6min
    for i in $(seq 1 14); do
      sleep 30
      R=$($SSH "test -f ~/logbench/results/$RUN/result.json && echo DONE || (pgrep -f $RUN >/dev/null && echo RUN || echo DEAD)" 2>/dev/null)
      [ "$R" = "DONE" ] && break
      [ "$R" = "DEAD" ] && { echo "  $RUN DEAD"; break; }
    done
    ensure_rule
    scp -o ConnectTimeout=15 -q -i "$LOGBENCH_SSH_KEY" -r "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}:~/logbench/results/$RUN" labs/lab13-logging-perf-benchmark/results/ 2>/dev/null
    S=$(python3 -c "import json;print(json.load(open('labs/lab13-logging-perf-benchmark/results/$RUN/result.json'))['measureStartUtc'])" 2>/dev/null)
    E=$(python3 -c "import json;print(json.load(open('labs/lab13-logging-perf-benchmark/results/$RUN/result.json'))['measureEndUtc'])" 2>/dev/null)
    SU=$(python3 -c "import json;d=json.load(open('labs/lab13-logging-perf-benchmark/results/$RUN/result.json'));print(d['successful'],d['errors'])" 2>/dev/null)
    echo "$RUN,$COND,$RPS,$S,$E" >> "$WINLOG"
    echo "  $RUN 완료: success/err=$SU  window=$S~$E"
  done
done
echo "=== RPS sweep 완료 ==="
cat "$WINLOG"
