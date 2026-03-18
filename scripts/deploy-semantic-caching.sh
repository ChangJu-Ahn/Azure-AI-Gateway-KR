#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 시맨틱 캐싱 추가 배포 스크립트
# 임베딩 모델(Azure OpenAI) + Azure Redis Cache + APIM 외부 캐시 연결
#
# 사전 조건: deploy.sh로 기본 인프라가 배포되어 있어야 합니다.
# ═══════════════════════════════════════════════════════════════

# .env에서 환경 변수 로드
if [ -f ".env" ]; then
    set -a; source .env 2>/dev/null; set +a
fi

# suffix 결정
PARAMS_FILE="infra/parameters/dev.bicepparam"
if [ -n "${1:-}" ]; then
    SUFFIX="$1"
elif [ -f "$PARAMS_FILE" ]; then
    SUFFIX=$(grep "param suffix" "$PARAMS_FILE" | sed "s/.*= '//;s/'.*//")
else
    echo "❌ suffix를 결정할 수 없습니다."
    echo "   사용법: ./scripts/deploy-semantic-caching.sh <suffix>"
    exit 1
fi

RESOURCE_GROUP="rg-ai-gw-${SUFFIX}"

# 리소스 그룹 존재 여부 확인
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "❌ 리소스 그룹 '${RESOURCE_GROUP}'이 없습니다."
    echo "   먼저 ./scripts/deploy.sh를 실행하세요."
    exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo " 시맨틱 캐싱 배포"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  리소스 그룹: ${RESOURCE_GROUP}"
echo "  접미사:      ${SUFFIX}"
echo ""
echo "  배포할 리소스:"
echo "    • Azure OpenAI (임베딩 모델: text-embedding-3-small)"
echo "    • Azure Cache for Redis"
echo "    • APIM 외부 캐시 연결 + 임베딩 백엔드 등록"
echo ""

# 배포
echo "🚀 시맨틱 캐싱 인프라 배포 시작..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file infra/semantic-caching.bicep \
    --parameters suffix="$SUFFIX" \
    --name semantic-caching-deployment \
    --output table

echo ""
echo "✅ 시맨틱 캐싱 배포 완료!"

# 결과 출력
EMBEDDING_ENDPOINT=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name semantic-caching-deployment \
    --query 'properties.outputs.embeddingEndpoint.value' \
    --output tsv 2>/dev/null || echo "")

REDIS_HOST=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name semantic-caching-deployment \
    --query 'properties.outputs.redisHostName.value' \
    --output tsv 2>/dev/null || echo "")

echo ""
echo "  임베딩 엔드포인트: ${EMBEDDING_ENDPOINT}"
echo "  Redis Host:        ${REDIS_HOST}"
echo ""
echo "📋 APIM 정책에 시맨틱 캐싱이 자동 적용됩니다:"
echo "   Inbound:  azure-openai-semantic-cache-lookup (score-threshold=0.8)"
echo "   Outbound: azure-openai-semantic-cache-store (duration=3600)"
