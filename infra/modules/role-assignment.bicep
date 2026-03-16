@description('Azure OpenAI 리소스 이름')
param openaiAccountName string

@description('APIM Managed Identity의 Principal ID')
param principalId string

@description('Cognitive Services OpenAI User 역할 ID')
var cognitiveServicesOpenAIUserRole = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource openaiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openaiAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, openaiAccount.id, cognitiveServicesOpenAIUserRole)
  scope: openaiAccount
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRole)
    principalType: 'ServicePrincipal'
  }
}
