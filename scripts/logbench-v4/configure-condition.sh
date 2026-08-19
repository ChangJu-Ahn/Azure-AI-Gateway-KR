#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/.env.logbench-v4"
CONDITION="${1:?Condition required: N8|A8|E8|N64|E64}"
case "$CONDITION" in
  N8|A8|E8) BYTES=8192 ;;
  N64|E64) BYTES=65536 ;;
  *) echo "Invalid condition: $CONDITION" >&2; exit 1 ;;
esac
BODY_BYTES=0
[ "$CONDITION" = A8 ] && BODY_BYTES=8192
EH_XML=""
if [[ "$CONDITION" = E* ]]; then
  EH_XML='<log-to-eventhub logger-id="logbench-v4-eh">@((string)context.Variables["body"])</log-to-eventhub>'
fi

SUB_ID="$(az account show --query id -o tsv)"
BASE="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${LOGBENCH_APIM_RG}/providers/Microsoft.ApiManagement/service/${LOGBENCH_APIM_NAME}"
POLICY="<policies><inbound><base /><choose><when condition=\"@(context.Request.IpAddress != &quot;${LOGBENCH_VM_IP}&quot;)\"><return-response><set-status code=\"403\" reason=\"Forbidden\" /></return-response></when></choose><set-variable name=\"body\" value=\"@((string)context.Request.Body.As&lt;string&gt;(preserveContent: true))\" />${EH_XML}<return-response><set-status code=\"200\" reason=\"OK\" /><set-header name=\"x-logbench-request-id\" exists-action=\"override\"><value>@(context.Request.Headers.GetValueOrDefault(&quot;x-logbench-request-id&quot;,&quot;&quot;))</value></set-header><set-header name=\"x-logbench-condition\" exists-action=\"override\"><value>${CONDITION}</value></set-header><set-body>OK</set-body></return-response></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"

jq -n --arg value "$POLICY" '{properties:{format:"rawxml",value:$value}}' \
  | az rest --method PUT --url "${BASE}/apis/logbench-v4/policies/policy?api-version=2024-05-01" --body @- -o none

LOGGER_ID="${BASE}/loggers/logbench-v4-ai"
jq -n --arg logger "$LOGGER_ID" --argjson bytes "$BODY_BYTES" \
  '{properties:{loggerId:$logger,sampling:{samplingType:"fixed",percentage:100},alwaysLog:"allErrors",frontend:{request:{headers:[],body:{bytes:$bytes}},response:{headers:[],body:{bytes:0}}},backend:{request:{headers:[],body:{bytes:0}},response:{headers:[],body:{bytes:0}}}}}' \
  | az rest --method PUT --url "${BASE}/apis/logbench-v4/diagnostics/applicationinsights?api-version=2024-05-01" --body @- -o none

echo "$CONDITION configured (${BYTES} bytes)"
