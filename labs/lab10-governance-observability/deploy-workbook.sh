#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy-workbook.sh
#   workbook-template.json → Azure Monitor Workbook(Microsoft.Insights/workbooks) 배포
#
#   하나의 게이트웨이가 여러 구독 × 멀티클라우드(Azure OpenAI · OpenAI · Bedrock ·
#   Anthropic · Gemini)의 토큰·쿼터·요청률·비용·차단·프롬프트를 리포팅하는
#   공유 Workbook 을 App Insights 에 배포합니다. 같은 이름으로 재배포 시 덮어씁니다(멱등).
#
# 사용법:
#   RESOURCE_GROUP=rg-... ./deploy-workbook.sh            # 환경변수
#   ./deploy-workbook.sh rg-...                           # 인자
#   (../../.env 에 RESOURCE_GROUP / APP_INSIGHTS_NAME 을 두면 자동 로드)
#
# 삭제:
#   az rest --method DELETE --url "<위 출력의 workbook resource id>?api-version=2023-06-01"
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

# .env 로드(있으면) — KEY=VALUE 형식
if [ -f ../../.env ]; then set -a; . ../../.env; set +a; fi

RG="${RESOURCE_GROUP:-${1:-}}"
[ -z "$RG" ] && { echo "❌ RESOURCE_GROUP 를 환경변수/인자/.env 로 지정하세요"; exit 1; }

TEMPLATE="workbook-template.json"
DISPLAY_NAME="${WORKBOOK_NAME:-AI Gateway — 멀티클라우드 구독별 거버넌스}"
[ -f "$TEMPLATE" ] || { echo "❌ $TEMPLATE 이(가) 없습니다"; exit 1; }

# App Insights 리소스 ID 자동 탐색(RG 내 첫 컴포넌트, 또는 APP_INSIGHTS_NAME 지정)
if [ -n "${APP_INSIGHTS_NAME:-}" ]; then
  AI_ID=$(az monitor app-insights component show -g "$RG" --app "$APP_INSIGHTS_NAME" --query id -o tsv)
else
  AI_ID=$(az monitor app-insights component show -g "$RG" --query "[0].id" -o tsv 2>/dev/null || true)
fi
[ -z "${AI_ID:-}" ] && { echo "❌ App Insights 컴포넌트를 찾지 못했습니다 (RG=$RG). APP_INSIGHTS_NAME 을 지정하세요"; exit 1; }
LOCATION=$(az group show -n "$RG" --query location -o tsv)
SUB=$(az account show --query id -o tsv)
echo "App Insights : $AI_ID"
echo "Location     : $LOCATION"
echo "Display name : $DISPLAY_NAME"

# ARM 요청 바디 생성(파이썬: 플레이스홀더 치환 + serializedData 문자열화 + 결정적 GUID)
BODY=$(mktemp)
WB_ID=$(python3 - "$TEMPLATE" "$AI_ID" "$LOCATION" "$DISPLAY_NAME" "$BODY" <<'PY'
import json, sys, uuid
template, ai_id, location, display, out = sys.argv[1:6]
data = open(template).read().replace("__APP_INSIGHTS_ID__", ai_id)
# 이름(GUID)을 AI_ID+displayName 으로 결정 → 재배포 시 동일 리소스 덮어쓰기(멱등)
wb_guid = str(uuid.uuid5(uuid.NAMESPACE_URL, ai_id + "|" + display))
body = {"location": location, "kind": "shared",
        "properties": {"displayName": display, "serializedData": data,
                       "version": "Notebook/1.0", "sourceId": ai_id, "category": "workbook"}}
json.dump(body, open(out, "w"), ensure_ascii=False)
print(wb_guid)
PY
)

URL="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Insights/workbooks/$WB_ID?api-version=2023-06-01"
echo "배포 중… (workbook GUID=$WB_ID)"
RESOURCE_ID=$(az rest --method PUT --url "$URL" --body @"$BODY" --headers "Content-Type=application/json" --query id -o tsv)
rm -f "$BODY"

# 포털 딥링크 생성(App Insights Usage Notebook 블레이드)
DEEPLINK=$(python3 - "$AI_ID" "$RESOURCE_ID" <<'PY'
import sys, urllib.parse
ai, wb = sys.argv[1], sys.argv[2]
print("https://portal.azure.com/#blade/AppInsightsExtension/UsageNotebookBlade/ComponentId/"
      + urllib.parse.quote(ai, safe="") + "/ConfigurationId/"
      + urllib.parse.quote(wb, safe="") + "/Type/workbook")
PY
)

echo "✅ 배포 완료"
echo "   Resource : $RESOURCE_ID"
echo "   열기      : $DEEPLINK"
echo "   또는 포털 → Monitor → Workbooks → '$DISPLAY_NAME'"
