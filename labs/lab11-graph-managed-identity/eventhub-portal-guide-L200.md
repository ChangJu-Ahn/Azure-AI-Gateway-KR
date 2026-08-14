# Event Hub 포털에서 보기 — L200 가이드

> **목적**: Event Hub에 쌓인 이벤트(이 데모에선 *정책 감사 레코드* + *진단 GatewayLogs*)를 **코드 없이 Azure Portal에서 눈으로** 확인하는 방법.
> Event Hub가 처음인 분을 위한 L200(개념 + 실습 클릭 경로) 수준입니다.
>
> **이 데모 리소스**: 네임스페이스 `ehnsgraphauditb0f20289` (koreacentral, Standard) · 이벤트 허브 `graph-audit` (파티션 2) · 소비자 그룹 `$Default`

---

## 1. 30초 개념 정리 (헷갈리는 용어부터)

| 용어 | 한 줄 정의 | 이 데모 |
|------|-----------|---------|
| **Namespace(네임스페이스)** | Event Hub들을 담는 "서버/컨테이너" | `ehnsgraphauditb0f20289` |
| **Event Hub(이벤트 허브)** | 실제 이벤트가 흐르는 "스트림/토픽" | `graph-audit` |
| **Partition(파티션)** | 병렬 처리·순서 보장 단위(허브를 쪼갠 레인) | 2개 |
| **Consumer Group(소비자 그룹)** | 읽는 쪽의 독립 "커서" 묶음 | `$Default` |
| **Retention(보존)** | 이벤트가 허브에 남아있는 기간 | Standard 기본 1~7일 |
| **Throughput Unit(TU)** | 처리량·**과금** 단위 | 1 TU (~$0.03/시간) |

> **핵심 구분**: 포털 작업은 두 종류입니다.
> - **관리(Management)**: 네임스페이스·허브 **생성/삭제/설정** → 보통 Contributor 권한.
> - **데이터(Data)**: 이벤트 **보내기/보기** → **별도의 데이터 권한(RBAC 역할 또는 SAS)** 필요. ← 이 문서의 주제.

---

## 2. 먼저: "보기" 권한 확인 (안 되면 여기부터)

이벤트를 **보려면** 관리 권한만으론 부족하고 아래 중 하나가 필요합니다.

- **RBAC 역할**: `Azure Event Hubs Data Receiver`(보기) / `Azure Event Hubs Data Sender`(보내기)
- 또는 **SAS**(로컬 인증)가 켜져 있어야 함 (`disableLocalAuth=false`)

**부여 방법(포털)**: 네임스페이스 → **Access control (IAM)** → **+ Add** → **Add role assignment** → 역할 `Azure Event Hubs Data Receiver` 선택 → 본인 계정 지정 → 저장. (전파에 수 분)

> 이 데모 환경엔 이미: APIM 관리 ID = `Data Sender`, 사용자 계정 = `Data Receiver` 부여됨. (SAS도 현재 활성)

---

## 3. Data Explorer 열기 — 포털에서 이벤트를 보는 핵심 도구

**Data Explorer**는 코드 없이 이벤트를 **보고(View)·보내는(Send)** 포털 내장 도구입니다.

**경로 A (권장)**: 포털 → 네임스페이스 `ehnsgraphauditb0f20289` → 왼쪽 메뉴 **Data Explorer** → 목록에서 `graph-audit` 선택

**경로 B**: 네임스페이스 → **Entities → Event Hubs** → `graph-audit` 클릭 → 왼쪽 메뉴 **Data Explorer**

> ⚠️ 네임스페이스가 Private Endpoint 전용이면 같은 VNet의 VM 브라우저에서 접근해야 합니다. (이 데모는 퍼블릭이라 무관)

---

## 4. 이벤트 보기 (View events) — 클릭 순서

Data Explorer 화면에서 **View events** 선택 후:

1. **PartitionID**: `All partition IDs` (전체에서 보기)
2. **Consumer Group**: `$Default`
3. **Event position**(어디서부터 읽나):
   - **Oldest position** — 허브에 남아있는 **가장 오래된 것부터** (처음 볼 때 권장)
   - **Newest position** — **지금 이후 새로 들어오는 것만**
   - **Custom position** — 특정 offset·sequence·**타임스탬프**부터
4. (선택) **Advanced**: Maximum batch size / Maximum wait time(초)
5. **View events** 클릭 → 아래 **그리드에 이벤트 목록** 표시
6. 특정 이벤트 클릭 → 오른쪽에 **본문(payload)** 표시 → 상단 **Download**로 저장 가능
7. 더 보려면 **View next events**, 초기화는 **Clear all**

