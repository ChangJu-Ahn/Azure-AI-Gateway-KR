# Azure Portal 배포 가이드

이 문서는 `scripts/deploy.sh` (CLI + Bicep)로 자동 배포되는 모든 리소스를 **Azure Portal에서 수동으로** 동일하게 구성하는 방법을 안내합니다.

> **예상 소요 시간:** 60~90분 (APIM Consumption 프로비저닝 대기 포함)

---

## 목차

1. [리소스 그룹 생성](#1-리소스-그룹-생성)
2. [Log Analytics 워크스페이스 생성](#2-log-analytics-워크스페이스-생성)
3. [Application Insights 생성](#3-application-insights-생성)
4. [Azure OpenAI 리소스 생성 (3개 리전)](#4-azure-openai-리소스-생성-3개-리전)
5. [gpt-4.1-nano 모델 배포 (3개 리전)](#5-gpt-4.1-nano-모델-배포-3개-리전)
6. [API Management 인스턴스 생성](#6-api-management-인스턴스-생성)
7. [APIM Managed Identity → OpenAI RBAC 설정](#7-apim-managed-identity--openai-rbac-설정)
8. [APIM에 Application Insights 연결](#8-apim에-application-insights-연결)
9. [APIM 백엔드 등록 (3개)](#9-apim-백엔드-등록-3개)
10. [백엔드 풀 구성](#10-백엔드-풀-구성)
11. [API 등록 및 정책 적용](#11-api-등록-및-정책-적용)
12. [테스트](#12-테스트)

---

## 1. 리소스 그룹 생성

1. [Azure Portal](https://portal.azure.com) 로그인
2. 상단 검색창에 **리소스 그룹** 입력 → **리소스 그룹** 클릭
3. **+ 만들기** 클릭
4. 입력:
   | 필드 | 값 |
   |------|-----|
   | 구독 | 본인 Azure 구독 선택 |
   | 리소스 그룹 | `rg-ai-gw-{suffix}` |
   | 지역 | `Korea Central` |
5. **검토 + 만들기** → **만들기** 클릭

---

## 2. Log Analytics 워크스페이스 생성

1. 상단 검색창 → **Log Analytics 작업 영역** 검색 → 클릭
2. **+ 만들기** 클릭
3. 입력:

   | 필드 | 값 |
   |------|-----|
   | 구독 | 동일 구독 |
   | 리소스 그룹 | `rg-ai-gw-{suffix}` |
   | 이름 | `log-ai-gw-{suffix}` |
   | 지역 | `Korea Central` |

4. **가격 책정 계층** 탭 → **종량제(Per GB 2018)** 확인 (기본값)
5. **검토 + 만들기** → **만들기** 클릭
6. 배포 완료될 때까지 대기 (약 1~2분)

---

## 3. Application Insights 생성

1. 상단 검색창 → **Application Insights** 검색 → 클릭
2. **+ 만들기** 클릭
3. 입력:

   | 필드 | 값 |
   |------|-----|
   | 구독 | 동일 구독 |
   | 리소스 그룹 | `rg-ai-gw-{suffix}` |
   | 이름 | `appi-ai-gw-{suffix}` |
   | 지역 | `Korea Central` |
   | 리소스 모드 | **작업 영역 기반** (기본값) |
   | Log Analytics 작업 영역 | `log-ai-gateway` (방금 만든 것) |

4. **검토 + 만들기** → **만들기** 클릭
5. 배포 완료 후 **리소스로 이동** → 오른쪽 상단 **Instrumentation Key** 복사 → 메모장에 저장 (나중에 APIM 연결 시 사용)

---

## 4. Azure OpenAI 리소스 생성 (3개 리전)

동일한 과정을 3번 반복합니다. 리전과 이름만 다릅니다.

| 순서 | 리소스 이름 | 리전 |
|------|-----------|------|
| ① | `aoai-eastus-dev` | `East US` |
| ② | `aoai-sweden-dev` | `Sweden Central` |
| ③ | `aoai-westus-dev` | `West US` |

### 각 리소스 생성 절차

1. 상단 검색창 → **Azure OpenAI** 검색 → **Azure OpenAI** 클릭
2. **+ 만들기** 클릭
3. **기본 사항** 탭:

   | 필드 | 값 |
   |------|-----|
   | 구독 | 동일 구독 |
   | 리소스 그룹 | `rg-ai-gw-{suffix}` |
   | 지역 | 위 표에서 해당 리전 선택 |
   | 이름 | 위 표에서 해당 이름 입력 |
   | 가격 책정 계층 | `Standard S0` |

4. **네트워크** 탭 → **모든 네트워크(인터넷 포함)** 선택
5. **검토 + 제출** → **만들기** 클릭
6. 배포 완료 후 **리소스로 이동**
7. 왼쪽 메뉴 **리소스 관리** → **키 및 엔드포인트** 클릭
8. **엔드포인트** URL 복사 → 메모장에 저장 (예: `https://aoai-eastus-dev.openai.azure.com/`)

> ⚠️ 3개 리전 모두 반복합니다. 총 3개의 엔드포인트를 메모해 두세요.

---

## 5. gpt-4.1-nano 모델 배포 (3개 리전)

각 Azure OpenAI 리소스에 동일한 모델을 배포합니다. 3번 반복합니다.

### 각 리소스에서의 모델 배포 절차

1. 해당 Azure OpenAI 리소스 페이지로 이동
2. 왼쪽 메뉴 **리소스 관리** → **모델 배포** 클릭
3. **+ 배포 만들기** → **기본 모델 배포** 클릭
4. 입력:

   | 필드 | 값 |
   |------|-----|
   | 모델 선택 | `gpt-4.1-nano` |
   | 모델 버전 | `2024-07-18` (기본값) |
   | 배포 이름 | `gpt-4.1-nano` |
   | 배포 유형 | `Standard` |
   | 분당 토큰 속도 제한 (TPM) | `30K` |

5. **만들기** 클릭

> ⚠️ 배포 이름은 반드시 `gpt-4.1-nano`로 통일합니다. APIM 정책에서 이 이름으로 라우팅합니다.

> ⚠️ 3개 리전 모두 동일하게 반복합니다.

---

## 6. API Management 인스턴스 생성

> ⏱️ Consumption 티어도 프로비저닝에 약 30~45분이 소요될 수 있습니다.

1. 상단 검색창 → **API Management 서비스** 검색 → 클릭
2. **+ 만들기** 클릭
3. **기본 사항** 탭:

   | 필드 | 값 |
   |------|-----|
   | 구독 | 동일 구독 |
   | 리소스 그룹 | `rg-ai-gw-{suffix}` |
   | 지역 | `Korea Central` |
   | 리소스 이름 | `apim-ai-gw-{suffix}` |
   | 조직 이름 | `AI Gateway Lab` |
   | 관리자 전자 메일 | 본인 이메일 |
   | 가격 책정 계층 | **Consumption** |

4. **모니터링** 탭:
   - **Application Insights** → **사용** 선택
   - Application Insights 인스턴스 → `appi-ai-gateway` 선택

5. **검토 + 만들기** → **만들기** 클릭
6. 프로비저닝 완료까지 대기 (30~45분)
7. 배포 완료 후 **리소스로 이동**
8. **개요** 페이지에서 **Gateway URL** 확인 → 메모장에 저장 (예: `https://apim-ai-gateway-dev.azure-api.net`)

### 시스템 할당 관리 ID 활성화 (APIM 생성 후)

> ⚠️ APIM 생성 마법사에는 관리 ID 설정 탭이 없습니다. **생성 완료 후** 별도로 설정해야 합니다.

1. 생성된 `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **보안** 섹션 → **관리 ID** 클릭
3. **시스템 할당** 탭 선택
4. **상태** → **켜기**로 변경
5. **저장** 클릭 → 확인 대화상자에서 **예** 클릭
6. **개체 ID**가 생성되면 성공 (이 ID가 OpenAI RBAC에서 사용됩니다)

> ⚠️ 이 설정이 없으면 Azure OpenAI에 키 없이 인증할 수 없습니다. 반드시 [7단계](#7-apim-managed-identity--openai-rbac-설정) 전에 완료하세요.

---

## 7. APIM Managed Identity → OpenAI RBAC 설정

APIM이 Azure OpenAI에 키 없이 접근할 수 있도록 각 OpenAI 리소스에 역할을 할당합니다.  
**3개 OpenAI 리소스 모두 동일하게 반복합니다.**

### 각 OpenAI 리소스에서의 역할 할당 절차

1. 해당 Azure OpenAI 리소스 페이지로 이동 (예: `aoai-eastus-dev`)
2. 왼쪽 메뉴 **액세스 제어(IAM)** 클릭
3. **+ 추가** → **역할 할당 추가** 클릭
4. **역할** 탭:
   - 검색창에 `Cognitive Services OpenAI User` 입력
   - **Cognitive Services OpenAI User** 역할 선택
   - **다음** 클릭
5. **구성원** 탭:
   - **액세스 할당 대상** → **관리 ID** 선택
   - **+ 구성원 선택** 클릭
   - **관리 ID** 드롭다운 → **API Management 서비스** 선택
   - `apim-ai-gateway-dev` 선택 후 **선택** 클릭
6. **검토 + 할당** → **검토 + 할당** 클릭

> ⚠️ 3개 Azure OpenAI 리소스(`aoai-eastus-dev`, `aoai-sweden-dev`, `aoai-westus-dev`) 모두 동일하게 반복합니다.

### 확인 방법

각 OpenAI 리소스의 **액세스 제어(IAM)** → **역할 할당** 탭에서  
`apim-ai-gateway-dev`이 **Cognitive Services OpenAI User** 역할로 나타나면 성공입니다.

---

## 8. APIM에 Application Insights 연결

> APIM 생성 시 모니터링 탭에서 이미 Application Insights를 연결했다면 이 단계는 건너뜁니다.

### 방법 A: APIM 리소스 수준 연결 (권장)

1. `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **모니터링** 섹션 → **Application Insights** 클릭
3. **+ 추가** 클릭
4. **Application Insights 인스턴스** → `appi-ai-gateway` 선택
5. **만들기** 클릭

### 방법 B: API별 진단 로그 설정

> API가 이미 등록되어 있어야 합니다. [11단계](#11-api-등록-및-정책-적용)를 먼저 완료한 후 돌아와서 설정하세요.

1. `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **API** 섹션 → **API** 클릭
3. `Azure OpenAI API` 선택 → **설정** 탭 클릭
4. 하단 **진단 로그** 섹션:
   - **Application Insights** 토글 → **사용**
   - **대상** → `appi-ai-gateway` 선택
   - **샘플링(%)** → `100`
   - **항상 오류 로그** → ✅ 체크
   - **클라이언트 IP 기록** → ✅ 체크
5. **저장** 클릭

> ⚠️ Consumption 티어에서는 왼쪽 메뉴에 "로거(Loggers)" 메뉴가 표시되지 않습니다. 위 두 방법 중 하나를 사용하세요.

---

## 9. APIM 백엔드 등록 (3개)

APIM에 3개 Azure OpenAI 엔드포인트를 백엔드로 등록합니다.

### 각 백엔드 등록 절차

1. `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **API** → **백엔드** 클릭
3. **+ 추가** 클릭
4. 입력:

**① East US 백엔드**

| 필드 | 값 |
|------|-----|
| 이름 | `aoai-eastus` |
| 유형 | `사용자 지정 URL` |
| 런타임 URL | `https://aoai-eastus-dev.openai.azure.com/openai` |
| 프로토콜 | `HTTP(s)` |

**② Sweden Central 백엔드**

| 필드 | 값 |
|------|-----|
| 이름 | `aoai-swedencentral` |
| 유형 | `사용자 지정 URL` |
| 런타임 URL | `https://aoai-sweden-dev.openai.azure.com/openai` |
| 프로토콜 | `HTTP(s)` |

**③ West US 백엔드**

| 필드 | 값 |
|------|-----|
| 이름 | `aoai-westus` |
| 유형 | `사용자 지정 URL` |
| 런타임 URL | `https://aoai-westus-dev.openai.azure.com/openai` |
| 프로토콜 | `HTTP(s)` |

5. 각각 **만들기** 클릭

### Circuit Breaker 설정 (각 백엔드에 적용)

> ⚠️ Azure Portal에서 Circuit Breaker를 직접 설정하는 UI가 제한적일 수 있습니다.
> 그 경우 아래 Azure CLI 명령으로 보완하거나, Bicep 배포를 사용하세요.

Portal에서 백엔드 편집이 가능한 경우:

1. 백엔드 목록에서 `aoai-eastus` 클릭
2. **Circuit Breaker** 섹션 (또는 **고급** 설정):

   | 설정 | 값 |
   |------|-----|
   | 규칙 이름 | `openAiCircuitBreaker` |
   | 실패 횟수 (count) | `3` |
   | 시간 간격 (interval) | `60초` (PT60S) |
   | 상태 코드 범위 | `429-429`, `500-503` |
   | 차단 기간 (tripDuration) | `30초` (PT30S) |
   | Retry-After 헤더 존중 | ✅ 체크 |

3. **저장** 클릭
4. `aoai-swedencentral`, `aoai-westus`에도 동일하게 반복

---

## 10. 백엔드 풀 구성

3개 백엔드를 하나의 풀로 묶어 로드밸런싱합니다.

1. `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **API** → **백엔드** 클릭
3. **+ 추가** 클릭
4. 입력:

   | 필드 | 값 |
   |------|-----|
   | 이름 | `openai-backend-pool` |
   | 유형 | **부하 분산 풀(Load balanced pool)** |

5. **풀 멤버 추가:**

   | 백엔드 | 우선순위 | 가중치 |
   |--------|---------|--------|
   | `aoai-eastus` | `1` | `1` |
   | `aoai-swedencentral` | `1` | `1` |
   | `aoai-westus` | `1` | `1` |

   > 우선순위가 모두 `1`이고 가중치가 동일하므로 **라운드 로빈** 방식으로 분산됩니다.

6. **만들기** 클릭

### 확인

백엔드 목록에서 `openai-backend-pool`이 **Pool** 타입으로 나타나고, 멤버가 3개인지 확인합니다.

---

## 11. API 등록 및 정책 적용

### 11-1. Azure OpenAI API 등록

1. `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **API** → **API** 클릭
3. **+ API 추가** → **HTTP** (수동 정의) 선택
4. 입력:

   | 필드 | 값 |
   |------|-----|
   | 표시 이름 | `Azure OpenAI API` |
   | 이름 | `azure-openai-api` |
   | 웹 서비스 URL | (공백 — 정책에서 백엔드 풀로 라우팅) |
   | API URL 접미사 | `openai` |
   | 구독 필요 | ✅ 체크 |

5. **만들기** 클릭

### 11-2. 작업(Operation) 추가

1. 방금 만든 `Azure OpenAI API` 클릭
2. **+ 작업 추가** 클릭
3. 입력:

   | 필드 | 값 |
   |------|-----|
   | 표시 이름 | `Chat Completions` |
   | 이름 | `chat-completions` |
   | HTTP 메서드 | `POST` |
   | URL 템플릿 | `/deployments/{deployment-id}/chat/completions` |

4. **URL 템플릿 매개 변수:**
   - `deployment-id` → 유형: `string`
5. **쿼리 매개 변수 추가:**
   - 이름: `api-version`, 유형: `string`, 필수: ✅
6. **저장** 클릭

### 11-3. 로드밸런서 정책 적용

1. `Azure OpenAI API` → **All operations** 클릭
2. **Design** 탭이 열리면, **Inbound processing** 섹션 오른쪽의 **</>** (코드 편집기) 아이콘 클릭
   - 또는 화면 하단의 **Policies code editor** 링크 클릭
3. 기존 내용을 모두 삭제하고 아래 정책을 붙여넣기:

```xml
<policies>
    <inbound>
        <base />
        <!-- Managed Identity 인증 -->
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
        <!-- 백엔드 풀로 라우팅 -->
        <set-backend-service backend-id="openai-backend-pool" />
    </inbound>

    <backend>
        <base />
    </backend>

    <outbound>
        <base />
        <!-- 사용된 백엔드 정보를 응답 헤더에 추가 (디버깅용) -->
        <set-header name="x-backend-url" exists-action="override">
            <value>@(context.Request.Url.Host)</value>
        </set-header>
    </outbound>

    <on-error>
        <base />
    </on-error>
</policies>
```

4. **저장** 클릭

> 💡 이것은 기본 로드밸런서 정책입니다.  
> 토큰 Rate Limiting, 시맨틱 캐싱 등 전체 정책을 적용하려면 `policies/ai-gateway-policy.xml` 내용을 대신 붙여넣으세요.

---

## 12. 테스트

### 12-1. Subscription Key 확인

1. `apim-ai-gateway-dev` APIM 리소스로 이동
2. 왼쪽 메뉴 **API** → **구독** 클릭
3. **Built-in all-access subscription** 행의 오른쪽 **...** → **키 표시/숨기기** 클릭
4. **기본 키** 복사

### 12-2. Portal 내장 테스트 콘솔

1. **API** → **Azure OpenAI API** → **Chat Completions** 작업 클릭
2. **테스트** 탭 클릭
3. **매개 변수 설정:**

   | 매개 변수 | 값 |
   |----------|-----|
   | deployment-id | `gpt-4.1-nano` |
   | api-version | `2025-04-01-preview` |

4. **요청 본문** (Raw JSON):

```json
{
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello, what is Azure API Management?"}
    ],
    "max_tokens": 200
}
```

5. **보내기** 클릭
6. 응답 확인:
   - **상태 코드**: `200 OK`
   - **응답 헤더**: `x-backend-url` 값으로 어느 백엔드가 사용됐는지 확인
   - **응답 본문**: 모델의 답변이 포함된 JSON

### 12-3. 노트북 테스트

환경 변수를 설정한 후 레포지토리의 노트북을 실행합니다:

```bash
export APIM_BASE_URL="https://apim-ai-gateway-dev.azure-api.net"
export APIM_SUBSCRIPTION_KEY="<위에서 복사한 키>"

python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
jupyter notebook labs/lab03-backend-pool/test-roundrobin.ipynb
```

---

## 리소스 대응표 (Bicep ↔ Portal)

| Bicep 파일 | 리소스 | Portal 이름 | 본 가이드 섹션 |
|-----------|--------|------------|---------------|
| `modules/monitoring.bicep` | Log Analytics | `log-ai-gateway` | [2](#2-log-analytics-워크스페이스-생성) |
| `modules/monitoring.bicep` | App Insights | `appi-ai-gateway` | [3](#3-application-insights-생성) |
| `modules/openai.bicep` × 3 | Azure OpenAI | `aoai-*-dev` | [4](#4-azure-openai-리소스-생성-3개-리전), [5](#5-gpt-4.1-nano-모델-배포-3개-리전) |
| `modules/apim.bicep` | APIM Service | `apim-ai-gateway-dev` | [6](#6-api-management-인스턴스-생성) |
| `main.bicep` (roleAssignment) | RBAC | Cognitive Services OpenAI User | [7](#7-apim-managed-identity--openai-rbac-설정) |
| `modules/apim.bicep` (logger) | APIM Logger | App Insights 연결 | [8](#8-apim에-application-insights-연결) |
| `modules/apim.bicep` (backends) | APIM Backends | `aoai-*` | [9](#9-apim-백엔드-등록-3개) |
| `modules/apim.bicep` (pool) | Backend Pool | `openai-backend-pool` | [10](#10-백엔드-풀-구성) |
| `policies/*.xml` | APIM Policies | API 정책 편집기 | [11](#11-api-등록-및-정책-적용) |

---

## 정리 (Clean Up)

모든 리소스를 삭제하려면:

1. 상단 검색창 → **리소스 그룹** 검색 → 클릭
2. `rg-ai-gw-{suffix}` 선택
3. **리소스 그룹 삭제** 클릭
4. 리소스 그룹 이름(`rg-ai-gw-{suffix}`) 입력하여 확인
5. **삭제** 클릭

> ⚠️ 리소스 그룹 삭제는 그 안의 모든 리소스를 함께 삭제합니다. 복구할 수 없으니 주의하세요.

---

## 트러블슈팅

### APIM → OpenAI 호출 시 401 Unauthorized

- **원인**: Managed Identity 역할 할당이 안 됨
- **확인**: 각 OpenAI 리소스의 **액세스 제어(IAM)** → **역할 할당** 탭에서 `apim-ai-gateway-dev`이 `Cognitive Services OpenAI User` 역할인지 확인
- **해결**: [7단계](#7-apim-managed-identity--openai-rbac-설정) 재수행

### APIM 테스트 콘솔에서 404 Not Found

- **원인**: API URL 접미사 또는 작업 URL 템플릿이 잘못됨
- **확인**: API 접미사가 `openai`, 작업 URL이 `/deployments/{deployment-id}/chat/completions`인지 확인
- **확인**: `api-version` 쿼리 파라미터가 전달되고 있는지 확인

### 응답 헤더에 x-backend-url이 없음

- **원인**: outbound 정책에 `set-header` 가 빠져 있음
- **해결**: [11-3 정책 적용](#11-3-로드밸런서-정책-적용) 확인 후 outbound 섹션에 `set-header` 추가

### 429 Too Many Requests

- **원인**: Azure OpenAI 모델의 TPM(분당 토큰) 한도 초과
- **확인**: 각 OpenAI 리소스의 모델 배포 → TPM 한도 확인 (기본 30K)
- **해결**: APIM의 Circuit Breaker + 백엔드 풀이 정상 동작하면 다른 리전으로 자동 Failover됩니다
