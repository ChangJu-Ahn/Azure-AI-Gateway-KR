@description('APIM 인스턴스 이름')
param name string

@description('배포 위치')
param location string

@description('APIM SKU')
param sku string

@description('관리자 이메일')
param publisherEmail string

@description('게시자 이름')
param publisherName string

@description('Application Insights 리소스 ID')
param appInsightsId string

@description('Application Insights Instrumentation Key')
param appInsightsInstrumentationKey string

@description('Azure OpenAI East US 엔드포인트')
param openaiEastUsEndpoint string

@description('Azure OpenAI Sweden Central 엔드포인트')
param openaiSwedenEndpoint string

@description('Azure OpenAI West US 엔드포인트')
param openaiWestUsEndpoint string

// ─── APIM Service ───
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: name
  location: location
  sku: {
    name: sku
    capacity: sku == 'Consumption' ? 0 : 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ─── Application Insights Logger ───
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
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
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    frontend: {
      request: {
        headers: [ 'Content-Type', 'Ocp-Apim-Subscription-Key', 'x-model-provider' ]
        body: {
          bytes: 4096
        }
      }
      response: {
        headers: [ 'Content-Type', 'x-ratelimit-remaining-tokens' ]
        body: {
          bytes: 4096
        }
      }
    }
    backend: {
      request: {
        headers: [ 'Content-Type', 'Authorization' ]
        body: {
          bytes: 4096
        }
      }
      response: {
        headers: [ 'Content-Type', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
        body: {
          bytes: 4096
        }
      }
    }
  }
}

// ─── Backends ───
resource backendEastUs 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'aoai-eastus'
  properties: {
    url: '${openaiEastUsEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 1
            errorReasons: ['Server errors']
            interval: 'PT1S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 503 }
            ]
          }
          name: 'openAiCircuitBreaker'
          tripDuration: 'PT30S'
          acceptRetryAfter: false
        }
      ]
    }
  }
}

resource backendSweden 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'aoai-swedencentral'
  properties: {
    url: '${openaiSwedenEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 1
            errorReasons: ['Server errors']
            interval: 'PT1S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 503 }
            ]
          }
          name: 'openAiCircuitBreaker'
          tripDuration: 'PT30S'
          acceptRetryAfter: false
        }
      ]
    }
  }
}

resource backendWestUs 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'aoai-westus'
  properties: {
    url: '${openaiWestUsEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 1
            errorReasons: ['Server errors']
            interval: 'PT1S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 503 }
            ]
          }
          name: 'openAiCircuitBreaker'
          tripDuration: 'PT30S'
          acceptRetryAfter: false
        }
      ]
    }
  }
}

// ─── Backend Pool ───
resource backendPool 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-backend-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${backendEastUs.name}'
          priority: 1
          weight: 1
        }
        {
          id: '/backends/${backendSweden.name}'
          priority: 1
          weight: 1
        }
        {
          id: '/backends/${backendWestUs.name}'
          priority: 1
          weight: 1
        }
      ]
    }
  }
}

// ─── Outputs ───
output gatewayUrl string = apimService.properties.gatewayUrl
output name string = apimService.name
output principalId string = apimService.identity.principalId
