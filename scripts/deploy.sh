#!/bin/bash
set -euo pipefail

# ─── Azure API Management AI Gateway 배포 스크립트 ───

LOCATION="koreacentral"
ENVIRONMENT="${1:-dev}"
PARAMS_FILE="infra/parameters/${ENVIRONMENT}.bicepparam"

# 파라미터 파일 확인
if [ ! -f "$PARAMS_FILE" ]; then
    echo "❌ 파라미터 파일을 찾을 수 없습니다: ${PARAMS_FILE}"
    exit 1
fi

# suffix 결정: 인자 > bicepparam 파일
if [ -n "${2:-}" ]; then
    SUFFIX="$2"
else
    SUFFIX=$(grep "param suffix" "$PARAMS_FILE" | sed "s/.*= '//;s/'.*//")
fi

if [ -z "$SUFFIX" ]; then
    echo "❌ suffix를 결정할 수 없습니다. bicepparam에 suffix가 있거나 두 번째 인자로 전달하세요."
    exit 1
fi

RESOURCE_GROUP="rg-ai-gw-${SUFFIX}"

echo "=== AI Gateway 배포 ==="
echo "환경: ${ENVIRONMENT}"
echo "접미사: ${SUFFIX}"
echo "리소스 그룹: ${RESOURCE_GROUP}"
echo "위치: ${LOCATION}"
echo ""

# 리소스 그룹 생성
echo "📦 리소스 그룹 생성..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

# Bicep 배포
echo "🚀 인프라 배포 시작..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file infra/main.bicep \
    --parameters "$PARAMS_FILE" \
    --parameters suffix="$SUFFIX" \
    --name ai-gateway-deployment \
    --output table

echo ""
echo "✅ 배포 완료!"

# 배포 결과 출력
APIM_URL=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name ai-gateway-deployment \
    --query 'properties.outputs.apimGatewayUrl.value' \
    --output tsv 2>/dev/null || echo "배포 확인 필요")

APIM_NAME=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name ai-gateway-deployment \
    --query 'properties.outputs.apimName.value' \
    --output tsv 2>/dev/null || echo "")

echo "Gateway URL: ${APIM_URL}"
echo "APIM Name:   ${APIM_NAME}"

# .env 생성 (기존 파일이 있으면 백업 후 덮어쓰기)
if [ -f ".env" ]; then
    cp .env ".env.bak.$(date +%Y%m%d%H%M%S)"
    echo "📋 기존 .env를 백업했습니다."
fi
cp .env.sample .env
if [ -n "$APIM_URL" ] && [ "$APIM_URL" != "배포 확인 필요" ]; then
    sed -i.bak "s|https://<apim-name>.azure-api.net|${APIM_URL}|" .env
    rm -f .env.bak
fi
if [ -n "$APIM_NAME" ]; then
    sed -i.bak "s|<apim-name>|${APIM_NAME}|" .env
    rm -f .env.bak
fi
sed -i.bak "s|rg-ai-gw-<suffix>|${RESOURCE_GROUP}|" .env
rm -f .env.bak
echo ""
echo "📝 .env 파일이 생성되었습니다."
echo "   APIM Subscription Key를 입력해주세요:"
echo "   Azure Portal → APIM → Subscriptions → Built-in all-access subscription → Show/hide keys"
