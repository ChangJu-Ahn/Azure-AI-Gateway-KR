@description('Azure OpenAI 리소스 이름')
param name string

@description('배포 위치')
param location string

@description('모델 배포 용량 (1K TPM 단위). 실습용으로 낮게 설정하면 429 테스트가 쉬워집니다.')
param modelCapacity int = 5

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
  }
}

resource gpt41NanoDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: 'gpt-4.1-nano'
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1-nano'
      version: '2025-04-14'
    }
  }
}

output endpoint string = openai.properties.endpoint
output resourceId string = openai.id
output name string = openai.name
