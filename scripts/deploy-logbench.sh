#!/bin/bash
set -euo pipefail

# ─── Lab 13 로깅 성능 벤치마크 — 전용 격리 리소스 배포 ───
# ⚠️ Standard v2 APIM · Event Hub · Load Testing 은 시간당 과금됩니다.
#    측정 후 반드시 scripts/teardown-logbench.sh 로 RG 를 삭제하세요.

# Azure Load Testing 은 koreacentral 미지원 → 기본값은 APIM v2·Load Testing 모두 지원하는 japaneast.
LOCATION="${LOGBENCH_LOCATION:-japaneast}"
PUBLISHER_EMAIL="${LOGBENCH_PUBLISHER_EMAIL:-admin@example.com}"

if [ "${ACK_STANDARD_V2_COST:-false}" != "true" ]; then
    echo "❌ 비용 확인이 필요합니다."
    echo "   이 랩은 Standard v2 APIM + Event Hub + Load Testing 을 배포하며 시간당 과금됩니다."
    echo "   동의하면 다음처럼 실행하세요:"
    echo "     ACK_STANDARD_V2_COST=true ./scripts/deploy-logbench.sh [suffix]"
    exit 1
fi

if [ -n "${1:-}" ]; then
    SUFFIX="$1"
else
    SUFFIX="logbench-$(date +%Y%m%d)"
fi

RESOURCE_GROUP="rg-ai-gw-logbench-${SUFFIX}"

echo "=== Lab 13 LogBench 배포 ==="
echo "접미사: ${SUFFIX}"
echo "리소스 그룹: ${RESOURCE_GROUP}"
echo "위치: ${LOCATION}"
echo ""
echo "⏱️  Standard v2 는 보통 몇 분 내 배포됩니다(편차 가능)."
echo ""

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file infra/logbench.bicep \
    --parameters suffix="$SUFFIX" publisherEmail="$PUBLISHER_EMAIL" \
    --name logbench-deployment \
    --output table

echo ""
echo "✅ 배포 완료! 출력값을 .env.logbench 에 기록합니다."

get_out() {
    az deployment group show --resource-group "$RESOURCE_GROUP" --name logbench-deployment \
        --query "properties.outputs.${1}.value" -o tsv 2>/dev/null || echo ""
}

APIM_NAME_OUT="$(get_out apimName)"
APIM_URL_OUT="$(get_out apimGatewayUrl)"
# StandardV2 는 apimGatewayUrl 출력이 비어올 수 있어 관례 호스트명으로 보정한다.
if [ -z "$APIM_URL_OUT" ] && [ -n "$APIM_NAME_OUT" ]; then
    APIM_URL_OUT="https://${APIM_NAME_OUT}.azure-api.net"
fi
EH_NS_OUT="$(get_out eventHubNamespace)"
EH_NM_OUT="$(get_out eventHubName)"

{
    echo "LOGBENCH_SUFFIX=\"${SUFFIX}\""
    echo "LOGBENCH_RG=\"${RESOURCE_GROUP}\""
    echo "LOGBENCH_LOCATION=\"${LOCATION}\""
    echo "LOGBENCH_APIM_NAME=\"${APIM_NAME_OUT}\""
    echo "LOGBENCH_APIM_URL=\"${APIM_URL_OUT}\""
    echo "LOGBENCH_EH_NAMESPACE=\"${EH_NS_OUT}\""
    echo "LOGBENCH_EH_NAME=\"${EH_NM_OUT}\""
    echo "LOGBENCH_LA_CUSTOMER_ID=\"$(get_out logAnalyticsCustomerId)\""
    echo "LOGBENCH_LOADTEST_NAME=\"$(get_out loadTestName)\""
    echo "LOGBENCH_APPINSIGHTS_NAME=\"$(get_out appInsightsName)\""
} > .env.logbench

echo "📝 .env.logbench 생성 완료:"
cat .env.logbench

# ─── 배포 후: Event Hub 로거(logbench-eh)를 Managed Identity 방식으로 등록 ───
# 테넌트가 EH SAS 를 비활성화(disableLocalAuth=true)해도 동작하도록 MI 를 쓴다.
# bicep 이 부여한 "Azure Event Hubs Data Sender" 역할의 RBAC 전파(수십 초)를 기다린 뒤 재시도한다.
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
LOGGER_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME_OUT}/loggers/logbench-eh?api-version=2023-09-01-preview"
LOGGER_BODY="{\"properties\":{\"loggerType\":\"azureEventHub\",\"credentials\":{\"endpointAddress\":\"${EH_NS_OUT}.servicebus.windows.net\",\"identityClientId\":\"systemAssigned\",\"name\":\"${EH_NM_OUT}\"}}}"
echo ""
echo "⏳ Event Hub 로거(MI) 등록 — RBAC 전파 대기 후 재시도..."
sleep 60
LOGGER_OK=false
for i in 1 2 3 4 5; do
    if az rest --method PUT --url "$LOGGER_URL" --headers "Content-Type=application/json" --body "$LOGGER_BODY" -o none 2>/dev/null; then
        echo "  ✅ logbench-eh 로거 등록 완료"; LOGGER_OK=true; break
    fi
    echo "  ...RBAC 전파 대기 (${i}/5) — 45초 후 재시도"; sleep 45
done
[ "$LOGGER_OK" = true ] || echo "  ⚠️ 로거 등록 실패 — 잠시 후 재실행하거나 수동 등록하세요(C3 구성만 영향)."

echo ""
echo "다음: 노트북 labs/lab13-logging-perf-benchmark/benchmark-logging-performance.ipynb 실행"
