# Lab 11: APIM + Managed Identity로 Microsoft Graph 호출

APIM의 Managed Identity를 사용해 **클라이언트가 구독 키만으로** 동일 테넌트의
Microsoft Graph 정보를 조회하도록 만듭니다. 나아가 **구독별 차등 조회**를
두 가지 격리 모델(정책 게이트 vs 권한별 MI)로 비교 실습합니다.

## 목표

- 클라이언트가 Graph 토큰을 직접 발급하지 않고 **APIM 구독 키만으로** Graph 조회
- Managed Identity의 **앱 역할(App Role)** 부여 원리 이해 (`az rest`)
- **옵션 A**: System MI 1개 + 정책 게이트로 구독별 Operation 차단(403)
- **옵션 B**: 권한별 User-Assigned MI 3개(users/mail/sharepoint)로 진짜 격리 달성
- 두 모델의 보안 강도 차이를 노트북으로 검증

## 사전 확인

> Lab 1의 `deploy.sh`로 APIM(`apim-ai-gw-{suffix}`)이 배포되어 있고,
> System-Assigned Managed Identity가 활성화되어 있어야 합니다.

```bash
set -a; source .env; set +a
# APIM System MI principalId 확인
az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv
```

## 핵심 개념 (먼저 읽어주세요)

**구독 키는 Graph 토큰이 아닙니다.** 클라이언트는 `Ocp-Apim-Subscription-Key`만 보내고,
Graph용 `Authorization: Bearer` 토큰은 **APIM의 MI가 내부에서 발급**해 백엔드로 주입합니다.

**MI는 애플리케이션 권한만 씁니다.** 사용자 컨텍스트가 없으므로 위임 권한이 아닌
앱 역할(`User.Read.All`, `Mail.Read`)을 부여합니다. 이는 Portal UI로 안 되고 `az rest`가 필요합니다.

**System MI vs User MI (먼저 구분하세요)**

두 가지는 완전히 다른 정체성입니다. 이 랩의 옵션 A/B 차이가 바로 여기서 시작됩니다.

| | System-Assigned MI (System MI) | User-Assigned MI (UAMI) |
|---|---|---|
| 정체성 소유 | **APIM 리소스 자체** (= APIM 본체) | 독립 리소스 (따로 생성) |
| 생명주기 | APIM 삭제 시 함께 삭제 | APIM과 무관하게 존속 |
| APIM당 개수 | **1개** (이름 없음, APIM 이름으로 표시) | **N개** 연결 가능 |
| 권한 분리 | 불가 (1개 정체성 = 권한 합집합) | 가능 (정체성마다 최소 권한) |
| 정책 지정 | `client-id` 없이 사용 | `client-id="{{...}}"`로 지정 |

> 즉 **"System MI = APIM 자체"**가 맞습니다. APIM 하나 = 정체성 하나라 권한을 쪼갤 수 없고,
> 그래서 옵션 A는 격리를 **정책 레이어에서 흉내**냅니다. 반대로 UAMI는 정체성을 여러 개 두고
> 각각 단일 권한만 부여할 수 있어, APIM이 요청마다 `client-id`로 발급 주체를 고릅니다(옵션 B).

**격리는 어디서?**

| 모델 | 실제 권한 경계 | 격리 방식 |
|------|---------------|-----------|
| 옵션 A | System MI = 모든 권한 합집합 | APIM 정책이 구독→Operation 차단 |
| 옵션 B | UAMI별 단일 권한 | 정책이 구독별 `client-id`로 다른 MI 선택 |

---

## Part 1 (옵션 A): System MI + 정책 게이트

### 1단계: Graph API 등록 (Portal, 수동)

1. Azure Portal → APIM → APIs → **Add API** → **HTTP**
2. 설정:
   - Display name: `Microsoft Graph`
   - Web service URL: `https://graph.microsoft.com/v1.0`
   - API URL suffix: `graph`
