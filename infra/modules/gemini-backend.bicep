@description('Gemini 백엔드 URL')
param geminiBackendUrl string = 'https://generativelanguage.googleapis.com/v1beta'

@description('APIM 서비스 이름')
param apimServiceName string

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimServiceName
}

resource geminiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'gemini-backend'
  properties: {
    url: geminiBackendUrl
    protocol: 'http'
  }
}

output backendId string = geminiBackend.id
