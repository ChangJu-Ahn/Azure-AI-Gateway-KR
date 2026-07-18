# Lab 8: 멀티 클라우드 통합 게이트웨이

> ✅ **통합 라우팅 라이브 검증됨** — [`test-multicloud-gateway.ipynb`](./test-multicloud-gateway.ipynb)
> 로 실제 배포에서 **하나의 통합 엔드포인트 → `model` prefix 만으로 Azure OpenAI(배포경로)·Google Gemini(OpenAI 호환)** 이중 클라우드 라우팅을 200 으로 E2E 확인했습니다.
> 미구성 프로바이더(OpenAI·Anthropic)는 게이트웨이가 백엔드 도달 전 400 으로 차단하며, `.env` 키만 추가하면 동일 패턴으로 활성화됩니다.

하나의 OpenAI 호환 엔드포인트로 **Azure OpenAI(기본)** 와 **Azure 외부의 OpenAI · Anthropic · Google Gemini** 를 통합 관리합니다. 클라이언트는 `model` 필드만 바꾸면 프로바이더가 전환되고, 게이트웨이가 토큰 제어·메트릭·Fallback을 동일하게 적용합니다.

## 목표

- Azure OpenAI(기본) + Azure 외부 3사(OpenAI·Anthropic·Google Gemini)를 단일 OpenAI 호환 API 로 통합 (Approach A: 통합 계약)
- 프로바이더별 백엔드 풀로 로드밸런싱 (Lab 3/5 개념 재사용)
- 프로바이더 무관 `llm-*` 정책으로 토큰 제어·메트릭 통일 (+ Provider 차원)
- 크로스클라우드 Fallback
- 외부 3사(OpenAI·Anthropic·Google Gemini)는 모두 **OpenAI 호환 엔드포인트**를 제공 → 별도 SDK 없이 동일 계약으로 통합

## 왜 llm-* 정책인가 (azure-openai-* 와 차이)

| | `azure-openai-*` (Lab 4/6) | `llm-*` (이번 Lab) |
|---|---|---|
| 대상 백엔드 | Azure OpenAI 전용 | OpenAI 호환 usage 를 반환하는 **모든** 프로바이더 |
| 토큰 제한 | `azure-openai-token-limit` | `llm-token-limit` |
| 토큰 메트릭 | `azure-openai-emit-token-metric` | `llm-emit-token-metric` (+ Provider 차원) |
| 시맨틱 캐시 | `azure-openai-semantic-cache-*` | `llm-semantic-cache-*` |

> 💡 OpenAI·Anthropic·Gemini 는 모두 OpenAI 호환 응답의 `usage` 필드를 반환하므로,
> `llm-*` 정책이 프로바이더와 무관하게 동일하게 토큰을 계량합니다.

## 아키텍처

```mermaid
graph TD
    Client["클라이언트<br/>OpenAI SDK · model 만 변경"] -->|Ocp-Apim-Subscription-Key| GW["APIM 통합 게이트웨이<br/>/openai/v1/chat/completions"]
    GW -->|model prefix 라우팅| R{provider}
    R -->|azure / (기본)| AOAI["Azure OpenAI 풀<br/>Lab3 재사용 · Managed Identity"]
    R -->|openai/*| OAI["OpenAI 직접"]
    R -->|anthropic/*| ANT["Anthropic 풀<br/>키 3개 로드밸런싱"]
    R -->|gemini/*| GEM["Gemini 풀<br/>Lab5 재사용"]
    AOAI & OAI & ANT & GEM -.->|429/5xx 시 retry| FB["Fallback"]
```

## 사전 준비 (.env / Named Value)

아래 값을 `.env` 파일에 설정한 뒤 Named Value 등록 단계에서 사용합니다.

```bash
RESOURCE_GROUP=<리소스 그룹>
APIM_NAME=<APIM 서비스명>
OPENAI_API_KEY=<OpenAI API 키>
ANTHROPIC_API_KEY_1=<Anthropic API 키 1>
ANTHROPIC_API_KEY_2=<Anthropic API 키 2>
ANTHROPIC_API_KEY_3=<Anthropic API 키 3>
# Gemini 키(gemini-api-key-1..3)는 Lab 5에서 이미 등록됨
```

