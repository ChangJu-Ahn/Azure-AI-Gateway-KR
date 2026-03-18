#!/bin/bash
set -euo pipefail

# ─── 임시 스크립트: APIM에 백엔드 + 백엔드풀 추가 ───
# SKU 변경으로 수동 재생성한 APIM에 누락된 백엔드를 복원합니다.
# 사용 후 이 파일을 삭제하세요.

APIM_ID="/subscriptions/347e0df7-94e9-4feb-b42d-57d7e49566f2/resourceGroups/rg-ai-gw-aigateway-20260317/providers/Microsoft.ApiManagement/service/apim-ai-gw-aigateway-20260317"
API_VER="2023-09-01-preview"

CB_RULES='[{
  "failureCondition": {
    "count": 1,
    "errorReasons": ["Server errors"],
    "interval": "PT1S",
    "statusCodeRanges": [{"min": 429, "max": 429}, {"min": 500, "max": 503}]
  },
  "name": "openAiCircuitBreaker",
  "tripDuration": "PT30S",
  "acceptRetryAfter": false
}]'

create_backend() {
  local name=$1
  local url=$2
  echo "📦 Backend: ${name}..."
  az rest --method PUT \
    --url "https://management.azure.com${APIM_ID}/backends/${name}?api-version=${API_VER}" \
    --body "{
      \"properties\": {
        \"url\": \"${url}\",
        \"protocol\": \"http\",
        \"circuitBreaker\": { \"rules\": ${CB_RULES} }
      }
    }" -o none
  echo "   ✅ ${name} 완료"
}

# ─── 1~3. 백엔드 생성 ───
echo "=== APIM 백엔드 + 백엔드풀 추가 ==="
echo ""

create_backend "aoai-eastus" "https://aoai-eus-aigateway-20260317.openai.azure.com/openai"
create_backend "aoai-swedencentral" "https://aoai-swe-aigateway-20260317.openai.azure.com/openai"
create_backend "aoai-westus" "https://aoai-wus-aigateway-20260317.openai.azure.com/openai"

# ─── 4. 백엔드풀 생성 ───
echo ""
echo "🔗 Backend Pool: openai-backend-pool..."
az rest --method PUT \
  --url "https://management.azure.com${APIM_ID}/backends/openai-backend-pool?api-version=${API_VER}" \
  --body '{
    "properties": {
      "type": "Pool",
      "pool": {
        "services": [
          { "id": "/backends/aoai-eastus", "priority": 1, "weight": 1 },
          { "id": "/backends/aoai-swedencentral", "priority": 1, "weight": 1 },
          { "id": "/backends/aoai-westus", "priority": 1, "weight": 1 }
        ]
      }
    }
  }' -o none
echo "   ✅ openai-backend-pool 완료"

echo ""
echo "============================================"
echo "✅ 백엔드 + 백엔드풀 추가 완료!"
echo "============================================"
echo ""
echo "  aoai-eastus          (priority 1, weight 1)"
echo "  aoai-swedencentral   (priority 1, weight 1)"
echo "  aoai-westus          (priority 1, weight 1)"
echo "  openai-backend-pool  (위 3개 round-robin)"
echo ""
echo "⚠️  이 스크립트는 임시입니다. 완료 후 삭제하세요:"
echo "    rm scripts/tmp-add-backends.sh"
