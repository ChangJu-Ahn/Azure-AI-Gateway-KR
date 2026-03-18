#!/bin/bash
set -euo pipefail

# ─── APIM 모니터링 설정 스크립트 ───
# APIM을 수동으로 재생성한 경우, 배포 시 자동 설정되는 모니터링 구성을 복원합니다.
#
# 설정 항목:
#   1. Application Insights Logger (appinsights-logger)
#   2. Application Insights Diagnostics (프론트엔드/백엔드 body 로깅 포함)
#   3. Custom Metrics 활성화 (emit-token-metric 정책용)
#   4. APIM → Log Analytics Diagnostic Setting (APIM Analytics 블레이드용)

# ─── 설정값 ───
SUFFIX="${1:-}"

if [ -z "$SUFFIX" ]; then
    # .env 또는 bicepparam에서 suffix 추출 시도
    if [ -f ".env" ]; then
        RG_FROM_ENV=$(grep "^RESOURCE_GROUP=" .env | sed 's/RESOURCE_GROUP=//' || true)
        SUFFIX=$(echo "$RG_FROM_ENV" | sed 's/rg-ai-gw-//')
    fi
    if [ -z "$SUFFIX" ]; then
        SUFFIX=$(grep "param suffix" infra/parameters/dev.bicepparam 2>/dev/null | sed "s/.*= '//;s/'.*//")
    fi
fi

if [ -z "$SUFFIX" ]; then
    echo "❌ suffix를 결정할 수 없습니다."
    echo "   사용법: ./scripts/setup-monitoring.sh <suffix>"
    exit 1
fi

RESOURCE_GROUP="rg-ai-gw-${SUFFIX}"
APIM_NAME="apim-ai-gw-${SUFFIX}"
APP_INSIGHTS_NAME="appi-ai-gw-${SUFFIX}"
LOG_ANALYTICS_NAME="log-ai-gw-${SUFFIX}"

echo "=== APIM 모니터링 설정 ==="
echo "리소스 그룹:      ${RESOURCE_GROUP}"
echo "APIM:             ${APIM_NAME}"
echo "App Insights:     ${APP_INSIGHTS_NAME}"
echo "Log Analytics:     ${LOG_ANALYTICS_NAME}"
echo ""

# ─── 1. 리소스 존재 확인 ───
echo "🔍 리소스 확인 중..."

APIM_ID=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null) || {
    echo "❌ APIM을 찾을 수 없습니다: ${APIM_NAME}"
    exit 1
}
echo "   ✅ APIM: ${APIM_NAME}"

APP_INSIGHTS_ID=$(az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null) || {
    echo "❌ Application Insights를 찾을 수 없습니다: ${APP_INSIGHTS_NAME}"
    echo "   먼저 deploy.sh로 인프라를 배포하거나, App Insights를 수동 생성하세요."
    exit 1
}
echo "   ✅ App Insights: ${APP_INSIGHTS_NAME}"

INSTRUMENTATION_KEY=$(az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --query instrumentationKey -o tsv)
echo "   Instrumentation Key: ${INSTRUMENTATION_KEY:0:8}..."

LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null) || {
    echo "⚠️  Log Analytics를 찾을 수 없습니다: ${LOG_ANALYTICS_NAME}"
    echo "   APIM Analytics 블레이드 설정을 건너뜁니다."
    LOG_ANALYTICS_ID=""
}
if [ -n "$LOG_ANALYTICS_ID" ]; then
    echo "   ✅ Log Analytics: ${LOG_ANALYTICS_NAME}"
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo ""

# ─── 2. Application Insights Logger 생성 ───
echo "📊 [1/4] Application Insights Logger 생성..."
LOGGER_ID="${APIM_ID}/loggers/appinsights-logger"

az rest --method PUT \
    --url "https://management.azure.com${LOGGER_ID}?api-version=2023-09-01-preview" \
    --body "{
        \"properties\": {
            \"loggerType\": \"applicationInsights\",
            \"credentials\": {
                \"instrumentationKey\": \"${INSTRUMENTATION_KEY}\"
            },
            \"isBuffered\": true,
            \"resourceId\": \"${APP_INSIGHTS_ID}\"
        }
    }" \
    --output none

echo "   ✅ Logger 'appinsights-logger' 생성 완료"

# ─── 3. Application Insights Diagnostics 설정 ───
echo "📊 [2/4] Application Insights Diagnostics 설정..."

