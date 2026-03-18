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

### 3단계: 시맨틱 캐싱 (별도 배포)

유사한 프롬프트에 대해 이전 응답을 캐시에서 반환합니다.

> ⚠️ **시맨틱 캐싱은 별도 배포가 필요합니다.**
> 임베딩 모델(Azure OpenAI) + Azure Redis Cache가 한 세트로 필요하므로, 기본 `deploy.sh`에는 포함되어 있지 않습니다.
>
> ```bash
> ./scripts/deploy-semantic-caching.sh <suffix>
> ```
>
> 배포 후 아래 정책을 적용하면 동작합니다.

> **적용 위치: Inbound + Outbound 모두 필요**
> - `cache-lookup`은 **Inbound** — 요청이 들어올 때 캐시에서 유사한 응답을 찾습니다
> - `cache-store`는 **Outbound** — 백엔드 응답을 캐시에 저장합니다

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

### 5단계: IP 필터링 (접근 제어)

특정 IP 대역만 AI API에 접근할 수 있도록 네트워크 수준 접근 제어를 적용합니다.

> **적용 위치: Inbound processing** — 요청이 들어올 때 즉시 IP를 검사합니다.

```xml
<!-- Inbound processing에 추가 (인증 정책 바로 뒤) -->

<!-- 허용된 IP만 통과 (화이트리스트) -->
<ip-filter action="allow">
    <address-range from="10.0.0.0" to="10.0.0.255" />
    <address>203.0.113.50</address>
</ip-filter>

<!-- 또는 특정 IP 차단 (블랙리스트) -->
<ip-filter action="forbid">
    <address>192.168.1.100</address>
</ip-filter>
```

> 💡 **allow vs forbid:**
> - `allow`: 목록에 **있는 IP만** 통과, 나머지 차단 (화이트리스트)
> - `forbid`: 목록에 **있는 IP를** 차단, 나머지 통과 (블랙리스트)
>
> 프로덕션에서는 `allow`로 사내 IP 대역만 허용하는 것이 일반적입니다.

