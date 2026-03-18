# Lab 7: 고급 패턴

프로덕션 환경에서 활용할 수 있는 고급 AI Gateway 패턴을 실습합니다.

## 목표

- A/B 테스트 라우팅
- Azure Content Safety 연계
- SSE 스트리밍 지원
- PTU vs PayGo 밸런싱

## 실습 시나리오

### 시나리오 1: A/B 테스트 라우팅

트래픽의 일부를 새 모델 버전으로 라우팅하여 성능을 비교합니다.

> **적용 위치: Inbound processing** — 요청이 들어올 때 랜덤으로 라우팅 대상을 결정합니다.

```xml
<!-- Inbound processing에 적용 -->
<inbound>
    <base />
    <!-- 10%의 트래픽을 새 모델로 라우팅 -->
    <set-variable name="routingRandom" value="@(new Random().Next(100))" />
    <choose>
        <when condition="@((int)context.Variables["routingRandom"] < 10)">
            <!-- 10%: 새 모델 (GPT-4o latest) -->
            <set-backend-service base-url="https://aoai-eus-<suffix>.openai.azure.com/openai" />
            <rewrite-uri template="/deployments/gpt-4o-latest/chat/completions" />
            <set-header name="x-ab-group" exists-action="override">
                <value>experiment</value>
            </set-header>
        </when>
        <otherwise>
            <!-- 90%: 기존 모델 -->
            <set-backend-service backend-id="openai-backend-pool" />
            <set-header name="x-ab-group" exists-action="override">
                <value>control</value>
            </set-header>
        </otherwise>
    </choose>
</inbound>
```

### 시나리오 2: Content Safety 연계

Azure Content Safety를 활용하여 유해 콘텐츠를 필터링합니다.

> **적용 위치: Inbound processing** — 백엔드 호출 전에 Content Safety API로 입력을 검사합니다.

```xml
<!-- Inbound processing에 적용 -->
<inbound>
    <base />
    <!-- 1. Content Safety로 입력 검사 -->
    <send-request mode="new" response-variable-name="safetyResponse" timeout="10">
        <set-url>https://<content-safety>.cognitiveservices.azure.com/contentsafety/text:analyze?api-version=2024-09-01</set-url>
        <set-method>POST</set-method>
        <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
        </set-header>
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
        <set-body>@{
            var body = context.Request.Body.As<JObject>(preserveContent: true);
            var lastMessage = ((JArray)body["messages"]).Last["content"].ToString();
            return new JObject(
                new JProperty("text", lastMessage),
                new JProperty("categories", new JArray("Hate", "Violence", "SelfHarm", "Sexual"))
            ).ToString();
        }</set-body>
    </send-request>

    <!-- 2. 위험 콘텐츠 차단 -->
    <choose>
        <when condition="@{
            var result = ((IResponse)context.Variables["safetyResponse"]).Body.As<JObject>();
            var categories = result["categoriesAnalysis"] as JArray;
            return categories.Any(c => (int)c["severity"] >= 4);
        }">
            <return-response>
                <set-status code="400" reason="Content Safety Violation" />
                <set-body>{"error": {"message": "입력 내용이 콘텐츠 안전 정책을 위반합니다.", "code": "content_filter"}}</set-body>
            </return-response>
        </when>
    </choose>
</inbound>
```

### 시나리오 3: SSE 스트리밍 지원

Server-Sent Events 기반 스트리밍 응답을 처리합니다.

> **적용 위치: Inbound + Backend + Outbound 모두 필요**
> - `set-variable`는 **Inbound** — 스트리밍 요청인지 감지
> - `forward-request`는 **Backend** — 버퍼링 비활성화로 스트리밍 전달
> - `choose`는 **Outbound** — 스트리밍이 아닌 경우에만 메트릭 수집

```xml
<!-- Inbound processing -->
<inbound>
    <base />
    <!-- 스트리밍 요청 감지 -->
    <set-variable name="isStreaming" value="@{
        var body = context.Request.Body.As<JObject>(preserveContent: true);
        return body["stream"]?.Value<bool>() == true;
    }" />
</inbound>
<backend>
    <forward-request timeout="120" buffer-response="false" />
</backend>
<outbound>
    <base />
    <!-- 스트리밍이 아닌 경우에만 토큰 메트릭 수집 -->
    <choose>
        <when condition="@(!((bool)context.Variables["isStreaming"]))">
            <azure-openai-emit-token-metric namespace="ai-gateway-metrics">
                <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
            </azure-openai-emit-token-metric>
        </when>
    </choose>
</outbound>
```

### 시나리오 4: PTU vs PayGo 밸런싱

Provisioned Throughput Unit(PTU)를 우선 사용하고, 초과 시 PayGo로 Spillover합니다.

```bicep
// PTU 백엔드 (Priority 1)
resource ptuBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'aoai-ptu'
  properties: {
    url: 'https://aoai-ptu-001.openai.azure.com/openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [{
        failureCondition: {
          count: 1
          statusCodeRanges: [{ min: 429, max: 429 }]
          interval: 'PT10S'
        }
        name: 'ptuThrottleBreaker'
        tripDuration: 'PT60S'
        acceptRetryAfter: true
      }]
    }
  }
}

// PayGo 백엔드 (Priority 2 - Spillover)
resource paygoPool 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-ptu-paygo-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        { id: '/backends/aoai-ptu',    priority: 1, weight: 1 }
        { id: '/backends/aoai-paygo',  priority: 2, weight: 1 }
      ]
    }
  }
}
```

## 핵심 개념

### 프로덕션 체크리스트

- [ ] 모든 백엔드에 Managed Identity 인증 적용
- [ ] Circuit Breaker + Backend Pool 조합으로 장애 대응
- [ ] 토큰 Rate Limiting으로 비용 제어
- [ ] Application Insights로 메트릭/로그 수집
- [ ] Content Safety로 유해 콘텐츠 필터링
- [ ] PTU + PayGo 밸런싱으로 비용 최적화
- [ ] 스트리밍 지원 (buffer-response="false")

## 완료!

모든 Lab을 완료하셨습니다. 이 레포지토리의 패턴을 활용하여 프로덕션 AI Gateway를 구축해 보세요.

## 테스트 방법

### VS Code REST Client

`scripts/test-endpoints.http`의 `Lab 7` 섹션 참조

→ [Lab 8: 리소스 정리](../lab08-cleanup/README.md) | [메인 README로 돌아가기](../../README.md)
