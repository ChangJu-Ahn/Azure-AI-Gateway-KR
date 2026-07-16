# 개발자 포털(Developer Portal) 게시 가이드

APIM 개발자 포털을 활성화·브랜딩·게시하여 팀이 셀프서비스로 구독하게 합니다.

## 1. 포털 관리 콘솔 열기

Azure Portal → API Management → **Developer portal** → **Developer portal (관리)** 클릭.

포털 편집 인터페이스가 열립니다.

## 2. 콘텐츠 편집 & 브랜딩

### 홈 페이지 편집

1. 관리 콘솔 왼쪽 메뉴 → **Pages** → **Home** 클릭
2. 제목·설명 편집 (예: "AI Gateway — Multi-Cloud LLM Portal")
3. 필요하면 로고·배경 색상 변경 (Design 탭 → **Branding**)

### 제품 페이지 활성화

1. 왼쪽 메뉴 → **Pages** → **Products** 활성화
2. 포털에 등록된 모든 Product(team-a, team-b 등)가 표시됩니다

### 헤더 & 푸터 커스터마이징

1. **Design** 탭 → **Header** / **Footer** 섹션
2. 조직 이름·로고·링크 추가

## 3. 게시(Publish)

1. 관리 콘솔 상단 **Publish** 버튼 클릭
2. 변경사항이 공개 포털에 반영됩니다

> ⚠️ 게시 전까지는 변경사항이 개발(관리) 콘솔에서만 보입니다.

## 4. 회원가입 & 구독 흐름

### 4-1. 개발자 회원가입

1. 공개 포털(`https://<apim-name>.developer.azure-api.net`) 접속
2. 오른쪽 상단 **Sign Up** 또는 **Register** 클릭
3. 이메일·이름·비밀번호 입력 후 제출
4. 이메일 인증 완료

### 4-2. Product 구독 신청

1. 포털 로그인 → **Products** 탭 클릭
2. Product 목록 표시 (team-a, team-b 등)
3. `team-a` 클릭 → **Subscribe** 버튼
4. 구독 이름 입력 후 제출

### 4-3. 즉시 발급 vs. 승인 대기

- **team-a** (자동 승인 · TPM 10,000 · 월 10,000,000): Subscribe 후 즉시 Subscription Key 발급
  - **Profile** 페이지에서 **Primary Key** · **Secondary Key** 확인 가능
  
- **team-b** (관리자 승인 · TPM 2,000 · 월 2,000,000): Subscribe 후 "대기 중" 상태
  - 관리자 승인 후 Key 발급
  - 포털 Profile 페이지에 Key 표시

## 5. 구독 승인 (관리자)

1. Azure Portal → API Management → 해당 APIM 인스턴스 클릭
2. 왼쪽 메뉴 → **Subscriptions** 클릭
3. **Pending subscriptions** (또는 필터링으로 "대기" 상태)
4. 각 대기 중 구독 행 → 오른쪽 **...** → **Approve** 또는 **Reject** 선택
5. 승인하면 개발자 포털에서 자동으로 Key 를 확인할 수 있습니다

> 💡 Portal 에서도 승인/거부 가능합니다 (관리자 권한 필요).

## 6. API 테스트 (Try It)

개발자 포털에서 직접 API 호출을 테스트할 수 있습니다:

1. **Products** → Product 클릭 → API 목록 표시
2. API 작업(예: `Chat Completions`) 클릭
3. **Try It** 탭
4. Subscription 선택 → 매개변수 입력 → **Send** 클릭
5. 응답 확인 (StatusCode, Headers, Body)

## 7. Profile & Key 관리

개발자가 포털에서:

1. 오른쪽 상단 프로필 아이콘 → **Profile** 클릭
2. **Subscriptions** 섹션에서 자신의 모든 구독 목록
3. 각 구독의 **Primary Key** · **Secondary Key** 확인·복사
4. 필요시 Key 재생성 (**Regenerate**)

## 트러블슈팅

### 포털 페이지가 비어 있음 (모든 Product이 안 보임)

- 확인: APIM 관리 콘솔 → **Products** → 해당 Product의 **설정** → **State** 가 **Published** 로 설정됐는지
- 확인: 게시(Publish)를 완료했는지
- 확인: 개발자가 로그인했는지 (로그인하지 않으면 익명 사용자로 제한된 Product만 보임)

### "Subscription Approval Required" 메시지만 뜨고 Key가 안 보임

- 원인: 관리자가 아직 구독을 승인하지 않음
- 해결: 관리자 → Azure Portal → **Subscriptions** → **Approve**

### 개발자 포털 접속 안 됨 (404)

- 확인: APIM이 Developer Tier 이상인지 (Consumption Tier는 Developer Portal 미지원)
- 확인: 포털 URL 형식 (`https://<apim-name>.developer.azure-api.net`)
- 확인: APIM 인스턴스가 실행 중인지 (포털 상태 표시기 확인)

### API "Try It" 테스트에서 401 Unauthorized

- 원인: Subscription Key를 선택하지 않았거나, 구독이 활성화되지 않음
- 해결: **Try It** 탭에서 **Ocp-Apim-Subscription-Key** 드롭다운에서 활성 구독 선택

## 추가 리소스

- [APIM Developer Portal 공식 문서](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-developer-portal)
- [구독 관리](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-aad)
- Lab 9: Products & 개발자 포털 — [구독 격리 구현](../labs/lab09-products-portal/README.md)
