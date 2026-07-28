# Lab 11: APIM + Managed Identity로 Microsoft Graph 호출

APIM의 Managed Identity를 사용해 **클라이언트가 구독 키만으로** 동일 테넌트의
Microsoft Graph 정보를 조회하도록 만듭니다. 나아가 **구독별 차등 조회**를
두 가지 격리 모델(정책 게이트 vs 권한별 MI)로 비교 실습합니다.

## 목표

- 클라이언트가 Graph 토큰을 직접 발급하지 않고 **APIM 구독 키만으로** Graph 조회
- Managed Identity의 **앱 역할(App Role)** 부여 원리 이해 (`az rest`)
- **옵션 A**: System MI 1개 + 정책 게이트로 구독별 Operation 차단(403)
- **옵션 B**: 권한별 User-Assigned MI 2개로 진짜 격리 달성
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
3. Operation 3개 추가:
   - `GET /users`
   - `GET /users/{user-id}`
   - `GET /users/{user-id}/messages`

### 2단계: Product 2개 생성 & 구독 키 발급

1. APIM → **Products** → **Add**
   - `graph-users` (Published, Requires subscription)
   - `graph-mail` (Published, Requires subscription)
2. 각 Product에 **Microsoft Graph API 추가**
3. 각 Product의 **Subscriptions**에서 키 생성 → Primary key 복사
4. `.env`에 입력:
   ```
   APIM_KEY_GRAPH_USERS="<graph-users 구독 키>"
   APIM_KEY_GRAPH_MAIL="<graph-mail 구독 키>"
   ```

### 3단계: System MI에 Graph 앱 역할 부여

```bash
set -a; source .env; set +a
PRINCIPAL_ID=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv)

./scripts/grant-graph-role.sh "$PRINCIPAL_ID" User.Read.All
./scripts/grant-graph-role.sh "$PRINCIPAL_ID" Mail.Read
```

> ⏱️ 권한 전파에 수 분이 걸릴 수 있습니다.

### 4단계: 정책 적용 (Microsoft Graph API → All operations → Inbound)

```xml
<policies>
    <inbound>
        <base />
        <!-- 구독(Product)별 Operation 게이트 -->
        <choose>
            <when condition="@(context.Product?.Name == "graph-users" && context.Operation.UrlTemplate.Contains("/messages"))">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>이 구독(graph-users)은 사용자 조회만 허용됩니다.</set-body>
                </return-response>
            </when>
            <when condition="@(context.Product?.Name == "graph-mail" && !context.Operation.UrlTemplate.Contains("/messages"))">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>이 구독(graph-mail)은 메일 조회만 허용됩니다.</set-body>
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

### 5단계: 노트북 테스트 (Part 1)

`test-graph-mi.ipynb`의 셀 1~6을 실행합니다.

---

## Part 2 (옵션 B): 권한별 UAMI로 진짜 격리

### 1단계: UAMI 배포

```bash
set -a; source .env; set +a
./scripts/deploy-graph-uami.sh
```

이 스크립트는 UAMI 2개 생성 → APIM 연결 → 각각 단일 역할 부여 →
clientId를 APIM Named Value(`uami-graph-users-client-id`, `uami-graph-mail-client-id`)로 등록합니다.

### 2단계: 정책 교체 (client-id 라우팅)

```xml
<policies>
    <inbound>
        <base />
        <choose>
            <when condition="@(context.Product?.Name == "graph-mail")">
                <authentication-managed-identity resource="https://graph.microsoft.com" client-id="{{uami-graph-mail-client-id}}" />
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

`test-graph-mi.ipynb`의 셀 7을 실행하여, `graph-users` 키로 메일 접근 시
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
| 7 | (Part 2) graph-users → 메일 재시도 | Graph 권한 거부 |

## 핵심 개념

- **편의적 격리 vs 진짜 격리**: 정책 게이트는 APIM을 신뢰하는 전제의 편의적 격리이고,
  권한별 UAMI는 토큰 권한 자체로 경계를 만드는 강한 격리입니다.
- **최소 권한 원칙**: UAMI마다 필요한 앱 역할 하나만 부여합니다.
- **보안 함의**: 옵션 A는 정책이 뚫리면 MI의 전체 권한이 노출될 수 있습니다.

## 다음 단계

→ [Lab 12: 리소스 정리](../lab12-cleanup/README.md)
