targetScope = 'resourceGroup'

@description('리소스 배포 위치')
param location string = resourceGroup().location

@description('리소스 이름 접미사. deploy.sh 사용 시 오늘 날짜로 자동 생성됩니다(aigateway-YYYYMMDD). 직접 배포하며 값을 지정하지 않으면 배포 시점 UTC 날짜로 기본 생성됩니다.')
param suffix string = 'aigateway-${utcNow('yyyyMMdd')}'

@description('APIM SKU (Developer, StandardV2, Consumption)')
param apimSku string = 'Developer'

@description('APIM 관리자 이메일')
param publisherEmail string

@description('APIM 게시자 이름')
param publisherName string = 'AI Gateway Lab'

@description('Azure AI Content Safety 배포 리전. Content Safety 지원 리전을 사용하세요(koreacentral 미지원 가능).')
param contentSafetyLocation string = 'eastus'

// ─── 리소스 이름 (suffix 기반 자동 생성) ───
var apimName = 'apim-ai-gw-${suffix}'
var aoaiEastUsName = 'aoai-eus-${suffix}'
var aoaiSwedenName = 'aoai-swe-${suffix}'
var aoaiWestUsName = 'aoai-wus-${suffix}'
var contentSafetyName = 'acs-${suffix}'

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

// ─── Azure AI Content Safety (커스텀 컨텐츠 필터링 + 한국형 PII 차단) ───
module contentSafety 'modules/content-safety.bicep' = {
  name: 'content-safety'
  params: {
    name: contentSafetyName
    location: contentSafetyLocation
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
    contentSafetyEndpoint: contentSafety.outputs.endpoint
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

// ─── Role Assignment (APIM → Content Safety, Cognitive Services User) ───
module roleContentSafety 'modules/content-safety-role.bicep' = {
  name: 'role-content-safety'
  params: {
    contentSafetyName: contentSafety.outputs.name
    principalId: apim.outputs.principalId
  }
}

// ─── Outputs ───
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimName string = apim.outputs.name
output appInsightsName string = monitoring.outputs.appInsightsName
output contentSafetyName string = contentSafety.outputs.name
output contentSafetyEndpoint string = contentSafety.outputs.endpoint
output contentSafetyBlocklistName string = contentSafety.outputs.blocklistName
