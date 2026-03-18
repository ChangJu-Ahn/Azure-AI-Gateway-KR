# Lab 6: 모니터링 & 로깅

AI Gateway의 토큰 사용량, 성능, 에러를 모니터링하고 대시보드와 알림을 구성합니다.

## 목표

- APIM 내장 Analytics vs Application Insights 차이 이해
- Application Insights 연동
- 토큰 사용량 메트릭 대시보드 구성
- KQL 기반 로그 분석
- 알림 규칙 설정
- 비즈니스 시나리오별 모니터링 전략 수립

## APIM 내장 Analytics vs Application Insights

APIM에는 두 가지 모니터링 옵션이 있습니다. 목적에 따라 선택하거나 병행합니다.

### 기능 비교

| | APIM 내장 Analytics | Application Insights |
|---|---|---|
| **접근** | Portal → APIM → **Analytics** | Portal → **Application Insights** (별도 리소스) |
| **추가 비용** | APIM에 포함 (무료) | 데이터 수집량 기반 과금 |
| **설정** | 없음 (자동) | Logger + Diagnostics 연동 필요 |
| **기본 대시보드** | 요청 수, 에러율, 응답시간, 지역별/API별 | 같은 것 + 커스텀 대시보드 |
| **토큰 메트릭** | ❌ | ✅ `azure-openai-emit-token-metric` 정책 |
| **모델별 TPM** | ❌ | ✅ KQL로 차원별 분석 |
| **요청/응답 Body** | ❌ | ✅ Diagnostics 설정 |
| **End-to-End 추적** | ❌ 제한적 | ✅ `operation_Id`로 프론트→백엔드 조인 |
| **커스텀 대시보드** | ❌ 고정 UI만 | ✅ Azure Workbook, Grafana 연동 |
| **알림 규칙** | ❌ | ✅ Alert Rules 설정 |
| **데이터 보존** | 최근 데이터만 | 30~730일 설정 가능 |
| **KQL 쿼리** | ❌ | ✅ 자유로운 분석 |

### APIM 내장 Analytics로 볼 수 있는 것

Portal → APIM → **Analytics** 블레이드에서 코드 없이 바로 확인 가능합니다:

- **Timeline**: 시간대별 요청 수, 에러 수 추이
- **Geography**: 클라이언트 IP 기반 지역별 호출 분포
- **APIs**: API별 호출 횟수, 평균 응답시간, 에러율
- **Operations**: Operation별 상세 통계
- **Products**: Product별 사용량 (멀티 테넌트 시)
- **Subscriptions**: Subscription Key별 호출 통계
- **Users**: 사용자별 사용량

> 💡 "전체 요청이 몇 개인지, 에러가 얼마나 나는지" 수준의 **빠른 상태 점검**에 적합합니다.
> 별도 설정 없이 바로 쓸 수 있다는 것이 최대 장점입니다.

### Application Insights가 필요한 이유

AI Gateway에서는 **일반 API와 다른 메트릭**이 필요합니다:

| 일반 API 모니터링 | AI Gateway 모니터링 |
|---|---|
| 요청 수, 에러율 | **토큰 사용량** (비용의 핵심) |
| 응답 시간 | **모델별 × 백엔드별 TPM** (할당량 관리) |
| HTTP 상태 코드 | **팀/구독별 토큰 소비량** (차지백) |
| — | **프롬프트/응답 Body** (품질 분석, 환각 감지) |
| — | **캐시 히트율** (비용 절감 효과 측정) |

이런 AI 특화 메트릭은 APIM Analytics에서 볼 수 **없으며**, Application Insights + 정책 조합이 필수입니다.

### 비즈니스 시나리오별 모니터링 전략

#### 시나리오 1: "AI 인프라 비용을 팀별로 차지백하고 싶다"

> **필요:** Application Insights + `azure-openai-emit-token-metric` 정책

팀(Subscription)별 토큰 소비량을 수집하고, 모델별 단가를 곱해 비용을 산출합니다.

