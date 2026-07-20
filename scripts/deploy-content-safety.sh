#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Content Safety 커스텀 컨텐츠 필터링 — 독립(증분) 배포 스크립트
# Content Safety 계정 + korea-pii RAI 블록리스트 + APIM 백엔드/역할만 배포합니다.
# (APIM을 재생성하지 않으므로 몇 분 내에 완료됩니다.)
#
# 사전 조건: deploy.sh로 기본 인프라(APIM)가 배포되어 있어야 합니다.
# 사용법: ./scripts/deploy-content-safety.sh [suffix] [contentSafetyLocation]
# ═══════════════════════════════════════════════════════════════

# .env에서 환경 변수 로드
if [ -f ".env" ]; then
    set -a; source .env 2>/dev/null; set +a
fi

# suffix 결정: 인자 > .env의 RESOURCE_GROUP에서 추출
if [ -n "${1:-}" ]; then
    SUFFIX="$1"
elif [ -n "${RESOURCE_GROUP:-}" ]; then
    SUFFIX="${RESOURCE_GROUP#rg-ai-gw-}"
else
    echo "❌ suffix를 결정할 수 없습니다."
    echo "   먼저 ./scripts/deploy.sh를 실행하거나 suffix를 인자로 전달하세요:"
    echo "   사용법: ./scripts/deploy-content-safety.sh <suffix> [contentSafetyLocation]"
    exit 1
fi

CS_LOCATION="${2:-eastus}"
RESOURCE_GROUP="rg-ai-gw-${SUFFIX}"

# 리소스 그룹 존재 여부 확인
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "❌ 리소스 그룹 '${RESOURCE_GROUP}'이 없습니다."
    echo "   먼저 ./scripts/deploy.sh를 실행하세요."
    exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo " Content Safety 커스텀 컨텐츠 필터링 배포"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  리소스 그룹:      ${RESOURCE_GROUP}"
echo "  접미사:           ${SUFFIX}"
echo "  Content Safety 리전: ${CS_LOCATION}"
echo ""
echo "  배포할 리소스:"
echo "    • Azure AI Content Safety (acs-${SUFFIX})"
echo "    • RAI 블록리스트 korea-pii (주민번호/휴대폰/주소 정규식)"
echo "    • APIM content-safety-backend (Managed Identity)"
echo "    • APIM MI → Cognitive Services User 역할"
echo ""

# 배포 (증분: 기존 APIM은 그대로, Content Safety 관련만 추가)
echo "🚀 Content Safety 배포 시작... (몇 분 소요)"
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file infra/content-safety.bicep \
    --parameters suffix="$SUFFIX" contentSafetyLocation="$CS_LOCATION" \
    --name content-safety-deployment \
    --output table

echo ""
echo "✅ Content Safety 배포 완료!"

# 결과 출력
CS_NAME=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name content-safety-deployment \
    --query 'properties.outputs.contentSafetyName.value' \
    --output tsv 2>/dev/null || echo "")

CS_ENDPOINT=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name content-safety-deployment \
    --query 'properties.outputs.contentSafetyEndpoint.value' \
    --output tsv 2>/dev/null || echo "")

echo ""
echo "  Content Safety: ${CS_NAME}"
echo "  Endpoint:       ${CS_ENDPOINT}"
echo ""
echo "📋 다음 단계:"
echo "   labs/lab07-advanced-patterns/test-content-safety-pii.ipynb 노트북을 실행하여"
echo "   llm-content-safety 정책 적용 및 한국형 PII 차단을 검증하세요."
echo ""
echo "   ⚠️ RAI 블록리스트 항목은 반영까지 최대 ~5분이 걸릴 수 있습니다."
