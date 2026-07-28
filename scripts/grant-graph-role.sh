#!/bin/bash
set -euo pipefail

# ─── Managed Identity에 Microsoft Graph 앱 역할(App Role) 부여 ───
# Managed Identity는 app-only 신원이므로 위임(Delegated)이 아닌
# 애플리케이션 권한(App Role)을 부여해야 합니다.
# Portal UI로는 불가능하며 Graph appRoleAssignments를 직접 호출합니다.
#
# 사용법:
#   ./scripts/grant-graph-role.sh <PRINCIPAL_ID> <APP_ROLE_NAME>
# 예:
#   ./scripts/grant-graph-role.sh 1111-2222-... User.Read.All
#   ./scripts/grant-graph-role.sh 3333-4444-... Mail.Read

PRINCIPAL_ID="${1:-}"
APP_ROLE_NAME="${2:-}"

if [ -z "$PRINCIPAL_ID" ] || [ -z "$APP_ROLE_NAME" ]; then
    echo "❌ 사용법: ./scripts/grant-graph-role.sh <PRINCIPAL_ID> <APP_ROLE_NAME>"
    echo "   예:   ./scripts/grant-graph-role.sh <mi-principal-id> User.Read.All"
    exit 1
fi

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

echo "=== Graph 앱 역할 부여 ==="
echo "대상 Principal ID: ${PRINCIPAL_ID}"
echo "앱 역할:           ${APP_ROLE_NAME}"
echo ""

# 1. Microsoft Graph 서비스 주체(Service Principal)의 objectId 조회
echo "🔎 Microsoft Graph 서비스 주체 조회..."
GRAPH_SP_ID=$(az ad sp show --id "$GRAPH_APP_ID" --query id -o tsv)
if [ -z "$GRAPH_SP_ID" ]; then
    echo "❌ Microsoft Graph 서비스 주체를 찾을 수 없습니다."
    exit 1
fi

# 2. 앱 역할 이름 → appRole ID 변환
echo "🔎 '${APP_ROLE_NAME}' 앱 역할 ID 조회..."
APP_ROLE_ID=$(az ad sp show --id "$GRAPH_APP_ID" \
    --query "appRoles[?value=='${APP_ROLE_NAME}'].id | [0]" -o tsv)
if [ -z "$APP_ROLE_ID" ] || [ "$APP_ROLE_ID" == "None" ]; then
    echo "❌ '${APP_ROLE_NAME}' 앱 역할을 찾을 수 없습니다. 역할 이름을 확인하세요."
    exit 1
fi
echo "   appRole ID: ${APP_ROLE_ID}"

# 3. 멱등성: 이미 부여되어 있으면 skip
echo "🔎 기존 부여 여부 확인..."
EXISTING=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${PRINCIPAL_ID}/appRoleAssignments" \
    --query "value[?appRoleId=='${APP_ROLE_ID}'] | [0].id" -o tsv 2>/dev/null || true)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
    echo "✅ 이미 '${APP_ROLE_NAME}' 역할이 부여되어 있습니다 (assignment id: ${EXISTING}). 건너뜁니다."
    exit 0
fi

# 4. appRoleAssignment 생성
echo "🚀 '${APP_ROLE_NAME}' 역할 부여 중..."
az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${PRINCIPAL_ID}/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\":\"${PRINCIPAL_ID}\",\"resourceId\":\"${GRAPH_SP_ID}\",\"appRoleId\":\"${APP_ROLE_ID}\"}" \
    --output none

echo "✅ 완료: '${APP_ROLE_NAME}' 역할을 부여했습니다."
echo "⏱️  권한 전파에 수 분이 걸릴 수 있습니다."