3. Operation 추가:
   - `GET /users`
   - `GET /users/{user-id}`
   - `GET /users/{user-id}/messages`
   - `GET /sites/*` (와일드카드 catch-all — SharePoint 경로가 다중 세그먼트라 단일 `{param}`으로 못 잡음)

### 2단계: Product 3개 생성 & 구독 키 발급

1. APIM → **Products** → **Add**
   - `graph-users` (Published, Requires subscription)
   - `graph-mail` (Published, Requires subscription)
   - `graph-sharepoint` (Published, Requires subscription)
2. 각 Product에 **Microsoft Graph API 추가**
3. 각 Product의 **Subscriptions**에서 키 생성 → Primary key 복사
4. `.env`에 입력:
   ```
   APIM_KEY_GRAPH_USERS="<graph-users 구독 키>"
   APIM_KEY_GRAPH_MAIL="<graph-mail 구독 키>"
   APIM_KEY_GRAPH_SHAREPOINT="<graph-sharepoint 구독 키>"
   SHAREPOINT_SITE_HOSTNAME="<tenant.sharepoint.com>"
   SHAREPOINT_SITE_PATH="<site-name>"
   ```

### 3단계: System MI에 Graph 앱 역할 부여

```bash
set -a; source .env; set +a
PRINCIPAL_ID=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv)

./scripts/grant-graph-role.sh "$PRINCIPAL_ID" User.Read.All
./scripts/grant-graph-role.sh "$PRINCIPAL_ID" Mail.Read
./scripts/grant-graph-role.sh "$PRINCIPAL_ID" Sites.Read.All
```

> ⏱️ 권한 전파에 수 분이 걸릴 수 있습니다.

#### 부여 확인

**⚠️ APIM 리소스 블레이드에서는 Graph 권한이 안 보입니다.** APIM → Managed identities →
`Azure role assignments` 버튼은 **Azure RBAC 역할**(Reader, Contributor 등)만 표시합니다.
우리가 준 `User.Read.All` / `Mail.Read`는 **Microsoft Graph 앱 역할(API 권한)** 이라
**종류가 다른 인가 체계**이며, 이 화면에는 나타나지 않습니다.

> **"역할"이라는 단어만 같을 뿐, 서로 다른 평면입니다.** Azure에는 이름이 비슷해서 헷갈리는
> 인가 체계가 3개 있습니다. 이 랩에서 부여한 건 **③ API 권한**이며, APIM 블레이드가 보여주는
> **① Azure RBAC**과는 무관합니다.

| 체계 | 무엇을 보호 | 예시 | 부여/저장 위치 | 강제(enforce) 주체 |
|------|-------------|------|----------------|--------------------|
| **① Azure RBAC** | Azure **리소스**(ARM: 구독/RG/VM/Storage) | Reader, Contributor, Storage Blob Data Reader | ARM `roleAssignments` (리소스 스코프) | ARM / 리소스 공급자 |
| **② Entra 디렉터리 역할** | Entra **디렉터리 객체**(사용자/그룹/앱 관리) | Global Administrator, User Administrator | Entra 디렉터리 | Entra ID |
| **③ API 권한(앱 역할)** ← 이 랩 | 특정 **API 호출**(Graph 등) | **User.Read.All, Mail.Read** | 대상 API SP의 `appRoleAssignments` | **그 API 자신** (토큰 `roles` 클레임 검사) |

**무엇과 무엇을 비교해야 하나:**

- **③의 진짜 짝은 "다른 API의 권한"입니다.** `User.Read.All`은 Graph 전용이 아니라 OAuth API 권한 모델의
  한 사례일 뿐 — Key Vault·Storage·커스텀 API도 각자 앱 역할을 노출합니다. 즉 ③끼리 비교해야 맞습니다.
- **①의 진짜 짝은 ②입니다.** 둘 다 "role 기반"이지만 하나는 *Azure 리소스*를, 하나는 *Entra 디렉터리*를
  다스립니다. "role"이 겹치는 건 이 둘이지, ③이 아닙니다.

