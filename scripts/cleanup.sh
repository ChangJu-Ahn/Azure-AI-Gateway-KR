#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Azure AI Gateway 리소스 정리 (Clean Up)
# 리소스 그룹 전체를 삭제하여 모든 리소스를 한 번에 정리합니다.
# ═══════════════════════════════════════════════════════════════

# .env에서 리소스 그룹 이름 읽기, 없으면 인자로 받기
if [ -f ".env" ]; then
    set -a; source .env 2>/dev/null; set +a
fi

if [ -z "${RESOURCE_GROUP:-}" ]; then
    SUFFIX="${1:?Usage: ./scripts/cleanup.sh <suffix>  (예: cja0316)}"
    RESOURCE_GROUP="rg-ai-gw-${SUFFIX}"
fi

echo "═══════════════════════════════════════════════════════"
echo " Azure AI Gateway 리소스 정리"
echo "═══════════════════════════════════════════════════════"
echo ""

# 리소스 그룹 존재 여부 확인
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "ℹ️  리소스 그룹 '${RESOURCE_GROUP}'이 존재하지 않습니다."
    exit 0
fi

# 리소스 그룹 내 리소스 목록 출력
echo "📋 삭제될 리소스 목록:"
az resource list --resource-group "$RESOURCE_GROUP" --output table
echo ""

# 삭제 확인
read -p "⚠️  리소스 그룹 '${RESOURCE_GROUP}'의 모든 리소스를 삭제합니다. 계속하시겠습니까? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "❌ 취소되었습니다."
    exit 0
fi

echo ""
echo "🗑️  리소스 그룹 삭제 중... (백그라운드 실행)"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo ""
echo "✅ 삭제 요청이 전송되었습니다."
echo "   리소스 그룹이 완전히 삭제되기까지 수 분이 소요될 수 있습니다."
echo ""
echo "   삭제 상태 확인:"
echo "   az group show --name ${RESOURCE_GROUP} --query 'properties.provisioningState' 2>/dev/null || echo '삭제 완료'"
echo ""

# Soft Delete 리소스 purge 안내
echo "═══════════════════════════════════════════════════════"
echo " ⚠️  Soft Delete 리소스 정리"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Azure OpenAI와 APIM은 삭제 후 30일간 soft delete 상태로 남습니다."
echo "같은 이름으로 재배포하려면 purge가 필요합니다."
echo ""

# Azure OpenAI soft delete 확인 및 purge
echo "📋 Soft-deleted OpenAI 리소스 확인 중..."
DELETED_OPENAI=$(az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o tsv 2>/dev/null || echo "")

if [ -n "$DELETED_OPENAI" ]; then
    echo ""
    az cognitiveservices account list-deleted -o table
    echo ""
    read -p "🗑️  위 리소스를 영구 삭제(purge)합니까? (y/N): " PURGE_CONFIRM
    if [[ "$PURGE_CONFIRM" == "y" || "$PURGE_CONFIRM" == "Y" ]]; then
        az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o tsv | while read -r NAME LOCATION; do
            echo "   purge: ${NAME} (${LOCATION})..."
            az cognitiveservices account purge --name "$NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" 2>/dev/null || \
            echo "   ⚠️  ${NAME} purge 실패 (다른 리소스 그룹이거나 이미 삭제됨)"
        done
        echo "✅ OpenAI soft delete purge 완료"
    fi
else
    echo "   soft-deleted OpenAI 리소스가 없습니다."
fi

# APIM soft delete 확인
echo ""
echo "📋 Soft-deleted APIM 리소스 확인 중..."
DELETED_APIM=$(az apim deletedservice list --query "[].{name:serviceId, location:location}" -o tsv 2>/dev/null || echo "")

if [ -n "$DELETED_APIM" ]; then
    echo ""
    az apim deletedservice list -o table
    echo ""
    read -p "🗑️  위 APIM을 영구 삭제(purge)합니까? (y/N): " PURGE_APIM_CONFIRM
    if [[ "$PURGE_APIM_CONFIRM" == "y" || "$PURGE_APIM_CONFIRM" == "Y" ]]; then
        az apim deletedservice list --query "[].{name:name, location:location}" -o tsv | while read -r NAME LOCATION; do
            echo "   purge: ${NAME} (${LOCATION})..."
            az apim deletedservice purge --service-name "$NAME" --location "$LOCATION" 2>/dev/null || \
            echo "   ⚠️  ${NAME} purge 실패"
        done
        echo "✅ APIM soft delete purge 완료"
    fi
else
    echo "   soft-deleted APIM 리소스가 없습니다."
fi

echo ""
echo "🎉 정리 완료! 재배포하려면: ./scripts/deploy.sh"
