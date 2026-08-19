#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/.env.logbench-v4"
TAG="$(az group show -n "$LOGBENCH_RG" --query "tags.\"managed-by\"" -o tsv)"
[ "$TAG" = "lab13-v4" ] || { echo "Refusing to delete unrecognized RG" >&2; exit 1; }
az group delete -n "$LOGBENCH_RG" --yes --no-wait
echo "Disposable RG deletion requested. APIM and logbench-v4 API were not changed."