az rest --method PUT \
    --url "https://management.azure.com${APIM_ID}/diagnostics/applicationinsights?api-version=2023-09-01-preview" \
    --body "{
        \"properties\": {
            \"loggerId\": \"${LOGGER_ID}\",
            \"alwaysLog\": \"allErrors\",
            \"sampling\": {
                \"percentage\": 100,
                \"samplingType\": \"fixed\"
            },
            \"logClientIp\": true,
            \"httpCorrelationProtocol\": \"W3C\",
            \"verbosity\": \"information\",
            \"metrics\": true,
            \"frontend\": {
                \"request\": {
                    \"headers\": [\"Content-Type\", \"Ocp-Apim-Subscription-Key\", \"x-model-provider\"],
                    \"body\": {
                        \"bytes\": 4096
                    }
                },
                \"response\": {
                    \"headers\": [\"Content-Type\", \"x-ratelimit-remaining-tokens\"],
                    \"body\": {
                        \"bytes\": 4096
                    }
                }
            },
            \"backend\": {
                \"request\": {
                    \"headers\": [\"Content-Type\", \"Authorization\"],
                    \"body\": {
                        \"bytes\": 4096
                    }
                },
                \"response\": {
                    \"headers\": [\"Content-Type\", \"x-ms-region\", \"x-ratelimit-remaining-tokens\", \"x-ratelimit-remaining-requests\"],
                    \"body\": {
                        \"bytes\": 4096
                    }
                }
            }
        }
    }" \
    --output none

echo "   ✅ Diagnostics 설정 완료 (프론트엔드/백엔드 body 로깅 포함)"

# ─── 4. Custom Metrics 활성화 ───
echo "📊 [3/4] Custom Metrics (with dimensions) 활성화..."

# App Insights의 커스텀 메트릭 활성화는 Portal에서만 가능한 부분이 있으나,
# Diagnostics에 metrics: true를 이미 설정했으므로 emit-token-metric이 작동합니다.
echo "   ✅ Diagnostics에 metrics: true 설정 완료"
echo "   ⚠️  Portal → App Insights → Usage and estimated costs → Custom metrics (Preview)"
echo "      → 'With dimensions' 선택도 확인하세요 (CLI로 설정 불가)"

# ─── 5. APIM → Log Analytics Diagnostic Setting ───
echo "📊 [4/4] APIM Analytics 블레이드용 Diagnostic Setting..."

if [ -n "$LOG_ANALYTICS_ID" ]; then
    az monitor diagnostic-settings create \
        --name "apim-to-log-analytics" \
        --resource "$APIM_ID" \
        --workspace "$LOG_ANALYTICS_ID" \
        --logs '[
            {"categoryGroup": "allLogs", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}},
            {"categoryGroup": "audit", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}
        ]' \
        --metrics '[
            {"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}
        ]' \
        --output none 2>/dev/null || {
        # categoryGroup 미지원 시 개별 카테고리로 재시도
        echo "   ⚠️  categoryGroup 미지원, 개별 카테고리로 재시도..."
        az monitor diagnostic-settings create \
            --name "apim-to-log-analytics" \
            --resource "$APIM_ID" \
            --workspace "$LOG_ANALYTICS_ID" \
            --logs '[
                {"category": "GatewayLogs", "enabled": true},
                {"category": "WebSocketConnectionLogs", "enabled": true}
            ]' \
            --metrics '[
                {"category": "AllMetrics", "enabled": true}
            ]' \
            --output none
    }
    echo "   ✅ Diagnostic Setting 'apim-to-log-analytics' 생성 완료"
    echo "      → Portal → APIM → Analytics 블레이드에서 확인 가능"
else
    echo "   ⏭️  Log Analytics가 없어 건너뜁니다."
fi

echo ""
echo "============================================"
echo "✅ 모니터링 설정 완료!"
echo "============================================"
echo ""
echo "설정된 항목:"
echo "  1. ✅ APIM Logger (appinsights-logger)"
echo "  2. ✅ APIM Diagnostics (App Insights 연동)"
echo "     - 샘플링: 100% (고정)"
echo "     - 프론트엔드/백엔드 request·response body 로깅 (4KB)"
echo "     - W3C 상관 관계 추적"
echo "     - Custom Metrics 활성화"
echo "  3. ✅ APIM → Log Analytics Diagnostic Setting"
echo "     - GatewayLogs, AllMetrics 수집"
echo "     - APIM Analytics 블레이드 사용 가능"
echo ""
echo "추가 필요 작업:"
echo "  📌 Portal → App Insights → Usage and estimated costs"
echo "     → Custom metrics (Preview) → 'With dimensions' 선택"
echo "  📌 APIM API 정책에 azure-openai-emit-token-metric 추가 (lab06 참고)"
