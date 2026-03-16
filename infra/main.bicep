targetScope = 'resourceGroup'

@description('리소스 배포 위치')
param location string = resourceGroup().location

@description('리소스 이름 접미사 (예: 0316a). deploy.sh가 자동 생성합니다.')
param suffix string

@description('APIM SKU (Consumption, Developer, StandardV2)')
param apimSku string = 'Consumption'

@description('APIM 관리자 이메일')
param publisherEmail string

@description('APIM 게시자 이름')
param publisherName string = 'AI Gateway Lab'

// ─── 리소스 이름 (suffix 기반 자동 생성) ───
var apimName = 'apim-ai-gw-${suffix}'
var aoaiEastUsName = 'aoai-eus-${suffix}'
var aoaiSwedenName = 'aoai-swe-${suffix}'
var aoaiWestUsName = 'aoai-wus-${suffix}'

// ─── Monitoring ───
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    suffix: suffix
  }
}

// ─── Azure OpenAI ───
module openaiEastUs 'modules/openai.bicep' = {
  name: 'openai-eastus'
  params: {
    name: aoaiEastUsName
    location: 'eastus'
  }
}

module openaiSweden 'modules/openai.bicep' = {
  name: 'openai-sweden'
  params: {
    name: aoaiSwedenName
    location: 'swedencentral'
  }
}

module openaiWestUs 'modules/openai.bicep' = {
  name: 'openai-westus'
  params: {
    name: aoaiWestUsName
    location: 'westus'
  }
}

// ─── API Management ───
module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    name: apimName
    location: location
    sku: apimSku
    publisherEmail: publisherEmail
    publisherName: publisherName
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    openaiEastUsEndpoint: openaiEastUs.outputs.endpoint
    openaiSwedenEndpoint: openaiSweden.outputs.endpoint
    openaiWestUsEndpoint: openaiWestUs.outputs.endpoint
  }
}

// ─── Role Assignments (APIM → Azure OpenAI) ───
module roleEastUs 'modules/role-assignment.bicep' = {
  name: 'role-eastus'
  params: {
    openaiAccountName: openaiEastUs.outputs.name
    principalId: apim.outputs.principalId
  }
}

module roleSweden 'modules/role-assignment.bicep' = {
  name: 'role-sweden'
  params: {
    openaiAccountName: openaiSweden.outputs.name
    principalId: apim.outputs.principalId
  }
}

module roleWestUs 'modules/role-assignment.bicep' = {
  name: 'role-westus'
  params: {
    openaiAccountName: openaiWestUs.outputs.name
    principalId: apim.outputs.principalId
  }
}

// ─── Outputs ───
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimName string = apim.outputs.name
output appInsightsName string = monitoring.outputs.appInsightsName
