targetScope = 'resourceGroup'

// ═══════════════════════════════════════════════════════════════
// Content Safety 커스텀 컨텐츠 필터링 — 독립(증분) 배포
//
// 이미 배포된 APIM 위에 Content Safety 관련 리소스만 추가합니다.
// APIM을 재생성하지 않으므로 몇 분 내에 완료됩니다.
//   • Azure AI Content Safety 계정 + RAI 블록리스트(korea-pii, 정규식)
//   • content-safety-backend (Managed Identity 인증)
//   • APIM MI → Cognitive Services User 역할
//
// 사전 조건: deploy.sh로 기본 인프라(APIM)가 배포되어 있어야 합니다.
// ═══════════════════════════════════════════════════════════════

@description('리소스 이름 접미사 (기존 배포와 동일해야 함)')
param suffix string

@description('Azure AI Content Safety 배포 리전. Content Safety 지원 리전을 사용하세요.')
param contentSafetyLocation string = 'eastus'

// ─── 리소스 이름 (main.bicep과 동일 규칙) ───
var apimName = 'apim-ai-gw-${suffix}'
var contentSafetyName = 'acs-${suffix}'

// ─── 기존 APIM 참조 ───
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// ─── Content Safety 계정 + RAI 블록리스트(korea-pii) ───
module contentSafety 'modules/content-safety.bicep' = {
  name: 'content-safety'
  params: {
    name: contentSafetyName
    location: contentSafetyLocation
  }
}

// ─── APIM: Content Safety 백엔드 (MI 인증) ───
resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apimService
  name: 'content-safety-backend'
  properties: {
    description: 'Azure AI Content Safety backend (Managed Identity)'
    url: contentSafety.outputs.endpoint
    protocol: 'http'
    credentials: {
      #disable-next-line BCP037
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

// ─── APIM MI → Content Safety 역할 (Cognitive Services User) ───
module roleContentSafety 'modules/content-safety-role.bicep' = {
  name: 'role-content-safety'
  params: {
    contentSafetyName: contentSafety.outputs.name
    principalId: apimService.identity.principalId
  }
}

// ─── Outputs ───
output contentSafetyName string = contentSafety.outputs.name
output contentSafetyEndpoint string = contentSafety.outputs.endpoint
output contentSafetyBlocklistName string = contentSafety.outputs.blocklistName
