# Lab 4: AI 전용 정책 적용

Azure API Management의 Azure OpenAI 전용 정책을 활용하여 토큰 관리, 캐싱, 메트릭 수집을 구현합니다.

## 목표

- 토큰 기반 Rate Limiting 적용
- 토큰 메트릭 수집 설정
- 시맨틱 캐싱 구성
- Retry 및 Circuit Breaker 정책 조합

## 실습 단계

### 1단계: 토큰 기반 Rate Limiting

일반 Rate Limiting(요청 수 기반)이 아닌, **토큰 수 기반**으로 속도를 제한합니다.

> **적용 위치: Inbound processing** — 백엔드 호출 전에 토큰 예산을 차감합니다.

```xml
<!-- Inbound processing에 추가 -->
<azure-openai-token-limit
        counter-key="@(context.Subscription.Id)"
        tokens-per-minute="10000"
        estimate-prompt-tokens="true"
        remaining-tokens-variable-name="remainingTokens"
        remaining-tokens-header-name="x-ratelimit-remaining-tokens"
        tokens-consumed-variable-name="tokensConsumed"
        tokens-consumed-header-name="x-ratelimit-tokens-consumed" />
```

**정책 조각 파일:** `policies/fragments/token-rate-limit.xml`

### 2단계: 토큰 메트릭 수집

Application Insights로 토큰 사용량 메트릭을 전송합니다.

> **적용 위치: Outbound processing** — 백엔드 응답에서 토큰 사용량을 추출한 후 메트릭으로 전송합니다.

```xml
<!-- Outbound processing에 추가 -->
<azure-openai-emit-token-metric namespace="ai-gateway-metrics">
        <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
        <dimension name="Client IP" value="@(context.Request.IpAddress)" />
        <dimension name="API ID" value="@(context.Api.Id)" />
        <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
        <dimension name="Backend" value="@(context.Request.Url.Host)" />
    </azure-openai-emit-token-metric>
```

**정책 조각 파일:** `policies/fragments/emit-token-metrics.xml`

### 3단계: 시맨틱 캐싱

유사한 프롬프트에 대해 이전 응답을 캐시에서 반환합니다.

> **적용 위치: Inbound + Outbound 모두 필요**
> - `cache-lookup`은 **Inbound** — 요청이 들어올 때 캐시에서 유사한 응답을 찾습니다
> - `cache-store`는 **Outbound** — 백엔드 응답을 캐시에 저장합니다

**사전 준비:** Embedding 모델이 배포된 Azure OpenAI 백엔드 필요

```bash
# Embedding 모델 배포 (deploy.sh가 생성한 OpenAI 리소스 이름 사용)
set -a; source .env; set +a

az cognitiveservices account deployment create \
  --name aoai-eus-<suffix> \
  --resource-group $RESOURCE_GROUP \
  --deployment-name text-embedding-ada-002 \
  --model-name text-embedding-ada-002 \
  --model-version "2" \
  --model-format OpenAI \
  --sku-capacity 30 \
  --sku-name Standard
```

> 💡 `<suffix>`는 `infra/parameters/dev.bicepparam`의 suffix 값입니다 (예: `cja0316`).

```xml
<!-- Inbound processing에 추가 -->
<azure-openai-semantic-cache-lookup
    score-threshold="0.8"
    embeddings-backend-id="embedding-backend"
    embeddings-backend-auth="system-assigned" />
```

```xml
<!-- Outbound processing에 추가 -->
<azure-openai-semantic-cache-store duration="3600" />
```
```

**정책 조각 파일:** `policies/fragments/semantic-caching.xml`

### 4단계: Retry 정책

429(Rate Limit) 또는 일시적 서버 에러 시 자동으로 재시도합니다.

> **적용 위치: Backend** — 백엔드 호출 시점에서 동작합니다. 실패 시 다른 백엔드로 재시도합니다.
>
> ⚠️ **Backend 섹션은 `<base />`를 `<retry>` 블록으로 교체**합니다.

```xml
<!-- Backend 섹션 전체를 아래로 교체 -->
<backend>
    <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)"
           count="3"
           interval="1"
           max-interval="10"
           delta="1"
           first-fast-retry="false">
        <set-backend-service backend-id="openai-backend-pool" />
        <forward-request buffer-request-body="true" />
    </retry>
