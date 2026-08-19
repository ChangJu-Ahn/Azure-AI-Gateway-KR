#!/usr/bin/env bash
set -euo pipefail
# Basic v2 APIM 배포 + logbench-v4 API/EH로거/E8 정책 설정 (SKU 비교 실험용)
# 전제: deploy.sh 로 신규 RG(EH/VM) 이미 배포됨 (.env.logbench-v4 존재)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/.env.logbench-v4"
SUB_ID="$(az account show --query id -o tsv)"

echo "=== 1. Basic v2 APIM 배포 (수분 소요) ==="
az deployment group create -g "$LOGBENCH_RG" -n apim-basicv2 \
  --template-file "$ROOT/infra/apim-basicv2.bicep" \
  --parameters suffix="$LOGBENCH_SUFFIX" -o none

V2_NAME=$(az deployment group show -g "$LOGBENCH_RG" -n apim-basicv2 --query "properties.outputs.apimName.value" -o tsv)
V2_PRINCIPAL=$(az deployment group show -g "$LOGBENCH_RG" -n apim-basicv2 --query "properties.outputs.apimPrincipalId.value" -o tsv)
echo "Basic v2: $V2_NAME (principal $V2_PRINCIPAL)"

echo "=== 2. EH Data Sender 역할 부여 ==="
EH_NS_ID=$(az eventhubs namespace show -g "$LOGBENCH_RG" -n "$LOGBENCH_EH_NAMESPACE" --query id -o tsv)
az role assignment create --assignee "$V2_PRINCIPAL" --role "Azure Event Hubs Data Sender" --scope "$EH_NS_ID" -o none 2>/dev/null || true

echo "=== 3. API + operation 생성 ==="
az apim api create -g "$LOGBENCH_RG" --service-name "$V2_NAME" --api-id logbench-v4 \
  --path logbench-v4 --display-name "LogBench v4" --protocols https --subscription-required false -o none
az apim api operation create -g "$LOGBENCH_RG" --service-name "$V2_NAME" \
  --api-id logbench-v4 --operation-id echo --display-name Echo --method POST --url-template /echo -o none

echo "=== 4. EH 로거 생성 (MI, RBAC 전파 재시도) ==="
BASE="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${LOGBENCH_RG}/providers/Microsoft.ApiManagement/service/${V2_NAME}"
EH_BODY="$(jq -n --arg endpoint "${LOGBENCH_EH_NAMESPACE}.servicebus.windows.net" --arg name "$LOGBENCH_EH_NAME" \
  '{properties:{loggerType:"azureEventHub",description:"managed-by=lab13-v4",credentials:{endpointAddress:$endpoint,identityClientId:"systemAssigned",name:$name},isBuffered:true}}')"
for attempt in 1 2 3 4 5; do
  az rest --method PUT --url "${BASE}/loggers/logbench-v4-eh?api-version=2024-05-01" --body "$EH_BODY" -o none 2>/dev/null && break
  echo "  RBAC 전파 대기 ($attempt/5)"; sleep 30
done

echo "=== 5. E8 정책 적용 (VM IP 체크 + body 읽기 + log-to-eventhub) ==="
EH_XML='<log-to-eventhub logger-id="logbench-v4-eh">@((string)context.Variables["body"])</log-to-eventhub>'
POLICY="<policies><inbound><base /><choose><when condition=\"@(context.Request.IpAddress != &quot;${LOGBENCH_VM_IP}&quot;)\"><return-response><set-status code=\"403\" reason=\"Forbidden\" /></return-response></when></choose><set-variable name=\"body\" value=\"@((string)context.Request.Body.As&lt;string&gt;(preserveContent: true))\" />${EH_XML}<return-response><set-status code=\"200\" reason=\"OK\" /><set-header name=\"x-logbench-request-id\" exists-action=\"override\"><value>@(context.Request.Headers.GetValueOrDefault(&quot;x-logbench-request-id&quot;,&quot;&quot;))</value></set-header><set-header name=\"x-logbench-condition\" exists-action=\"override\"><value>E8</value></set-header><set-body>OK</set-body></return-response></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"
jq -n --arg value "$POLICY" '{properties:{format:"rawxml",value:$value}}' \
  | az rest --method PUT --url "${BASE}/apis/logbench-v4/policies/policy?api-version=2024-05-01" --body @- -o none

echo ""
echo "✅ Basic v2 준비 완료. 측정 URL: https://${V2_NAME}.azure-api.net/logbench-v4/echo"
echo "   VM에서 benchmark.py 로 8KB 500 RPS E8 측정 후 EH IncomingMessages 로 드롭 확인."