```
수집: emit-token-metric → Subscription ID 차원 포함
분석: KQL로 구독별 × 모델별 토큰 합산 → 단가 매핑
결과: "팀 A는 이번 달 gpt-4o에 $150, gpt-4.1-nano에 $30 사용"
```

APIM Analytics로는 "팀 A가 몇 번 호출했는지"만 알 수 있고, **토큰 단위 비용**은 알 수 없습니다.

#### 시나리오 2: "429 에러가 급증하면 즉시 알림을 받고 싶다"

> **필요:** Application Insights + Alert Rules

```
수집: App Insights requests 테이블에서 resultCode == 429 추적
알림: 5분 내 429가 10건 초과 → Teams/Slack/이메일 발송
대응: 백엔드 풀 weight 조정 또는 추가 리전 투입
```

APIM Analytics에서는 "429가 몇 건 있었는지" 사후 확인만 가능하고, **실시간 알림은 불가**합니다.

#### 시나리오 3: "응답 품질을 모니터링하고 싶다 (환각 감지)"

> **필요:** Application Insights + Diagnostics Body 로깅

```
수집: frontend/backend response body를 App Insights에 저장
분석: KQL로 응답 본문 패턴 분석, 외부 평가 시스템 연동
결과: "특정 프롬프트 패턴에서 환각 응답 비율이 12%"
```

APIM Analytics에서는 요청/응답 **본문을 전혀 볼 수 없습니다.**

#### 시나리오 4: "백엔드별 TPM을 실시간 추적하여 할당량 소진 전에 대응하고 싶다"

> **필요:** Application Insights + `emit-token-metric` (Backend 차원 필수)

```
수집: emit-token-metric → Backend 차원 포함
분석: KQL로 백엔드별 분당 토큰 합산 (TPM)
알림: 특정 백엔드 TPM이 할당량 80% 도달 시 알림
대응: weight 낮추기 또는 Circuit Breaker tripDuration 조정
```

#### 시나리오 5: "빠른 상태 점검만 하면 된다"

> **필요:** APIM 내장 Analytics만으로 충분

```
확인: Portal → APIM → Analytics 열기
결과: "오늘 요청 5,000건, 에러율 0.3%, 평균 응답 1.2초" 즉시 확인
```

설정 없이 바로 볼 수 있으므로, 일상 모니터링이나 간단한 보고에 활용합니다.

### 결론: 어떤 걸 써야 하나?

| 상황 | 권장 |
|------|------|
| 개발/테스트 중 빠른 확인 | APIM Analytics |
| 토큰 비용 추적, 차지백 | App Insights 필수 |
| 실시간 알림 (429, 지연 급증) | App Insights 필수 |
| 응답 품질 분석, 디버깅 | App Insights 필수 |
| 프로덕션 운영 | **둘 다 병행** (Analytics로 빠른 확인 + App Insights로 심층 분석) |

> 이 실습에서는 `deploy.sh`가 Application Insights를 **자동으로 배포하고 APIM에 연결**합니다.
> 아래 단계에서는 정책을 추가하여 AI Gateway 특화 메트릭을 수집합니다.

## 실습 단계

### 1단계: Application Insights 연동

```bicep
// infra/modules/monitoring.bicep

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-ai-gateway'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-ai-gateway'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}
```

APIM에 Application Insights Logger 연결:

```bicep
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
    }
    isBuffered: true
  }
}

resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-09-01-preview' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    logClientIp: true
  }
}
```

### 2단계: 토큰 메트릭 수집 정책

1. Azure Portal → APIM → **APIs** → **Azure OpenAI** → **All operations**
2. **Inbound processing** 영역의 **</>** 클릭 (Code View — 전체 XML 편집)
3. `<outbound>` 섹션에 아래 정책을 추가 후 **Save**

> **적용 위치: Outbound processing** — 백엔드 응답에서 토큰 사용량을 추출하여 Application Insights로 전송합니다.

