param location string = resourceGroup().location
param suffix string
param publisherEmail string = 'admin@example.com'
param publisherName string = 'LogBench v2'

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: 'apim-logbench-v2-${suffix}'
  location: location
  sku: { name: 'BasicV2', capacity: 1 }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
  tags: { 'managed-by': 'lab13-v4' }
}
output apimName string = apim.name
output apimPrincipalId string = apim.identity.principalId
output gatewayUrl string = apim.properties.gatewayUrl