### 프로바이더 통합 표

| 프로바이더 | 백엔드 URL | 인증 | model 필드 예시 |
|---|---|---|---|
| Azure OpenAI | 기존 풀 (Lab 2/3) | `Managed Identity` | `gpt-4.1-nano` (prefix 없음) |
| OpenAI 직접 | `https://api.openai.com/v1` | `Authorization: Bearer {{openai-api-key}}` | `openai/gpt-4o` |
| Anthropic | `https://api.anthropic.com/v1` (키 3개 풀) | 백엔드 credential (raw 키, `ANTHROPIC_API_KEY_1..3`) | `anthropic/claude-3-5-sonnet-20241022` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | `Authorization: Bearer {{gemini-api-key-1}}` | `gemini/gemini-2.0-flash` |

> ⚠️ OpenAI·Anthropic·Gemini 모델명은 각 콘솔에서 최신 값을 확인하세요. 세 프로바이더 모두 OpenAI 호환 `/chat/completions` 경로를 지원합니다.

## 실습 단계

> 🔬 **핸즈온 노트북** — [`test-multicloud-gateway.ipynb`](./test-multicloud-gateway.ipynb) 가 아래 1~4단계를
> 자동화합니다. `.env` 에 설정된 프로바이더 키를 감지해 **구성된 프로바이더만** 통합 `<choose>` 라우팅
> 정책에 포함하고, 통합 API를 배포한 뒤 `model` prefix 라우팅을 실제 호출로 검증하고, 마지막에
> 노트북이 만든 리소스를 정리합니다(Lab 5의 `gemini-api-key-*` 는 보존). Azure OpenAI 는 키 없이
> Managed Identity 로 동작하므로 별도 설정 없이 바로 라우팅됩니다.

### 1단계: 프로바이더 키를 Named Value(secret)로 등록

```bash
set -a; source .env; set +a

az apim nv create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --named-value-id openai-api-key --display-name "OpenAI-API-Key" \
  --value "$OPENAI_API_KEY" --secret true
```

> Gemini 키(`gemini-api-key-1..3`)는 Lab 5에서 이미 등록되어 있습니다.
> Anthropic 키는 **Named Value 로 등록하지 않습니다** — APIM 은 백엔드 credential 안의 `{{named-value}}` 를
> 해석하지 않기 때문에(리터럴 전송 → 401), 2단계에서 **raw 키를 백엔드 credential 에 직접** 주입합니다.

### 2단계: 프로바이더별 백엔드 등록

```bash
# OpenAI 직접 (단일 백엔드)
az apim backend create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --backend-id openai-direct-backend --protocol http \
  --url "https://api.openai.com/v1"
```

**Anthropic — 키 3개 백엔드 풀 (Lab 5 Gemini 와 동일 패턴)**

`az apim backend create`는 Circuit Breaker·credential을 지원하지 않으므로 REST API로 등록합니다. 각 백엔드는 동일 URL을 가리키지만 서로 다른 키를 사용합니다. ⚠️ APIM 은 백엔드 credential 안의 `{{named-value}}` 를 해석하지 않으므로(리터럴 전송 → 401), **`.env` 의 raw 키**를 credential 의 `Authorization: Bearer` 에 직접 넣습니다.