```xml
<!-- Outbound processing에 추가 -->
<outbound>
    <base />
    <azure-openai-emit-token-metric namespace="ai-gateway-metrics">
        <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
        <dimension name="Client IP" value="@(context.Request.IpAddress)" />
        <dimension name="API ID" value="@(context.Api.Id)" />
        <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
        <dimension name="Backend" value="@(context.Request.Url.Host)" />
    </azure-openai-emit-token-metric>

    <!-- 커스텀 메트릭: 응답 시간 -->
    <emit-metric name="ai-gateway-latency" namespace="ai-gateway-metrics">
        <dimension name="API" value="@(context.Api.Name)" />
        <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
        <dimension name="Backend" value="@(context.Request.Url.Host)" />
        <dimension name="Status" value="@(context.Response.StatusCode.ToString())" />
        <value>@(context.Elapsed.TotalMilliseconds)</value>
    </emit-metric>
</outbound>
```

> **핵심:** `Backend` 차원을 반드시 포함해야 각 AOAI 인스턴스별 TPM을 정확히 추적할 수 있습니다.

### 2-1단계: 프론트엔드/백엔드 요청·응답 로깅

APIM Diagnostics에 프론트엔드/백엔드의 request/response body 로깅을 활성화합니다:

```bicep
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-09-01-preview' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: { percentage: 100, samplingType: 'fixed' }
    logClientIp: true
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    frontend: {
      request: {
        headers: [ 'Content-Type', 'Ocp-Apim-Subscription-Key', 'x-model-provider' ]
        body: { bytes: 4096 }
      }
      response: {
        headers: [ 'Content-Type', 'x-ratelimit-remaining-tokens' ]
        body: { bytes: 4096 }
      }
    }
    backend: {
      request: {
        headers: [ 'Content-Type', 'Authorization' ]
        body: { bytes: 4096 }
      }
      response: {
        headers: [ 'Content-Type', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
        body: { bytes: 4096 }
      }
    }
  }
}
```

이 설정 후 App Insights에서 확인 가능한 데이터:

| App Insights 테이블 | 내용 |
|----------------------|------|
| `requests` | 프론트엔드 (클라이언트 → APIM) 요청/응답 + Body |
| `dependencies` | 백엔드 (APIM → Azure OpenAI) 요청/응답 + Body |
| `customMetrics` | 토큰 메트릭 (Model, Backend 차원 포함) |

### 3단계: KQL 로그 쿼리

**모델별·백엔드별 토큰 사용량:**

```kql
customMetrics
| where name startswith "ai-gateway-metrics"
| where timestamp > ago(24h)
| extend model = tostring(customDimensions["Model"])
| extend backend = tostring(customDimensions["Backend"])
| summarize
    totalTokens = sum(value),
    avgTokens = avg(value),
    callCount = count()
    by model, backend, bin(timestamp, 1h)
| order by timestamp desc
```

**모델별·백엔드별 TPM (분당 토큰) — 핵심 쿼리:**

```kql
customMetrics
| where name startswith "ai-gateway-metrics"
| where timestamp > ago(1h)
| extend model = tostring(customDimensions["Model"])
| extend backend = tostring(customDimensions["Backend"])
| summarize TPM = sum(value) by model, backend, bin(timestamp, 1m)
| order by timestamp desc
| render timechart
```

**AOAI 인스턴스별 TPM 피벗 테이블:**

```kql
customMetrics
| where name startswith "ai-gateway-metrics"
| where timestamp > ago(1h)
| extend model = tostring(customDimensions["Model"])
| extend backend = tostring(customDimensions["Backend"])
| summarize TPM = sum(value) by model, backend, bin(timestamp, 1m)
| evaluate pivot(backend, sum(TPM))
| order by timestamp desc
```

**429 에러 (Rate Limit) 발생 추이:**

```kql
requests
| where timestamp > ago(24h)
| where resultCode == "429"
| summarize count() by bin(timestamp, 5m)
| render timechart
```

