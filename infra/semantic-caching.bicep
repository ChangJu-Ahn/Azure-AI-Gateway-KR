targetScope = 'resourceGroup'

@description('리소스 배포 위치')
param location string = resourceGroup().location

@description('리소스 이름 접미사')
param suffix string

@description('임베딩 모델 배포 리전')
param embeddingLocation string = 'eastus'

@description('임베딩 모델 이름')
param embeddingModelName string = 'text-embedding-3-small'

@description('임베딩 모델 버전')
param embeddingModelVersion string = '1'

@description('Redis SKU (Basic, Standard, Premium)')
@allowed(['Basic', 'Standard', 'Premium'])
param redisSku string = 'Basic'

// ─── 리소스 이름 ───
var embeddingAccountName = 'aoai-emb-${suffix}'
var redisName = 'redis-ai-gw-${suffix}'
var apimName = 'apim-ai-gw-${suffix}'

// ─── Azure OpenAI (임베딩 전용) ───
resource embeddingAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: embeddingAccountName
  location: embeddingLocation
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: embeddingAccount
  name: embeddingModelName
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
  }
}

// ─── Azure Cache for Redis ───
resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: redisName
  location: location
  properties: {
    sku: {
      name: redisSku
      family: redisSku == 'Premium' ? 'P' : 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// ─── 기존 APIM 참조 ───
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// ─── APIM: 임베딩 백엔드 등록 ───
resource embeddingBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'embedding-backend'
  properties: {
    url: '${embeddingAccount.properties.endpoint}openai'
    protocol: 'http'
  }
}

// ─── APIM: 외부 캐시 연결 ───
resource externalCache 'Microsoft.ApiManagement/service/caches@2023-09-01-preview' = {
  parent: apimService
  name: 'default'
  properties: {
    connectionString: '${redisCache.properties.hostName}:${redisCache.properties.sslPort},password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
    useFromLocation: 'default'
    description: 'Azure Redis Cache for semantic caching'
  }
}

// ─── APIM → 임베딩 OpenAI Role Assignment ───
@description('Cognitive Services OpenAI User 역할 ID')
var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: embeddingAccount
  name: guid(embeddingAccount.id, apimService.id, cognitiveServicesOpenAIUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: apimService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ─── Outputs ───
output embeddingEndpoint string = embeddingAccount.properties.endpoint
output embeddingModelName string = embeddingModelName
output redisHostName string = redisCache.properties.hostName