```bash
set -a; source .env; set +a
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
APIM_RID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}"

# 백엔드 3개 (각각 다른 raw 키 + Circuit Breaker)
for i in 1 2 3; do
  key_var="ANTHROPIC_API_KEY_${i}"
  az rest --method PUT \
    --url "https://management.azure.com${APIM_RID}/backends/anthropic-backend-${i}?api-version=2024-06-01-preview" \
    --body "{
      \"properties\": {
        \"url\": \"https://api.anthropic.com/v1\",
        \"protocol\": \"http\",
        \"description\": \"Anthropic Backend ${i}\",
        \"credentials\": {
          \"header\": { \"Authorization\": [\"Bearer ${!key_var}\"] }
        },
        \"circuitBreaker\": {
          \"rules\": [{
            \"failureCondition\": {
              \"count\": 3,
              \"errorReasons\": [\"Server errors\"],
              \"interval\": \"PT10S\",
              \"statusCodeRanges\": [{\"min\":429,\"max\":429},{\"min\":500,\"max\":503}]
            },
            \"name\": \"anthropicCircuitBreaker\",
            \"tripDuration\": \"PT30S\",
            \"acceptRetryAfter\": false
          }]
        }
      }
    }"
done

# 3개 백엔드를 하나의 풀로 밀어 Round Robin 로드밸런싱
az rest --method PUT \
  --url "https://management.azure.com${APIM_RID}/backends/anthropic-backend-pool?api-version=2024-06-01-preview" \
  --body '{
    "properties": {
      "type": "Pool",
      "pool": {
        "services": [
          { "id": "/backends/anthropic-backend-1", "priority": 1, "weight": 1 },
          { "id": "/backends/anthropic-backend-2", "priority": 1, "weight": 1 },
          { "id": "/backends/anthropic-backend-3", "priority": 1, "weight": 1 }
        ]
      }
    }
  }'
```

> `openai-backend-pool`(Azure OpenAI)·`gemini-backend-pool`(Gemini)·`anthropic-backend-pool`(Anthropic)은 각각 풀로 로드밸런싱됩니다.
> OpenAI 직접은 단일 백엔드이며, 여러 키/리전을 두려면 동일하게 Lab 3/5 방식으로 풀을 구성합니다.

### 3단계: 통합 API 등록 & 정책 적용

`/openai/v1/chat/completions` 경로의 API를 만들고, 아래 정책을 적용합니다.
개별 조각은 `policies/fragments/model-routing.xml`, `llm-token-limit.xml`, `llm-emit-token-metrics.xml` 참고.

```xml
<policies>
    <inbound>
        <base />
        <!-- 구독별 토큰 제한 (프로바이더 무관) -->
        <llm-token-limit counter-key="@(context.Subscription.Id)"
            tokens-per-minute="10000" estimate-prompt-tokens="true"
            remaining-tokens-header-name="x-ratelimit-remaining-tokens" />
        <!-- model prefix 라우팅 + 인증 주입 (policies/fragments/model-routing.xml) -->
        <include-fragment fragment-id="model-routing" />
        <!-- 토큰 메트릭 (+ Provider 차원) -->
        <include-fragment fragment-id="llm-emit-token-metrics" />
    </inbound>
    <backend>
        <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)"
               count="3" interval="1" max-interval="10" delta="1" first-fast-retry="false">
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
```

> `include-fragment`를 쓰려면 각 조각을 먼저 APIM Policy Fragment 로 등록해야 합니다.
> (Portal → APIM → Policy fragments → + Create, 또는 `az apim policy-fragment create`)

### 4단계: 테스트 (동일 SDK, model 만 변경)

```python
from openai import OpenAI
client = OpenAI(base_url="https://<apim>.azure-api.net/openai/v1",
                api_key="<APIM_SUBSCRIPTION_KEY>")  # Ocp-Apim-Subscription-Key 로 전달되도록 설정

for model in ["gpt-4.1-nano", "openai/gpt-4o",
              "anthropic/claude-3-5-sonnet-20241022", "gemini/gemini-2.0-flash"]:
    r = client.chat.completions.create(model=model,
        messages=[{"role": "user", "content": "안녕하세요"}])
    print(model, "→", r.choices[0].message.content[:40], "| tokens:", r.usage.total_tokens)
```

## 핵심 개념

- 통합 OpenAI 계약: 클라이언트는 `model` 만 바꾼다
- `llm-*` 정책이 프로바이더와 무관하게 토큰을 계량·제한
- Provider 차원으로 멀티 클라우드 토큰을 구분 관측 (→ Lab 10)

## 다음 단계

→ [Lab 9: Products & 개발자 포털](../lab09-products-portal/README.md)