> ⚠️ **APIM SKU별 IP 필터 동작 차이 (중요)**
>
> `ip-filter`는 `context.Request.IpAddress`를 기준으로 동작합니다.
> 이 값은 **APIM SKU에 따라 실제 클라이언트 IP와 다를 수 있습니다:**
>
> | SKU | `context.Request.IpAddress` | ip-filter 동작 |
> |-----|---------------------------|----------------|
> | **Developer, Basic, Standard, Premium** | 실제 클라이언트 공인 IP (전용 IP) | 정상 동작 ✅ |
> | **Consumption, Basic v2, Standard v2, Premium v2** | 공유 인프라 IP로 변환될 수 있음 | 의도와 다르게 동작할 수 있음 ⚠️ |
>
> 📖 **공식 문서 근거:**
>
> > *"If your API Management instance is created in a service tier that runs on a shared infrastructure, it doesn't have a dedicated IP address. Currently, instances in the following service tiers run on a shared infrastructure and without a deterministic IP address: Consumption, Basic v2, Standard v2, Premium v2."*
> >
> > — [IP addresses in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-ip-addresses#ip-addresses-of-consumption-basic-v2-standard-v2-and-premium-v2-tier-api-management-instances)
>
> > *"Every API Management instance in Developer, Basic, Standard, or Premium tier has public IP addresses that are exclusive only to that instance. (They're not shared with other resources.)"*
> >
> > — [IP addresses in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-ip-addresses#public-ip-addresses)
>
> 즉, **Consumption SKU는 공유 인프라**에서 실행되어 전용 IP가 없으므로,
> 클라이언트의 공인 IP가 APIM에 도달하기 전에 변환될 수 있습니다.
>
> **Consumption SKU에서 ip-filter를 테스트하려면:**
> 1. Outbound에 아래 정책을 추가하여 APIM이 인식하는 IP를 먼저 확인
>    ```xml
>    <set-header name="x-client-ip" exists-action="override">
>        <value>@(context.Request.IpAddress)</value>
>    </set-header>
>    ```
> 2. 응답의 `x-client-ip` 헤더에 나온 IP를 `ip-filter`에 사용
>
> **프로덕션 IP 필터링 권장 방식:**
>
> | 방법 | 적합한 SKU | 장점 |
> |------|-----------|------|
> | `ip-filter` 정책 | Developer, Standard, Premium | 간단, 전용 IP로 정확한 필터링 |
> | **VNet + NSG** | Standard, Premium | 네트워크 레벨 차단, 가장 안전 |
> | Application Gateway + WAF | 모든 SKU | L7 방화벽, DDoS 보호 |
>
> 프로덕션에서는 `ip-filter` 단독보다 **VNet + NSG** 조합이 권장됩니다.
> `ip-filter`는 애플리케이션 레벨이고, NSG는 네트워크 패킷 자체를 차단합니다.

### 6단계: CORS 정책 (웹 프론트엔드 허용)

React, Next.js 등 웹 프론트엔드에서 APIM을 직접 호출할 때 필요합니다.

> **적용 위치: Inbound processing** — 브라우저의 Preflight(OPTIONS) 요청을 처리합니다.

```xml
<!-- Inbound processing에 추가 -->
<cors allow-credentials="false">
    <allowed-origins>
        <origin>https://your-app.azurewebsites.net</origin>
        <origin>http://localhost:3000</origin>
    </allowed-origins>
    <allowed-methods>
        <method>POST</method>
        <method>OPTIONS</method>
    </allowed-methods>
    <allowed-headers>
        <header>Content-Type</header>
        <header>Ocp-Apim-Subscription-Key</header>
        <header>Authorization</header>
    </allowed-headers>
</cors>
```

> 💡 **왜 필요한가?**
> - 브라우저는 다른 도메인으로의 API 호출 전에 **OPTIONS Preflight** 요청을 보냄
> - CORS 정책이 없으면 브라우저가 요청을 차단함 (서버는 정상이지만 브라우저에서 에러)
> - `*`로 모든 오리진을 허용할 수 있지만, 프로덕션에서는 **구체적인 도메인만** 허용

### 7단계: validate-jwt (Azure AD / OAuth 인증)

Subscription Key 대신 **Azure AD 토큰(JWT)**으로 인증합니다. 앱 등록 기반 접근 제어가 가능합니다.

> **적용 위치: Inbound processing** — Subscription Key 대신 또는 추가로 JWT를 검증합니다.

```xml
<!-- Inbound processing에 추가 -->
<validate-jwt header-name="Authorization" failed-validation-httpcode="401">
    <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
    <audiences>
        <audience>api://{apim-app-client-id}</audience>
    </audiences>
    <issuers>
        <issuer>https://sts.windows.net/{tenant-id}/</issuer>
    </issuers>
    <required-claims>
        <claim name="roles" match="any">
            <value>AI.User</value>
            <value>AI.Admin</value>
        </claim>
    </required-claims>
</validate-jwt>
```

> 💡 **Subscription Key vs JWT 비교:**
>
> | | Subscription Key | validate-jwt |
> |---|---|---|
> | **인증 방식** | 정적 키 | Azure AD 토큰 (OAuth 2.0) |
> | **키 관리** | 수동 회전 필요 | 자동 (토큰 만료/갱신) |
> | **세분화** | Product/Subscription 단위 | 앱/사용자/역할(claim) 단위 |
> | **적합** | 내부 서비스, PoC | 프로덕션, 외부 파트너 |
>
> **사전 준비:**
> 1. Azure AD에 앱 등록 → Client ID, Tenant ID 확보
> 2. 앱 역할(App Role) 정의 (예: `AI.User`, `AI.Admin`)
> 3. API를 호출할 클라이언트 앱에 역할 부여

### 8단계: quota-by-key (월별 토큰 예산)

`azure-openai-token-limit`은 **분당** 제한이고, `quota-by-key`는 **일/월 총량** 제한입니다.

> **적용 위치: Inbound processing** — 요청 시점에 남은 예산을 확인합니다.

```xml
<!-- Inbound processing에 추가 (token-limit과 별개로 동작) -->
<quota-by-key
    calls="10000"
    bandwidth="0"
    renewal-period="2592000"
    counter-key="@(context.Subscription.Id)" />
```

> 💡 **rate-limit vs quota 차이:**
>
> | | `azure-openai-token-limit` | `quota-by-key` |
> |---|---|---|
> | **제한 단위** | 분당 토큰 수 (TPM) | 기간당 호출 수 또는 대역폭 |
> | **리셋** | 매분 자동 리셋 | `renewal-period` 경과 후 리셋 |
> | **용도** | 순간 폭증 방지 | 월 예산 관리, 차지백 |
> | **에러** | 429 (초 단위 대기) | 403 (갱신까지 차단) |
>
> **비즈니스 시나리오:**
> - "팀 A는 이번 달 API 호출 10,000건까지만 사용 가능"
> - "파트너 B는 일일 1,000건 제한"
>
> `renewal-period`는 초 단위입니다:
> - 일일: `86400`
> - 주간: `604800`
> - 월간: `2592000` (30일)

### 9단계: 전체 정책 조합

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
        <!--
            CORS (웹 프론트엔드 호출 시 필요)
            <cors allow-credentials="false">
                <allowed-origins><origin>https://your-app.azurewebsites.net</origin></allowed-origins>
                <allowed-methods><method>POST</method></allowed-methods>
                <allowed-headers><header>Content-Type</header><header>Authorization</header></allowed-headers>
            </cors>
        -->
        <!--
            JWT 인증 (Subscription Key 대신 Azure AD 토큰 사용 시)
            <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
                <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
                <audiences><audience>api://{client-id}</audience></audiences>
            </validate-jwt>
        -->
        <!--
            IP 필터 (필요 시 활성화)
            <ip-filter action="allow">
                <address-range from="10.0.0.0" to="10.0.0.255" />
            </ip-filter>
        -->
        <!--
            시맨틱 캐시 조회 (별도 배포 필요: ./scripts/deploy-semantic-caching.sh)
            <azure-openai-semantic-cache-lookup
                score-threshold="0.8"
                embeddings-backend-id="embedding-backend"
                embeddings-backend-auth="system-assigned" />
        -->
        <!-- 토큰 Rate Limiting -->
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
        <!--
            시맨틱 캐시 저장 (별도 배포 필요: ./scripts/deploy-semantic-caching.sh)
            <azure-openai-semantic-cache-store duration="3600" />
        -->
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
| `azure-openai-semantic-cache-lookup` | inbound | 시맨틱 캐시 조회 (별도 배포) |
| `azure-openai-semantic-cache-store` | outbound | 시맨틱 캐시 저장 (별도 배포) |

### 일반 APIM 정책 목록

| 정책 | 영역 | 용도 |
|------|------|------|
| `ip-filter` | inbound | IP 화이트/블랙리스트 |
| `cors` | inbound | 웹 프론트엔드 CORS 허용 |
| `validate-jwt` | inbound | Azure AD / OAuth 토큰 검증 |
| `quota-by-key` | inbound | 일/월 단위 호출 예산 제한 |
| `retry` | backend | 429/5xx 시 자동 재시도 |

### 일반 정책 vs AI 전용 정책

| 일반 정책 | AI 전용 정책 | 차이점 |
|----------|-------------|--------|
| `rate-limit` | `azure-openai-token-limit` | 요청 수 vs 토큰 수 |
| `cache-lookup` | `azure-openai-semantic-cache-lookup` | 정확한 매칭 vs 유사도 매칭 |
| `emit-metric` | `azure-openai-emit-token-metric` | 일반 메트릭 vs 토큰 메트릭 |

## 테스트 방법

### 노트북 테스트

Lab 4에는 정책 유형별로 별도 노트북이 준비되어 있습니다:

| 노트북 | 테스트 내용 | 사전 준비 |
|---|---|---|
| `test-token-limit.ipynb` | 토큰 Rate Limiting + 멀티 테넌트 할당량 | Product/Subscription 설정 (노트북 하단 가이드 참고) |
| `test-ip-filter.ipynb` | IP 필터링 + 인증/접근 제어 | 없음 (자동 적용/복원) |
| `test-cors-jwt.ipynb` | CORS Preflight + JWT 인증 | JWT: Azure AD 앱 등록 (선택, 없으면 스킵) |

#### test-token-limit.ipynb
Product 기반 제한과 API 레벨 조건부 정책을 모두 실습합니다:

**실습 A**: 요청 수 기반 제한 (`rate-limit`, Product 레벨, 5회/분)
**실습 B**: 토큰 기반 제한 (`azure-openai-token-limit`, Product 레벨, 2,000 TPM)
**실습 C**: 조건부 정책 (`<choose>` + `rate-limit-by-key`, API 레벨) — `x-client-id` 헤더로 tieer별 차등 제한
**실습 D**: 조건부 LLM 토큰 제한 (`<choose>` + `llm-token-limit`, API 레벨) — 티어별 TPM 차등 적용

> ⚠️ 실습 A, B는 Product/Subscription을 먼저 설정해야 합니다 (노트북에서 자동 생성).
> 실습 C, D는 기존 Built-in Subscription Key로 테스트합니다.

#### test-ip-filter.ipynb
IP 필터 정책을 자동으로 적용/복원하며 테스트합니다:
1. **인증 없는 요청**: 401 응답 확인
2. **잘못된 키**: 401 응답 확인
3. **정상 요청**: 200 응답 확인
4. **존재하지 않는 모델**: 404 응답 확인
5. **IP 차단**: 현재 IP를 `ip-filter` 정책으로 차단 → 403 → 자동 복원

#### test-cors-jwt.ipynb
CORS와 JWT 인증 정책을 테스트합니다:
1. **CORS 미적용 상태**: OPTIONS Preflight 차단 확인
2. **CORS 적용**: 정책 자동 적용 → Preflight 성공 → 자동 복원
3. **비허용 Origin**: 허용 목록에 없는 Origin 차단 확인
4. **JWT 인증**: Azure AD 토큰 발급 및 검증 (선택사항, 앱 등록 필요)

## 다음 단계

→ [Lab 5: 멀티 모델 Gateway](../lab05-multi-model-gateway/README.md)