</backend>
```

**정책 조각 파일:** `policies/fragments/retry-with-fallback.xml`

### 5단계: 전체 정책 조합

1~4단계의 모든 정책을 하나로 조합한 완성된 AI Gateway 정책입니다.

1. Azure Portal → APIM → **APIs** → **Azure OpenAI** → **All operations**
2. **Inbound processing** 영역의 **</>** 클릭 (Code View — 전체 XML 편집)
3. 아래 XML으로 **전체 교체** 후 **Save**

> 💡 각 정책이 어느 섹션에 들어가는지 주석으로 표시했습니다.

```xml
<policies>
    <inbound>
        <base />
        <!-- 인증 -->
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
        <!-- 시맨틱 캐시 조회 (캐시 히트 시 토큰 소비 없이 outbound으로 이동) -->
        <azure-openai-semantic-cache-lookup
            score-threshold="0.8"
            embeddings-backend-id="embedding-backend"
            embeddings-backend-auth="system-assigned" />
        <!-- 토큰 Rate Limiting (캐시 미스 시에만 토큰 차감) -->
        <azure-openai-token-limit
            counter-key="@(context.Subscription.Id)"
            tokens-per-minute="10000"
            estimate-prompt-tokens="true"
            remaining-tokens-variable-name="remainingTokens"
            remaining-tokens-header-name="x-ratelimit-remaining-tokens"
            tokens-consumed-variable-name="tokensConsumed"
            tokens-consumed-header-name="x-ratelimit-tokens-consumed" />
        <!-- 백엔드 풀 로드밸런싱 -->
        <set-backend-service backend-id="openai-backend-pool" />
    </inbound>
    <backend>
        <!-- 429(Rate Limit) 또는 500+(서버 에러) 시 재시도 -->
        <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)"
               count="3" interval="1" max-interval="10" delta="1"
               first-fast-retry="false">
            <set-backend-service backend-id="openai-backend-pool" />
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound>
        <base />
        <!-- 시맨틱 캐시 저장 -->
        <azure-openai-semantic-cache-store duration="3600" />
        <!-- 토큰 메트릭 수집 (모델별·백엔드별 TPM 추적) -->
        <azure-openai-emit-token-metric namespace="ai-gateway-metrics">
            <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
            <dimension name="Client IP" value="@(context.Request.IpAddress)" />
            <dimension name="API ID" value="@(context.Api.Id)" />
            <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
            <dimension name="Backend" value="@(context.Request.Url.Host)" />
        </azure-openai-emit-token-metric>

        <!-- 커스텀 메트릭: 응답 지연 시간 -->
        <emit-metric name="ai-gateway-latency" namespace="ai-gateway-metrics">
            <dimension name="API" value="@(context.Api.Name)" />
            <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
            <dimension name="Backend" value="@(context.Request.Url.Host)" />
            <dimension name="Status" value="@(context.Response.StatusCode.ToString())" />
            <value>@(context.Elapsed.TotalMilliseconds)</value>
        </emit-metric>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

## 핵심 개념

### Azure OpenAI 전용 정책 목록

| 정책 | 영역 | 용도 |
|------|------|------|
| `azure-openai-token-limit` | inbound | 토큰 기반 Rate Limiting |
| `azure-openai-emit-token-metric` | outbound | 토큰 메트릭 수집 |
| `azure-openai-semantic-cache-lookup` | inbound | 시맨틱 캐시 조회 |
| `azure-openai-semantic-cache-store` | outbound | 시맨틱 캐시 저장 |

### 일반 정책 vs AI 전용 정책

| 일반 정책 | AI 전용 정책 | 차이점 |
|----------|-------------|--------|
| `rate-limit` | `azure-openai-token-limit` | 요청 수 vs 토큰 수 |
| `cache-lookup` | `azure-openai-semantic-cache-lookup` | 정확한 매칭 vs 유사도 매칭 |
| `emit-metric` | `azure-openai-emit-token-metric` | 일반 메트릭 vs 토큰 메트릭 |

## 테스트 방법

### 노트북 테스트

`labs/lab04-policies/test-multitenant.ipynb`를 실행하세요.

노트북에서 다음을 테스트합니다:
1. **토큰 Rate Limiting**: 큰 max_tokens로 연속 호출하여 429 응답 유발
2. **토큰 사용량 헤더**: `x-ratelimit-remaining-tokens` 헤더 변화 추적
3. **캐싱 효과**: 동일 프롬프트 반복 호출 시 응답 시간 비교

### VS Code REST Client

`scripts/test-endpoints.http`의 `Lab 4` 섹션에서:
- **4-1**: Rate Limiting 테스트 (반복 호출하여 `x-ratelimit-remaining-tokens` 관찰)
- **4-2, 4-3**: 캐싱 테스트 (동일 프롬프트, 응답 시간 비교)
- **4-4**: 시맨틱 캐시 테스트 (유사 프롬프트, 캐시 히트 확인)

## 다음 단계

→ [Lab 5: 멀티 모델 Gateway](../lab05-multi-model-gateway/README.md)
