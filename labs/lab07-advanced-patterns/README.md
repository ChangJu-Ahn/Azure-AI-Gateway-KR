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

### 시나리오 2: Content Safety 연계 + 한국형 PII 커스텀 필터링 ✅ 실행 가능

Azure AI Content Safety를 활용하여 **유해 콘텐츠 + 프롬프트 공격(jailbreak) + 대한민국 PII**(주민등록번호·휴대폰번호·주소)를 게이트웨이에서 차단합니다.

> ℹ️ **이 시나리오는 최초 배포(`./scripts/deploy.sh`)에 포함되어 함께 배포됩니다.**
> - Content Safety 리소스 `acs-<suffix>` ([infra/modules/content-safety.bicep](../../infra/modules/content-safety.bicep))
> - 커스텀 컨텐츠 필터링용 **RAI 블록리스트 `korea-pii`** + 한국형 PII 정규식 항목
> - APIM MI → `Cognitive Services User` 역할 ([infra/modules/content-safety-role.bicep](../../infra/modules/content-safety-role.bicep))
> - `content-safety-backend`(Managed Identity 인증) 백엔드
>
> 정책 적용/검증은 **[test-content-safety-pii.ipynb](test-content-safety-pii.ipynb)** 노트북에서 수행합니다.

> **적용 위치: Inbound processing** — 백엔드 LLM 호출 전에 Content Safety로 입력을 검사합니다.

```xml
<!-- Inbound processing에 적용 (fragment: policies/fragments/llm-content-safety.xml) -->
<inbound>
    <base />
    <llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
        <categories output-type="EightSeverityLevels">
            <category name="Hate" threshold="4" />
            <category name="Violence" threshold="4" />
            <category name="SelfHarm" threshold="4" />
            <category name="Sexual" threshold="4" />
        </categories>
        <!-- 커스텀 컨텐츠 필터링: 한국형 PII 정규식 블록리스트 -->
        <blocklists>
            <id>korea-pii</id>
        </blocklists>
    </llm-content-safety>
    <!-- 이후 백엔드 풀 라우팅 -->
    <set-backend-service backend-id="openai-backend-pool" />
</inbound>
```

#### 커스텀 blocklist는 어떻게 한국형 PII를 막나?

`llm-content-safety`의 `<blocklists>`가 참조하는 것은 텍스트 모더레이션 blocklist가 아니라
Content Safety의 **RAI 블록리스트(raiBlocklists)** 이며, **정규식(`isRegex`)을 지원**합니다.
따라서 아래 항목을 Bicep으로 배포해 두면 프롬프트에 해당 패턴이 있을 때 **403**으로 차단됩니다.

| 항목 | 정규식 | 예시 |
|---|---|---|
| 주민등록번호 | `\d{6}-[1-4]\d{6}` | `900101-1234567` |
| 휴대폰번호 | `01[016-9][-\s]?\d{3,4}[-\s]?\d{4}` | `010-1234-5678` |
| 주소(휴리스틱) | `[가-힣]{2,}(로\|길)\s?\d{1,4}(번길\|번지\|호)?` | `테헤란로 152` |

> ⚠️ **주소 차단은 본질적으로 오탐/미탐이 큽니다.** 데모용 휴리스틱이며, 운영에서는 Azure AI Language의
> PII 개체 인식으로 보완하거나 `address` 항목을 제거하세요 (patterns은 [content-safety.bicep](../../infra/modules/content-safety.bicep)에서 조정).

> 💡 **디폴트에 없는 이유**: Content Safety 기본 카테고리는 Hate/Violence/SelfHarm/Sexual 4종뿐이라
> 주민등록번호 같은 **한국 특화 PII는 기본 제공되지 않습니다.** 그래서 커스텀 blocklist로 직접 정의합니다.

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

### Jupyter 노트북 (실행 가능)

- **[test-content-safety-pii.ipynb](test-content-safety-pii.ipynb)** — Content Safety + 한국형 PII 커스텀 필터링을 실제 배포/검증
  (정상 프롬프트 통과 vs 주민번호/휴대폰/주소 포함 프롬프트 403 차단)

### VS Code REST Client

`scripts/test-endpoints.http`의 `Lab 7` 섹션 참조

→ [Lab 8: 멀티 클라우드 통합 게이트웨이](../lab08-multicloud-gateway/README.md) | [메인 README로 돌아가기](../../README.md)
