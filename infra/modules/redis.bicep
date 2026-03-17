@description('Redis Cache 이름')
param name string

@description('배포 위치')
param location string

@description('Redis SKU (Basic, Standard, Premium)')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Basic'

// ─── Azure Cache for Redis ───
resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: skuName
      family: skuName == 'Premium' ? 'P' : 'C'
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

// ─── Outputs ───
output id string = redisCache.id
output hostName string = redisCache.properties.hostName
output sslPort int = redisCache.properties.sslPort
output primaryKey string = redisCache.listKeys().primaryKey
output connectionString string = '${redisCache.properties.hostName}:${redisCache.properties.sslPort},password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