> 한 줄 요약: **③(Graph 앱 역할) = "이 정체성이 어떤 API를 무슨 권한으로 호출하나"(OAuth 인가)**,
> **①(Azure RBAC) = "이 정체성이 어떤 Azure 리소스를 다루나"(ARM 인가)**. APIM MI가 Graph를
> 호출할 땐 ③만 필요하고 ①은 전혀 관여하지 않습니다. 그래서 확인도 APIM 블레이드가 아닌
> Entra ID(아래 방법 1/2)에서 합니다.

**방법 1 — CLI (가장 확실):** 부여된 Graph 앱 역할을 직접 조회합니다.

```bash
az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PRINCIPAL_ID/appRoleAssignments" \
  --query "value[].{resource:resourceDisplayName, roleId:appRoleId}" -o table
```

`resourceDisplayName`이 `Microsoft Graph`인 항목이 **2개**(User.Read.All, Mail.Read) 나오면
부여 성공입니다. `roleId`(GUID)를 사람이 읽는 이름으로 매핑하려면:

```bash
az ad sp show --id "00000003-0000-0000-c000-000000000000" \
  --query "appRoles[?value=='User.Read.All' || value=='Mail.Read'].{value:value, id:id}" -o table
```

**방법 2 — Portal (눈으로):** APIM 리소스가 아니라 **Entra ID** 쪽에서 확인합니다.

Microsoft Entra ID → **Enterprise applications** → 필터 `Application type = Managed Identities`
→ 목록에서 **APIM 이름 그대로**(예: `apim-ai-gw-{suffix}`) 클릭 → **Permissions** 탭
→ `User.Read.All`, `Mail.Read`가 Application 권한으로 표시되면 성공.

> APIM 블레이드의 `Object (principal) ID`와 위 `$PRINCIPAL_ID`, 그리고 Enterprise applications의
> 해당 항목은 **모두 동일한 System MI**입니다. 같은 정체성을 화면만 달리 보는 것뿐입니다.

### 4단계: 정책 적용 (Microsoft Graph API → All operations → Inbound)

```xml
<policies>
    <inbound>
        <base />
        <!-- 구독(Product)별 Operation 게이트 -->
        <choose>
            <when condition="@(context.Product?.Name == &quot;graph-users&quot; &amp;&amp; context.Operation.UrlTemplate.Contains(&quot;/messages&quot;))">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>이 구독(graph-users)은 사용자 조회만 허용됩니다.</set-body>
                </return-response>
            </when>
            <when condition="@(context.Product?.Name == &quot;graph-mail&quot; &amp;&amp; !context.Operation.UrlTemplate.Contains(&quot;/messages&quot;))">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>이 구독(graph-mail)은 메일 조회만 허용됩니다.</set-body>
                </return-response>
            </when>
            <when condition="@(context.Product?.Name == &quot;graph-sharepoint&quot; &amp;&amp; !context.Operation.UrlTemplate.Contains(&quot;/sites&quot;))">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>이 구독(graph-sharepoint)은 SharePoint 조회만 허용됩니다.</set-body>
                </return-response>
            </when>
            <when condition="@(context.Product?.Name == &quot;graph-users&quot; &amp;&amp; context.Operation.UrlTemplate.Contains(&quot;/sites&quot;))">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>이 구독(graph-users)은 SharePoint 조회 권한이 없습니다.</set-body>
                </return-response>
            </when>
        </choose>
        <!-- System MI로 Graph 토큰 발급 -->
        <authentication-managed-identity resource="https://graph.microsoft.com" />
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
```

