#!/bin/bash
set -euo pipefail

# ─── Lab 13 로깅 성능 벤치마크 — 전용 격리 리소스 배포 ───
# ⚠️ Standard v2 APIM · Event Hub · Load Testing 은 시간당 과금됩니다.
#    측정 후 반드시 scripts/teardown-logbench.sh 로 RG 를 삭제하세요.

LOCATION="${LOGBENCH_LOCATION:-koreacentral}"
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

{
    echo "LOGBENCH_SUFFIX=\"${SUFFIX}\""
    echo "LOGBENCH_RG=\"${RESOURCE_GROUP}\""
    echo "LOGBENCH_LOCATION=\"${LOCATION}\""
    echo "LOGBENCH_APIM_NAME=\"$(get_out apimName)\""
    echo "LOGBENCH_APIM_URL=\"$(get_out apimGatewayUrl)\""
    echo "LOGBENCH_EH_NAMESPACE=\"$(get_out eventHubNamespace)\""
    echo "LOGBENCH_EH_NAME=\"$(get_out eventHubName)\""
    echo "LOGBENCH_LA_CUSTOMER_ID=\"$(get_out logAnalyticsCustomerId)\""
    echo "LOGBENCH_LOADTEST_NAME=\"$(get_out loadTestName)\""
    echo "LOGBENCH_APPINSIGHTS_NAME=\"$(get_out appInsightsName)\""
} > .env.logbench

echo "📝 .env.logbench 생성 완료:"
cat .env.logbench
echo ""
echo "다음: 노트북 labs/lab13-logging-perf-benchmark/benchmark-logging-performance.ipynb 실행"
