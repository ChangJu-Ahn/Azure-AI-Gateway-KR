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

resource ehSendAuth 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: eventHub
  name: 'apim-send'
  properties: {
    rights: [ 'Send', 'Listen' ]
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

resource apimEhLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'logbench-eh'
  properties: {
    loggerType: 'azureEventHub'
    credentials: {
      name: ehName
      connectionString: listKeys(ehSendAuth.id, ehSendAuth.apiVersion).primaryConnectionString
    }
    isBuffered: true
  }
}

// 중립 자(ruler): GatewayLogs → Log Analytics, 전 구성 상시 ON
resource apimDiagSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'gatewaylogs-to-la'
  scope: apimService
  properties: {
    workspaceId: logAnalytics.id
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
