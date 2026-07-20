@description('Azure AI Content Safety 리소스 이름')
param contentSafetyName string

@description('APIM Managed Identity의 Principal ID')
param principalId string

// llm-content-safety 정책이 Managed Identity로 Content Safety analyze API를 호출하려면
// APIM MI에 'Cognitive Services User' 역할이 필요합니다.
var cognitiveServicesUserRole = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: contentSafetyName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, contentSafety.id, cognitiveServicesUserRole)
  scope: contentSafety
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRole)
    principalType: 'ServicePrincipal'
  }
}
