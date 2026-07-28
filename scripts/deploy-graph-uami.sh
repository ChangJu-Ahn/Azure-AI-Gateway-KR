#!/bin/bash
set -euo pipefail

# ─── Lab 11 Part 2: 권한별 User-Assigned MI 배포 ───
# 옵션 B(진짜 격리): 권한마다 별도의 UAMI를 만들어 APIM에 연결하고,
# 각 UAMI에 단일 Graph 앱 역할만 부여합니다.
#   uami-graph-users-{suffix} → User.Read.All
#   uami-graph-mail-{suffix}  → Mail.Read
#
# 사용법: ./scripts/deploy-graph-uami.sh [suffix]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUFFIX="${1:-}"

if [ -z "$SUFFIX" ]; then
    if [ -f ".env" ]; then
        RG_FROM_ENV=$(grep "^RESOURCE_GROUP=" .env | sed 's/RESOURCE_GROUP=//' || true)
        SUFFIX=$(echo "$RG_FROM_ENV" | sed 's/rg-ai-gw-//')
    fi
fi

if [ -z "$SUFFIX" ]; then
    echo "❌ suffix를 결정할 수 없습니다."
    echo "   사용법: ./scripts/deploy-graph-uami.sh <suffix>"
    exit 1
fi

RESOURCE_GROUP="rg-ai-gw-${SUFFIX}"
APIM_NAME="apim-ai-gw-${SUFFIX}"
LOCATION="koreacentral"

UAMI_USERS="uami-graph-users-${SUFFIX}"
UAMI_MAIL="uami-graph-mail-${SUFFIX}"

echo "=== Lab 11 Part 2: 권한별 UAMI 배포 ==="
echo "리소스 그룹: ${RESOURCE_GROUP}"
echo "APIM:        ${APIM_NAME}"
echo ""

# 1. UAMI 2개 생성 (이미 있으면 az가 기존 값을 반환 → 멱등)
echo "📦 UAMI 생성: ${UAMI_USERS}"
az identity create --name "$UAMI_USERS" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --output none
echo "📦 UAMI 생성: ${UAMI_MAIL}"
az identity create --name "$UAMI_MAIL" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --output none

# 2. 식별자 조회
USERS_PRINCIPAL_ID=$(az identity show --name "$UAMI_USERS" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
USERS_CLIENT_ID=$(az identity show --name "$UAMI_USERS" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
USERS_RES_ID=$(az identity show --name "$UAMI_USERS" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
MAIL_PRINCIPAL_ID=$(az identity show --name "$UAMI_MAIL" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
MAIL_CLIENT_ID=$(az identity show --name "$UAMI_MAIL" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
MAIL_RES_ID=$(az identity show --name "$UAMI_MAIL" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

# 3. APIM에 UAMI attach
echo "🔗 APIM에 UAMI 연결..."
az apim update --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" \
    --set "identity.type=SystemAssigned,UserAssigned" \
    --output none
az resource update \
    --ids "$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)" \
    --set "identity.userAssignedIdentities.{\"${USERS_RES_ID}\":{},\"${MAIL_RES_ID}\":{}}" \
    --output none

# 4. 각 UAMI에 단일 Graph 앱 역할 부여 (grant-graph-role.sh 재사용)
echo "🔐 역할 부여: ${UAMI_USERS} → User.Read.All"
"${SCRIPT_DIR}/grant-graph-role.sh" "$USERS_PRINCIPAL_ID" "User.Read.All"
echo "🔐 역할 부여: ${UAMI_MAIL} → Mail.Read"
"${SCRIPT_DIR}/grant-graph-role.sh" "$MAIL_PRINCIPAL_ID" "Mail.Read"

# 5. clientId를 APIM Named Value로 등록 (정책에서 참조)
echo "📝 APIM Named Value 등록..."
az apim nv create --service-name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" \
    --named-value-id "uami-graph-users-client-id" --display-name "uami-graph-users-client-id" \
    --value "$USERS_CLIENT_ID" --output none 2>/dev/null || \
az apim nv update --service-name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" \
    --named-value-id "uami-graph-users-client-id" --value "$USERS_CLIENT_ID" --output none
az apim nv create --service-name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" \
    --named-value-id "uami-graph-mail-client-id" --display-name "uami-graph-mail-client-id" \
    --value "$MAIL_CLIENT_ID" --output none 2>/dev/null || \
az apim nv update --service-name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" \
    --named-value-id "uami-graph-mail-client-id" --value "$MAIL_CLIENT_ID" --output none

echo ""
echo "✅ 완료!"
echo "   ${UAMI_USERS} clientId: ${USERS_CLIENT_ID}"
echo "   ${UAMI_MAIL}  clientId: ${MAIL_CLIENT_ID}"
echo ""
echo "다음: APIM Microsoft Graph API 정책을 Part 2 버전으로 교체하세요 (README 참고)."