> ⚠️ **정책 표현식 안의 특수문자는 XML 엔티티로 이스케이프하세요.** `condition="..."`는 큰따옴표로
> 감싸는 XML 속성이라, 그 안에서 문자열 큰따옴표는 `&quot;`, 논리 AND(`&&`)는 `&amp;&amp;`로 써야 합니다.
> 그대로 `"graph-users"`나 `&&`를 쓰면 속성이 끊기거나 `&`가 엔티티로 오인되어
> *"policy expressions may not have the correct parentheses or braces format"* 경고가 뜹니다.
> Portal 편집기는 관대해 Save는 되지만, ARM/`az` 배포 시엔 깨지므로 이스케이프가 정석입니다.
> (직접 타이핑하지 말고 위 블록을 그대로 복사하세요.)

### 5단계: 노트북 테스트 (Part 1)

`test-graph-mi.ipynb`의 셀 1~10을 실행합니다. (셀 7~10 = SharePoint 리스트/항목 조회 및 교차접근 차단)

---

## Part 2 (옵션 B): 권한별 UAMI로 진짜 격리

### 1단계: UAMI 배포

```bash
set -a; source .env; set +a
./scripts/deploy-graph-uami.sh
```

이 스크립트는 UAMI 3개 생성 → APIM 연결 → 각각 단일 역할 부여 →
clientId를 APIM Named Value(`uami-graph-users-client-id`, `uami-graph-mail-client-id`,
`uami-graph-sharepoint-client-id`)로 등록합니다.

### 2단계: 정책 교체 (client-id 라우팅)

```xml
<policies>
    <inbound>
        <base />
        <choose>
            <when condition="@(context.Product?.Name == &quot;graph-mail&quot;)">
                <authentication-managed-identity resource="https://graph.microsoft.com" client-id="{{uami-graph-mail-client-id}}" />
            </when>
            <when condition="@(context.Product?.Name == &quot;graph-sharepoint&quot;)">
                <authentication-managed-identity resource="https://graph.microsoft.com" client-id="{{uami-graph-sharepoint-client-id}}" />
            </when>
            <otherwise>
                <authentication-managed-identity resource="https://graph.microsoft.com" client-id="{{uami-graph-users-client-id}}" />
            </otherwise>
        </choose>
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
```

> 이제 정책 게이트 없이도, 잘못된 경로는 **토큰 자체에 권한이 없어 Graph가 거부**합니다.

### 3단계: 노트북 테스트 (Part 2)

`test-graph-mi.ipynb`의 셀 11을 실행하여, `graph-users` 키로 메일 접근 시
Graph가 권한 부족으로 거부하는 것을 확인합니다.

---

## 노트북 테스트 항목

| 셀 | 시나리오 | 기대 |
|----|----------|------|
| 1 | 환경/구독키 로드 | — |
| 2 | 요청 헬퍼 (Bearer 없음) | 개념 |
| 3 | graph-users → GET /users | 200 |
| 4 | graph-users → /users/{id}/messages | 403 (정책) |
| 5 | graph-mail → /users/{id}/messages | 200 |
| 6 | graph-mail → GET /users | 403 (정책) |
| 7 | graph-sharepoint → 사이트 해석 | 200 (siteId 확보) |
| 8 | graph-sharepoint → GET /sites/{id}/lists | 200 (리스트 표) |
| 9 | graph-sharepoint → /lists/{id}/items | 200 (항목 표) |
| 10 | graph-users → /sites 교차접근 | 403 (정책) |
| 11 | (Part 2) graph-users → 메일 재시도 | Graph 권한 거부 |

## 핵심 개념

- **편의적 격리 vs 진짜 격리**: 정책 게이트는 APIM을 신뢰하는 전제의 편의적 격리이고,
  권한별 UAMI는 토큰 권한 자체로 경계를 만드는 강한 격리입니다.
- **최소 권한 원칙**: UAMI마다 필요한 앱 역할 하나만 부여합니다.
- **보안 함의**: 옵션 A는 정책이 뚫리면 MI의 전체 권한이 노출될 수 있습니다.

## 다음 단계

→ [Lab 12: 리소스 정리](../lab12-cleanup/README.md)
