# Lab 8: 멀티 클라우드 통합 게이트웨이

> ✅ **통합 라우팅 라이브 검증됨** — [`test-multicloud-gateway.ipynb`](./test-multicloud-gateway.ipynb)
> 로 실제 배포에서 **하나의 통합 엔드포인트 → `model` prefix 만으로 Azure OpenAI(배포경로)·Google Gemini(OpenAI 호환)** 이중 클라우드 라우팅을 200 으로 E2E 확인했습니다.
> 미구성 프로바이더(OpenAI·Bedrock·Anthropic)는 게이트웨이가 백엔드 도달 전 400 으로 차단하며, `.env` 키만 추가하면 동일 패턴으로 활성화됩니다.

하나의 OpenAI 호환 엔드포인트로 Azure OpenAI · OpenAI · AWS Bedrock · Anthropic · Google Gemini를 통합 관리합니다. 클라이언트는 `model` 필드만 바꾸면 프로바이더가 전환되고, 게이트웨이가 토큰 제어·메트릭·Fallback을 동일하게 적용합니다.

## 목표

- 5개 프로바이더를 단일 OpenAI 호환 API 로 통합 (Approach A: 통합 계약)
- 프로바이더별 백엔드 풀로 로드밸런싱 (Lab 3/5 개념 재사용)
- 프로바이더 무관 `llm-*` 정책으로 토큰 제어·메트릭 통일 (+ Provider 차원)
- 크로스클라우드 Fallback
- AWS Bedrock 을 2025 신규 **Bearer API 키** + OpenAI 호환 엔드포인트로 연결 (SigV4 불필요)

## 왜 llm-* 정책인가 (azure-openai-* 와 차이)

| | `azure-openai-*` (Lab 4/6) | `llm-*` (이번 Lab) |
|---|---|---|
| 대상 백엔드 | Azure OpenAI 전용 | OpenAI 호환 usage 를 반환하는 **모든** 프로바이더 |
| 토큰 제한 | `azure-openai-token-limit` | `llm-token-limit` |
| 토큰 메트릭 | `azure-openai-emit-token-metric` | `llm-emit-token-metric` (+ Provider 차원) |
| 시맨틱 캐시 | `azure-openai-semantic-cache-*` | `llm-semantic-cache-*` |

> 💡 Bedrock·Anthropic·Gemini 는 모두 OpenAI 호환 응답의 `usage` 필드를 반환하므로,
> `llm-*` 정책이 프로바이더와 무관하게 동일하게 토큰을 계량합니다.

## 아키텍처

```mermaid
graph TD
    Client["클라이언트<br/>OpenAI SDK · model 만 변경"] -->|Ocp-Apim-Subscription-Key| GW["APIM 통합 게이트웨이<br/>/openai/v1/chat/completions"]
    GW -->|model prefix 라우팅| R{provider}
    R -->|azure / (기본)| AOAI["Azure OpenAI 풀<br/>Lab3 재사용 · Managed Identity"]
    R -->|openai/*| OAI["OpenAI 직접"]
    R -->|bedrock/*| BR["AWS Bedrock<br/>Bearer API 키 (2025)"]
    R -->|anthropic/*| ANT["Anthropic"]
    R -->|gemini/*| GEM["Gemini 풀<br/>Lab5 재사용"]
    AOAI & OAI & BR & ANT & GEM -.->|429/5xx 시 retry| FB["Fallback"]
```

## 사전 준비 (.env / Named Value)

아래 값을 `.env` 파일에 설정한 뒤 Named Value 등록 단계에서 사용합니다.

```bash
RESOURCE_GROUP=<리소스 그룹>
APIM_NAME=<APIM 서비스명>
OPENAI_API_KEY=<OpenAI API 키>
AWS_BEDROCK_API_KEY=<AWS Bedrock API 키 (Bearer 토큰)>
AWS_BEDROCK_REGION=<us-east-1 등>
ANTHROPIC_API_KEY=<Anthropic API 키>
# Gemini 키(gemini-api-key-1..3)는 Lab 5에서 이미 등록됨
```

### 프로바이더 통합 표

| 프로바이더 | 백엔드 URL | 인증 | model 필드 예시 |
|---|---|---|---|
| Azure OpenAI | 기존 풀 (Lab 2/3) | `Managed Identity` | `gpt-4.1-nano` (prefix 없음) |
| OpenAI 직접 | `https://api.openai.com/v1` | `Authorization: Bearer {{openai-api-key}}` | `openai/gpt-4o` |
| AWS Bedrock | `https://bedrock-runtime.{region}.amazonaws.com/openai/v1` | `Authorization: Bearer {{aws-bedrock-api-key}}` | `bedrock/us.anthropic.claude-3-5-sonnet-20241022-v2:0` |
| Anthropic | `https://api.anthropic.com/v1` | `Authorization: Bearer {{anthropic-api-key}}` | `anthropic/claude-3-5-sonnet-20241022` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | `Authorization: Bearer {{gemini-api-key-1}}` | `gemini/gemini-2.0-flash` |

> ⚠️ Bedrock 모델 ID·리전, Anthropic/Gemini 모델명은 각 콘솔에서 최신 값을 확인하세요.
> Bedrock 은 2025년 도입된 **API 키(Bearer 토큰)**(장기/단기)를 사용하며, OpenAI 호환 경로
> `/openai/v1/chat/completions` 를 지원하므로 SigV4 서명이 필요 없습니다.

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

az apim nv create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --named-value-id aws-bedrock-api-key --display-name "AWS-Bedrock-API-Key" \
  --value "$AWS_BEDROCK_API_KEY" --secret true

az apim nv create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --named-value-id anthropic-api-key --display-name "Anthropic-API-Key" \
  --value "$ANTHROPIC_API_KEY" --secret true
```

> Gemini 키(`gemini-api-key-1..3`)는 Lab 5에서 이미 등록되어 있습니다.

### 2단계: 프로바이더별 백엔드 등록

```bash
# OpenAI 직접
az apim backend create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --backend-id openai-direct-backend --protocol http \
  --url "https://api.openai.com/v1"

# AWS Bedrock (리전 확인 후 URL 수정)
az apim backend create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --backend-id bedrock-backend --protocol http \
  --url "https://bedrock-runtime.$AWS_BEDROCK_REGION.amazonaws.com/openai/v1"

# Anthropic
az apim backend create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --backend-id anthropic-backend --protocol http \
  --url "https://api.anthropic.com/v1"
```

> `openai-backend-pool`(Azure OpenAI)·`gemini-backend-pool`(Gemini)은 Lab 3/5에서 구성됨.
> 각 프로바이더에 여러 키/리전을 두려면 Lab 3 방식으로 backend pool 을 구성해 로드밸런싱합니다.

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
              "bedrock/us.anthropic.claude-3-5-sonnet-20241022-v2:0",
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