> 팁: "방금 만든 트래픽만" 보고 싶으면 → **트래픽 생성 전에** Data Explorer를 `Newest position`으로 열어두거나, `Custom position`에 최근 타임스탬프를 넣으세요.

---

## 5. 이 데모에 대입 — 그리드에서 두 이벤트 모양 구분하기

**① 트래픽 만들기** (이벤트를 발생시켜야 보임): APIM을 통해 Graph를 호출합니다.
- 노트북 셀로 호출하거나, 브라우저/`curl`로:
  `GET https://apim-ai-gw-aigateway-20260716.azure-api.net/graph/users?$top=2`
  헤더 `Ocp-Apim-Subscription-Key: <graph-users 구독키>`

**② Data Explorer에서 보면 두 종류가 섞여 있습니다:**

- **정책 이벤트** (`log-to-eventhub` 정책이 만든 것 — **body/커스텀 필드 있음**):
  ```json
  {"ts":"...","requestId":"...","phase":"outbound","product":"graph-users",
   "path":"/graph/users","identity":"system-assigned",
   "backendUrl":"https://graph.microsoft.com/v1.0/users?...","responseCode":200}
  ```
- **진단 이벤트** (진단설정 GatewayLogs — **플랫폼 고정 스키마, body 없음**):
  ```json
  {"records":[{"category":"GatewayLogs",
    "operationName":"Microsoft.ApiManagement/GatewayLogs",
    "Sku":"Developer","durationMs":20,"isRequestSuccess":true,"time":"..."}]}
  ```

**구분 요령**: 최상위에 `"records"` 배열 + 안에 `"category":"GatewayLogs"`가 있으면 **진단**, 그런 봉투 없이 우리가 만든 커스텀 JSON이면 **정책**입니다.

> 배우는 포인트: **같은 허브**인데 한쪽(정책)은 본문·커스텀 필드가 있고, 다른 쪽(진단)은 고정 필드뿐입니다 → **"본문은 목적지가 아니라 소스(정책)가 만든다"**.

---

## 6. 내용 말고 "양"만 빠르게 보기 — Metrics

이벤트 **내용**은 필요 없고 "들어오고 있나"만 확인하려면:

- 네임스페이스(또는 허브) → **Metrics** → 지표 선택:
  - `Incoming Messages` / `Outgoing Messages` (건수)
  - `Incoming Bytes` / `Outgoing Bytes` (용량)
- **Overview** 블레이드에도 요약 차트가 있습니다.
- 차트는 **1~2분 지연**될 수 있습니다.

---

## 7. (참고) Send events — 테스트 이벤트 직접 주입

데모 트래픽 없이도 흐름을 시험하려면: Data Explorer → **Send events** → `Custom payload` → Content-Type `JSON` → 본문 입력 → **Send** (또는 **Repeat send**로 여러 건). 그 후 **View events**로 확인.

---

## 8. (참고) 그 외에 "보는" 방법

| 방법 | 언제 | 비고 |
|------|------|------|
| **Data Explorer** | 지금처럼 눈으로 즉시 확인 | 큰 메시지엔 부적합(타임아웃) |
| **Metrics / Overview** | 양·추세만 | 내용 안 보임 |
| **Process data (Stream Analytics no-code)** | 실시간 필터/변환 미리보기 | 별도 리소스 |
| **Capture → Blob/ADLS** | 전문을 파일로 장기 보관 | 이 데모는 **미활성** |
| **코드 소비(azure-eventhub SDK)** | 자동화·대량 | 이 데모 검증에 사용한 방식 |

---

## 9. 주의 / 비용

- **큰 메시지**는 Data Explorer 대신 SDK 사용(타임아웃 방지).
- **권한(RBAC)**에 따라 보기/보내기 가능 범위가 갈립니다.
- **Standard 네임스페이스는 켜져 있는 동안 과금**(~$0.03/시간 ≈ $22/월). 데모가 끝나면:
  `az eventhubs namespace delete -g rg-ai-gw-aigateway-20260716 -n ehnsgraphauditb0f20289`

---

## 부록: 이 데모 리소스 요약

| 항목 | 값 |
|------|-----|
| 네임스페이스 | `ehnsgraphauditb0f20289` (koreacentral, Standard) |
| 이벤트 허브 | `graph-audit` (파티션 2) |
| 소비자 그룹 | `$Default` |
| 데이터 역할 | APIM 관리 ID = `Data Sender` · 사용자 = `Data Receiver` |
| 들어오는 이벤트 | 정책(`log-to-eventhub`, body 있음) + 진단(`GatewayLogs`, body 없음) |

*출처: [Send and view events with Event Hubs Data Explorer (Microsoft Learn)](https://learn.microsoft.com/azure/event-hubs/event-hubs-data-explorer)*
