targetScope = 'resourceGroup'

@description('배포 위치')
param location string = resourceGroup().location

@description('리소스 이름 접미사')
param suffix string = 'logbench-${utcNow('yyyyMMdd')}'

@description('APIM SKU (벤치마크 전용: StandardV2 고정)')
@allowed([
  'StandardV2'
])
param apimSku string = 'StandardV2'

@description('APIM 관리자 이메일')
param publisherEmail string

@description('APIM 게시자 이름')
param publisherName string = 'AI Gateway LogBench'

var apimName = 'apim-logbench-${suffix}'
var laName = 'log-logbench-${suffix}'
var aiName = 'appi-logbench-${suffix}'
var ehnsName = 'ehns-logbench-${suffix}'
var ehName = 'logbench'
var loadTestName = 'lt-logbench-${suffix}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: laName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource ehNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: ehnsName
  location: location
  // 테넌트 폴리시(EH SAS 비활성)를 우회하는 안전망 태그. 기본 로거는 MI 를 쓰므로
  // SAS 는 필수가 아니지만, 태그가 있으면 SAS 도 사용 가능(정책 통과).
  tags: {
    SecurityControl: 'Ignore'
  }
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ehNamespace
  name: ehName
  properties: {
    messageRetentionInDays: 1
    partitionCount: 4
  }
}

// APIM System MI 가 Event Hub 로 Send 하도록 RBAC 부여 (SAS 비활성 테넌트 대응).
// SAS 연결문자열 로거는 disableLocalAuth=true 환경에서 배포가 거부되므로 사용하지 않는다.
var ehDataSenderRoleId = '2b629674-e913-4c01-ae53-ef4638d8f975' // Azure Event Hubs Data Sender
resource ehSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(ehNamespace.id, apimService.id, ehDataSenderRoleId)
  scope: ehNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ehDataSenderRoleId)
    principalId: apimService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: apimSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

resource apimAiLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
    }
    isBuffered: true
    resourceId: appInsights.id
  }
}

// ⚠️ Event Hub 로거(logbench-eh)는 bicep 이 아니라 scripts/deploy-logbench.sh 가
// 배포 후 Managed Identity 방식으로 생성한다. 이유: (1) 테넌트가 EH SAS 를 비활성화하면
// 연결문자열 로거 배포가 실패하고, (2) MI 로거는 위 ehSenderRole RBAC 전파(수십 초)를
// 기다려야 검증을 통과하므로 재시도 루프가 필요하다.

// 중립 자(ruler): GatewayLogs → Log Analytics, 전 구성 상시 ON
// resource-specific(Dedicated) 모드여야 ApiManagementGatewayLogs 테이블에 TotalTime/
// BackendTime 이 채워진다(기본 AzureDiagnostics 에는 타이밍 컬럼이 없음).
resource apimDiagSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'gatewaylogs-to-la'
  scope: apimService
  properties: {
    workspaceId: logAnalytics.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
  }
}

resource loadTest 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: loadTestName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

output apimName string = apimService.name
output apimGatewayUrl string = apimService.properties.gatewayUrl
output eventHubNamespace string = ehNamespace.name
output eventHubName string = ehName
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output loadTestName string = loadTest.name
output appInsightsName string = appInsights.name
