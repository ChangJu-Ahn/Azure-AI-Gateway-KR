@description('Azure AI Content Safety 리소스 이름')
param name string

@description('배포 위치. Content Safety를 지원하는 리전을 사용하세요(예: eastus, swedencentral). koreacentral은 미지원일 수 있습니다.')
param location string

@description('한국형 PII 차단용 RAI 블록리스트 이름. llm-content-safety 정책의 <blocklists><id>에서 참조됩니다.')
param blocklistName string = 'korea-pii'

// ─── Content Safety 계정 ───
resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'ContentSafety'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
  }
}

// ─── RAI 블록리스트 (커스텀 컨텐츠 필터링의 컨테이너) ───
// 참고: llm-content-safety 정책이 참조하는 blocklist는 텍스트 모더레이션 blocklist가 아니라
//       이 raiBlocklist(Responsible AI)이며, raiBlocklistItems는 정규식(isRegex)을 지원합니다.
resource raiBlocklist 'Microsoft.CognitiveServices/accounts/raiBlocklists@2025-06-01' = {
  parent: contentSafety
  name: blocklistName
  properties: {
    description: '대한민국 PII(주민등록번호/휴대폰번호/주소) 차단 목록'
  }
}

// ─── 블록리스트 항목 (정규식) ───
// ⚠️ 같은 blocklist에 여러 항목을 동시에 배포하면 IfMatchPreconditionFailed 오류가 발생합니다.
//    따라서 dependsOn으로 순차 배포되도록 체이닝합니다.

// ① 주민등록번호: YYMMDD-[성별코드 1~4]NNNNNN (예: 900101-1234567)
//    성별/세기 코드 [1-4]로 일반 13자리 숫자와 구분하여 오탐을 줄입니다.
resource itemRrn 'Microsoft.CognitiveServices/accounts/raiBlocklists/raiBlocklistItems@2025-06-01' = {
  parent: raiBlocklist
  name: 'rrn'
  properties: {
    isRegex: true
    pattern: '\\d{6}-[1-4]\\d{6}'
  }
}

// ② 휴대폰번호: 010/011/016/017/018/019 - 3~4자리 - 4자리 (구분자 -, 공백, 없음 허용)
resource itemPhone 'Microsoft.CognitiveServices/accounts/raiBlocklists/raiBlocklistItems@2025-06-01' = {
  parent: raiBlocklist
  name: 'phone'
  properties: {
    isRegex: true
    pattern: '01[016-9][-\\s]?\\d{3,4}[-\\s]?\\d{4}'
  }
  dependsOn: [
    itemRrn
  ]
}

// ③ 주소(휴리스틱): 한글 도로명 + (로|길) + 번호 (예: 테헤란로 152, 세종대로 110)
//    ⚠️ 정규식 기반 주소 탐지는 본질적으로 오탐/미탐이 큽니다. 데모용이며, 운영에서는
//       Azure AI Language의 PII 개체 인식 등으로 보완하거나 이 항목을 제거하세요.
resource itemAddress 'Microsoft.CognitiveServices/accounts/raiBlocklists/raiBlocklistItems@2025-06-01' = {
  parent: raiBlocklist
  name: 'address'
  properties: {
    isRegex: true
    pattern: '[가-힣]{2,}(로|길)\\s?\\d{1,4}(번길|번지|호)?'
  }
  dependsOn: [
    itemPhone
  ]
}

// ─── Outputs ───
output name string = contentSafety.name
output endpoint string = contentSafety.properties.endpoint
output blocklistName string = blocklistName