**백엔드별 응답 시간 분포:**

```kql
dependencies
| where timestamp > ago(1h)
| extend backend = tostring(target)
| summarize
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99)
    by backend
```

**프론트엔드 요청/응답 로그 확인:**

```kql
requests
| where timestamp > ago(1h)
| project 
    timestamp,
    name,
    resultCode,
    duration,
    client_IP,
    requestBody = tostring(customDimensions["Request-Body"]),
    responseBody = tostring(customDimensions["Response-Body"])
| order by timestamp desc
```

**백엔드 호출 로그 확인 (APIM → Azure OpenAI):**

```kql
dependencies
| where timestamp > ago(1h)
| project
    timestamp,
    target,
    resultCode,
    duration,
    requestBody = tostring(customDimensions["Request-Body"]),
    responseBody = tostring(customDimensions["Response-Body"])
| order by timestamp desc
```

**End-to-End 트랜잭션 추적 (프론트엔드 → 백엔드 조인):**

```kql
requests
| where timestamp > ago(1h)
| project 
    timestamp, operation_Id,
    frontend_url = url,
    frontend_status = resultCode,
    frontend_duration = duration
| join kind=inner (
    dependencies
    | where timestamp > ago(1h)
    | project
        operation_Id,
        backend_target = target,
        backend_status = resultCode,
        backend_duration = duration
) on operation_Id
| extend overhead_ms = frontend_duration - backend_duration
| order by timestamp desc
```

**구독별 일일 비용 추정:**

```kql
customMetrics
| where name startswith "ai-gateway-metrics"
| where timestamp > ago(1d)
| extend subscriptionId = tostring(customDimensions["Subscription ID"])
| extend model = tostring(customDimensions["Model"])
| summarize totalTokens = sum(value) by subscriptionId, model
| extend estimatedCost = case(
    model == "gpt-4o", totalTokens * 0.000005,
    model == "gpt-4.1-nano", totalTokens * 0.00000015,
    totalTokens * 0.000002
)
```

### 4단계: 알림 규칙 설정

```bicep
resource tokenAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-token-usage'
  location: 'global'
  properties: {
    description: '토큰 사용량이 임계치를 초과했습니다'
    severity: 2
    enabled: true
    scopes: [apimService.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          name: 'HighTokenUsage'
          metricNamespace: 'ai-gateway-metrics'
          metricName: 'Total Tokens'
          operator: 'GreaterThan'
          threshold: 100000
          timeAggregation: 'Total'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
  }
}
```

## 핵심 개념

### 모니터링 항목 체크리스트

| 항목 | 메트릭 | App Insights 테이블 | 목적 |
|------|--------|---------------------|------|
| 토큰 사용량 | Prompt/Completion Tokens | `customMetrics` | 비용 추적 |
| 모델별·백엔드별 TPM | TPM by Model × Backend | `customMetrics` | AOAI 할당량 관리 |
| 응답 시간 | P50, P95, P99 Latency | `dependencies` | 성능 모니터링 |
| 에러율 | 429, 500 Count | `requests` | 안정성 확인 |
| 캐시 히트율 | Cache Hit/Miss | `customMetrics` | 비용 절감 효과 |
| 백엔드 상태 | Circuit Breaker 상태 | `dependencies` | 가용성 확인 |
| 프론트엔드 요청/응답 | Request/Response Body | `requests` | 디버깅 |
| 백엔드 요청/응답 | Request/Response Body | `dependencies` | 디버깅 |
| End-to-End 추적 | Frontend → Backend 조인 | `requests` + `dependencies` | 지연 원인 분석 |

## 테스트 노트북

- **test-performance.ipynb** — 동시 부하 및 성능 측정
- **test-monitoring.ipynb** — 토큰/TPM 모니터링 + 프론트엔드/백엔드 로그 확인 종합 테스트

## 다음 단계

→ [Lab 7: 고급 패턴](../lab07-advanced-patterns/README.md)
