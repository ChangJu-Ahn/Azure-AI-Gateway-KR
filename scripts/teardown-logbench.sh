#!/bin/bash
set -euo pipefail

# ─── Lab 13 로깅 성능 벤치마크 — 전용 리소스 전체 삭제 ───
# RG 를 통째로 삭제하고 soft-delete 된 APIM 을 purge 합니다.

if [ -f ".env.logbench" ]; then
    # shellcheck disable=SC1091
    set -a; source .env.logbench; set +a
fi

SUFFIX="${1:-${LOGBENCH_SUFFIX:-}}"

if [ -z "${LOGBENCH_RG:-}" ] && [ -z "$SUFFIX" ]; then
    echo "❌ 삭제할 리소스 그룹을 결정하지 못했습니다. suffix 를 인자로 주세요:"
    echo "   ./scripts/teardown-logbench.sh <suffix>"
    exit 1
fi

RESOURCE_GROUP="${LOGBENCH_RG:-rg-ai-gw-logbench-${SUFFIX}}"

APIM_NAME="${LOGBENCH_APIM_NAME:-}"
APIM_LOCATION="${LOGBENCH_LOCATION:-japaneast}"

echo "=== LogBench 삭제 ==="
echo "리소스 그룹: ${RESOURCE_GROUP}"

az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "🗑️  RG 삭제 요청 완료(백그라운드 진행)."

if [ -n "$APIM_NAME" ]; then
    echo "⏳ APIM soft-delete purge 시도: ${APIM_NAME}"
    az apim deletedservice purge --service-name "$APIM_NAME" --location "$APIM_LOCATION" 2>/dev/null \
        && echo "✅ APIM purge 완료" \
        || echo "ℹ️ purge 대상이 아직 없거나 이미 정리됨(수 분 후 재시도 가능)."
fi

echo ""
echo "✅ teardown 요청 완료. Azure Portal 에서 RG 삭제 상태를 확인하세요."
