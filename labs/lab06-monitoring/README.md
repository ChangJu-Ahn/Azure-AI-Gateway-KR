# Lab 6: 모니터링 & 로깅

AI Gateway의 토큰 사용량, 성능, 에러를 모니터링하고 대시보드와 알림을 구성합니다.

## 목표

- Application Insights 연동
- 토큰 사용량 메트릭 대시보드 구성
- KQL 기반 로그 분석
- 알림 규칙 설정

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
