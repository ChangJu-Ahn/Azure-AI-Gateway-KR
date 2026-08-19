#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCATION="${LOGBENCH_LOCATION:-japaneast}"
APIM_NAME="${LOGBENCH_APIM_NAME:?Set LOGBENCH_APIM_NAME}"
APIM_RG="${LOGBENCH_APIM_RG:?Set LOGBENCH_APIM_RG}"
SUFFIX="${LOGBENCH_SUFFIX:-$(date +%Y%m%d%H%M)}"
RG="rg-ai-gw-logbench-${SUFFIX}"
VM_USER="${LOGBENCH_VM_USER:-azureuser}"
SSH_KEY="${LOGBENCH_SSH_KEY:-$HOME/.ssh/id_ed25519}"

for command in az jq curl ssh scp ssh-keygen; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done
az account show >/dev/null

SKU="$(az apim show -g "$APIM_RG" -n "$APIM_NAME" --query sku.name -o tsv)"
[ "$SKU" = "Developer" ] || { echo "APIM must use Developer SKU, found: $SKU" >&2; exit 1; }

PRINCIPAL_ID="$(az apim show -g "$APIM_RG" -n "$APIM_NAME" --query identity.principalId -o tsv)"
if [ -z "$PRINCIPAL_ID" ]; then
  az apim update -g "$APIM_RG" -n "$APIM_NAME" --set identity.type=SystemAssigned -o none
  PRINCIPAL_ID="$(az apim show -g "$APIM_RG" -n "$APIM_NAME" --query identity.principalId -o tsv)"
fi
[ -n "$PRINCIPAL_ID" ] || { echo "APIM managed identity was not available" >&2; exit 1; }

if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t ed25519 -N "" -f "$SSH_KEY"
fi
SSH_CIDR="${LOGBENCH_SSH_CIDR:-}"
if [ -z "$SSH_CIDR" ]; then
  IP="$(curl --fail --silent --show-error --max-time 10 https://api.ipify.org || true)"
  [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
    echo "Public IP detection failed; set LOGBENCH_SSH_CIDR" >&2
    exit 1
  }
  SSH_CIDR="${IP}/32"
fi

az group create -n "$RG" -l "$LOCATION" --tags managed-by=lab13-v4 -o none
az deployment group create -g "$RG" -n logbench-v4 \
  --template-file "$ROOT/infra/logbench-v4.bicep" \
  --parameters suffix="$SUFFIX" adminUsername="$VM_USER" \
    sshPublicKey="$(cat "${SSH_KEY}.pub")" sshSourceCidr="$SSH_CIDR" \
    apimPrincipalId="$PRINCIPAL_ID" -o none

out() {
  az deployment group show -g "$RG" -n logbench-v4 --query "properties.outputs.$1.value" -o tsv
}
VM_IP="$(out vmPublicIp)"
EH_NS="$(out eventHubNamespace)"
EH_FQDN="$(out eventHubFqdn)"
EH_NAME="$(out eventHubName)"
EH_CONSUMER="$(out consumerGroup)"
AI_ID="$(out appInsightsId)"
AI_CONNECTION="$(out appInsightsConnectionString)"

az apim api create -g "$APIM_RG" --service-name "$APIM_NAME" --api-id logbench-v4 \
  --path logbench-v4 --display-name "LogBench v4 [managed-by=lab13-v4]" \
  --protocols https --subscription-required false -o none 2>/dev/null || true
az apim api operation create -g "$APIM_RG" --service-name "$APIM_NAME" \
  --api-id logbench-v4 --operation-id echo --display-name Echo \
  --method POST --url-template /echo -o none 2>/dev/null || true

SUB_ID="$(az account show --query id -o tsv)"
BASE="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${APIM_RG}/providers/Microsoft.ApiManagement/service/${APIM_NAME}"
AI_LOGGER="${BASE}/loggers/logbench-v4-ai"
EH_LOGGER="${BASE}/loggers/logbench-v4-eh"

jq -n --arg connection "$AI_CONNECTION" --arg resource "$AI_ID" \
  '{properties:{loggerType:"applicationInsights",description:"managed-by=lab13-v4",credentials:{connectionString:$connection},isBuffered:true,resourceId:$resource}}' \
  | az rest --method PUT --url "${AI_LOGGER}?api-version=2024-05-01" --body @- -o none

EH_BODY="$(jq -n --arg endpoint "${EH_NS}.servicebus.windows.net" --arg name "$EH_NAME" \
  '{properties:{loggerType:"azureEventHub",description:"managed-by=lab13-v4",credentials:{endpointAddress:$endpoint,identityClientId:"systemAssigned",name:$name},isBuffered:true}}')"
for attempt in 1 2 3 4 5; do
  if az rest --method PUT --url "${EH_LOGGER}?api-version=2024-05-01" --body "$EH_BODY" -o none 2>/dev/null; then
    break
  fi
  [ "$attempt" -lt 5 ] || { echo "Event Hub logger creation failed" >&2; exit 1; }
  sleep 30
done

cat > "$ROOT/.env.logbench-v4.tmp" <<EOF
LOGBENCH_RG="$RG"
LOGBENCH_LOCATION="$LOCATION"
LOGBENCH_SUFFIX="$SUFFIX"
LOGBENCH_APIM_NAME="$APIM_NAME"
LOGBENCH_APIM_RG="$APIM_RG"
LOGBENCH_APIM_PRINCIPAL_ID="$PRINCIPAL_ID"
LOGBENCH_VM_IP="$VM_IP"
LOGBENCH_VM_USER="$VM_USER"
LOGBENCH_SSH_KEY="$SSH_KEY"
LOGBENCH_EH_NAMESPACE="$EH_NS"
LOGBENCH_EH_FQDN="$EH_FQDN"
LOGBENCH_EH_NAME="$EH_NAME"
LOGBENCH_EH_CONSUMER="$EH_CONSUMER"
EOF
chmod 600 "$ROOT/.env.logbench-v4.tmp"
mv "$ROOT/.env.logbench-v4.tmp" "$ROOT/.env.logbench-v4"

ssh -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" "${VM_USER}@${VM_IP}" \
  "sudo apt-get update -qq && sudo apt-get install -y python3-venv >/dev/null && mkdir -p ~/logbench"
scp -i "$SSH_KEY" "$ROOT/labs/lab13-logging-perf-benchmark/runner/benchmark.py" \
  "${VM_USER}@${VM_IP}:logbench/"
ssh -i "$SSH_KEY" "${VM_USER}@${VM_IP}" \
  "python3 -m venv ~/logbench/.venv && ~/logbench/.venv/bin/pip install -q aiohttp azure-identity azure-eventhub"

"$ROOT/scripts/logbench-v4/configure-condition.sh" N8
echo "Deployment complete. APIM was preserved; disposable RG: $RG"
