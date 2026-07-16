# 멀티 클라우드 AI Gateway & 통합 관측 랩 (Lab 8–10 + Lab 6 패치) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 APIM AI Gateway 랩 시리즈에 멀티 클라우드 통합(Lab 8) · 구독 격리(Lab 9) · 통합 관측/거버넌스(Lab 10) 드래프트 랩을 추가하고, Lab 6 로깅 한계를 정직하게 패치하며, cleanup 랩을 lab11로 재번호한다.

**Architecture:** 단일 OpenAI 호환 엔드포인트가 4개 프로바이더(Azure OpenAI · OpenAI · Anthropic · Gemini)를 프론트한다. 프로바이더 무관 `llm-*` 정책으로 토큰 제어·메트릭·캐시를 동일 적용하고, Products/Developer Portal로 subscriber를 격리하며, Azure Monitor Workbook + Event Hub 로깅으로 모든 프로토콜을 관측한다.

**Tech Stack:** Azure API Management(정책 XML), Bicep, Azure Monitor / Application Insights / Log Analytics(KQL), Event Hub, Jupyter(테스트 노트북, 초안은 선택), Markdown(한국어 랩 문서).

## Global Constraints

- **산출물 범위:** 초안(draft) README + 실제/정확한 스니펫까지. E2E 배포·실행 검증은 후속 태스크(본 계획 범위 밖). 각 README는 그 사실을 상단 배지로 명시("🚧 드래프트 — 실제 키 확보 후 E2E 검증 예정").
- **언어:** 모든 랩 문서는 **한국어**, 기존 랩 포맷(제목 → 개요 → 목표 → 아키텍처 mermaid → 실습 단계 → 핵심 개념 → 다음 단계) 준수.
- **정책 네이밍:** 신규 프로바이더 무관 정책은 `llm-*` 접두사. 기존 `azure-openai-*` 조각은 **삭제하지 않고 보존**(하위 랩 호환).
- **시크릿:** 모든 키는 APIM **Named Value(secret)** 로 등록, 클라이언트 비노출. `.env.sample`에 자리표시자만 추가.
- **랩 번호:** 신규 8/9/10, cleanup 기존 lab08 → **lab11**. gap 없음, cleanup은 항상 마지막.
- **폴더명:** `labs/lab08-multicloud-gateway/`, `labs/lab09-products-portal/`, `labs/lab10-governance-observability/`, `labs/lab11-cleanup/`.
- **XML well-formedness:** 모든 정책 조각은 `xmllint --noout`을 통과해야 한다. 정책 표현식의 `&`는 `&amp;`로 이스케이프하거나 `&&` 대신 사전 계산 변수 비교를 사용한다.
- **커밋:** 태스크 단위 커밋. 커밋 메시지에 아래 트레일러 포함:
  ```
  Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
  Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063
  ```
- **참조 스펙:** `docs/superpowers/specs/2026-07-16-multicloud-observability-labs-design.md`

---

## File Structure

**신규 생성:**
- `policies/fragments/llm-token-limit.xml` — 프로바이더 무관 토큰 제한
- `policies/fragments/llm-emit-token-metrics.xml` — 프로바이더 무관 토큰 메트릭 (+ Provider 차원)
- `policies/fragments/llm-semantic-cache.xml` — 프로바이더 무관 시맨틱 캐시(참고용, lookup+store 주석 포함)
- `policies/fragments/model-routing.xml` — `model` prefix 기반 백엔드 라우팅 + 인증 주입
- `policies/fragments/quota-by-key.xml` — 구독별 월 quota
- `labs/lab08-multicloud-gateway/README.md`
- `labs/lab09-products-portal/README.md`
- `labs/lab10-governance-observability/README.md`
- `docs/developer-portal-guide.md`

**수정:**
- `labs/lab06-monitoring/README.md` — 로깅 한계 섹션 + `bytes 4096→8192` + Lab 10 전방 참조
- `labs/lab07-advanced-patterns/README.md:190` — 다음 단계 링크 `lab08-cleanup` → `lab08-multicloud-gateway`
- `.env.sample` — Lab 8 신규 프로바이더 키 자리표시자
- `README.md`(루트) — 진행 상태 표, 비즈니스 시나리오, 폴더 트리, cleanup 링크(lab08→lab11) 갱신

**이동(rename):**
- `labs/lab08-cleanup/` → `labs/lab11-cleanup/` (git mv)

**태스크 의존성:** T1(정책 조각) → T2(Lab 8) → T3(Lab 9) → T4(Lab 10). T5(Lab 6 패치)·T6(재번호+루트 README)는 T1–T4 이후 수행하되 상호 독립.

---

### Task 1: 프로바이더 무관 `llm-*` 정책 조각 생성

**Files:**
- Create: `policies/fragments/llm-token-limit.xml`
- Create: `policies/fragments/llm-emit-token-metrics.xml`
- Create: `policies/fragments/llm-semantic-cache.xml`
- Create: `policies/fragments/model-routing.xml`
- Create: `policies/fragments/quota-by-key.xml`

**Interfaces:**
- Produces: 정책 조각 파일 5개. 후속 랩(T2–T4)에서 파일 경로와 정책 XML을 인용한다.
  - `llm-token-limit`: 속성 `counter-key`, `tokens-per-minute`, `estimate-prompt-tokens`, `remaining-tokens-header-name`
  - `llm-emit-token-metric`: `namespace="ai-gateway-metrics"`, 차원 `Subscription ID / Provider / Model / API ID / Client IP`
  - `model-routing`: 변수 `provider`(문자열), 변수 `modelName`(prefix 제거 결과)
  - `quota-by-key`: `counter-key="@(context.Subscription.Id)"`, `renewal-period`, `calls`/`bandwidth` 기반 (호출/대역폭); 월 누적 토큰 총량은 `llm-token-limit`의 `token-quota`/`token-quota-period` 사용

- [ ] **Step 1: `llm-token-limit.xml` 작성**

`policies/fragments/llm-token-limit.xml`:
```xml
<!-- 프로바이더 무관 토큰 기반 Rate Limiting 정책 조각 -->
<!-- azure-openai-token-limit 과 달리 OpenAI 호환 usage 를 반환하는 모든 백엔드에 적용 가능 -->
<!-- 적용 위치: Inbound -->
<fragment>
    <llm-token-limit
        counter-key="@(context.Subscription.Id)"
        tokens-per-minute="10000"
        estimate-prompt-tokens="true"
        remaining-tokens-variable-name="remainingTokens"
        remaining-tokens-header-name="x-ratelimit-remaining-tokens"
        tokens-consumed-variable-name="tokensConsumed"
        tokens-consumed-header-name="x-ratelimit-tokens-consumed" />
</fragment>
```

- [ ] **Step 2: `llm-emit-token-metrics.xml` 작성**

`policies/fragments/llm-emit-token-metrics.xml`:
```xml
<!-- 프로바이더 무관 토큰 메트릭 수집 정책 조각 -->
<!-- Provider 차원을 추가해 멀티 클라우드에서 프로바이더별 토큰을 구분 -->
<!-- 적용 위치: Inbound (공식 문서 기준). 커스텀 dimension 은 정책당 최대 5개 -->
<fragment>
    <llm-emit-token-metric namespace="ai-gateway-metrics">
        <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
        <dimension name="Provider" value="@((string)context.Variables.GetValueOrDefault(&quot;provider&quot;, &quot;unknown&quot;))" />
        <dimension name="Model" value="@((string)context.Variables.GetValueOrDefault(&quot;modelName&quot;, &quot;unknown&quot;))" />
        <dimension name="API ID" value="@(context.Api.Id)" />
        <dimension name="Client IP" value="@(context.Request.IpAddress)" />
    </llm-emit-token-metric>
</fragment>
```

- [ ] **Step 3: `model-routing.xml` 작성**

`policies/fragments/model-routing.xml`:
```xml
<!-- model prefix 기반 백엔드 라우팅 + 프로바이더별 인증 주입 -->
<!-- 클라이언트는 OpenAI 포맷으로 model 필드에 "provider/model" 을 전송 -->
<!--   예: "openai/gpt-4o", "anthropic/claude-3-5-sonnet-20241022", -->
<!--       "gemini/gemini-2.0-flash" -->
<!--   prefix 없으면 Azure OpenAI(기본)로 라우팅 -->
<!-- 적용 위치: Inbound -->
<fragment>
    <set-variable name="rawModel" value="@{
        var body = context.Request.Body?.As<JObject>(preserveContent: true);
        return body != null &amp;&amp; body["model"] != null ? body["model"].ToString() : "";
    }" />
    <set-variable name="provider" value="@{
        var m = (string)context.Variables["rawModel"];
        return m.Contains("/") ? m.Split('/')[0] : "azure";
    }" />
    <set-variable name="modelName" value="@{
        var m = (string)context.Variables["rawModel"];
        return m.Contains("/") ? m.Substring(m.IndexOf('/') + 1) : m;
    }" />
    <choose>
        <when condition="@((string)context.Variables[&quot;provider&quot;] == &quot;openai&quot;)">
            <set-backend-service backend-id="openai-direct-backend" />
            <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + "{{openai-api-key}}")</value>
            </set-header>
        </when>
        <when condition="@((string)context.Variables[&quot;provider&quot;] == &quot;anthropic&quot;)">
            <set-backend-service backend-id="anthropic-backend" />
            <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + "{{anthropic-api-key}}")</value>
            </set-header>
        </when>
        <when condition="@((string)context.Variables[&quot;provider&quot;] == &quot;gemini&quot;)">
            <set-backend-service backend-id="gemini-backend-pool" />
            <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + "{{gemini-api-key-1}}")</value>
            </set-header>
        </when>
        <otherwise>
            <set-backend-service backend-id="openai-backend-pool" />
            <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
        </otherwise>
    </choose>
    <!-- 백엔드가 기대하는 실제 model 값으로 재작성 (provider/ prefix 제거) -->
    <set-body>@{
        var body = context.Request.Body.As<JObject>(preserveContent: true);
        body["model"] = (string)context.Variables["modelName"];
        return body.ToString();
    }</set-body>
</fragment>
```

- [ ] **Step 4: `llm-semantic-cache.xml` 작성**

`policies/fragments/llm-semantic-cache.xml`:
```xml
<!-- 프로바이더 무관 시맨틱 캐시 (참고용) -->
<!-- 별도 배포 필요: 임베딩 모델 + Azure Redis (scripts/deploy-semantic-caching.sh) -->
<!-- lookup 은 Inbound, store 는 Outbound 에 배치 -->
<fragment>
    <!-- Inbound 에 배치:
    <llm-semantic-cache-lookup
        score-threshold="0.8"
        embeddings-backend-id="embedding-backend"
        embeddings-backend-auth="system-assigned" />
    -->
    <!-- Outbound 에 배치:
    <llm-semantic-cache-store duration="3600" />
    -->
</fragment>
```

- [ ] **Step 5: `quota-by-key.xml` 작성**

`policies/fragments/quota-by-key.xml`:
```xml
<!-- 구독별 월 quota 정책 조각 -->
<!-- llm-token-limit(분당 TPM)과 조합: 단기 스파이크는 TPM, 장기 총량은 quota 로 제어 -->
<!-- 적용 위치: Inbound (Product 정책에 배치 권장) -->
<fragment>
    <quota-by-key
        calls="10000"
        renewal-period="2592000"
        counter-key="@(context.Subscription.Id)" />
</fragment>
```

- [ ] **Step 6: 모든 조각의 XML well-formedness 검증**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
for f in policies/fragments/llm-token-limit.xml policies/fragments/llm-emit-token-metrics.xml policies/fragments/llm-semantic-cache.xml policies/fragments/model-routing.xml policies/fragments/quota-by-key.xml; do
  xmllint --noout "$f" && echo "OK: $f"
done
```
Expected: 5줄 모두 `OK: ...` 출력, 에러 없음.

- [ ] **Step 7: 커밋**

```bash
git add policies/fragments/llm-token-limit.xml policies/fragments/llm-emit-token-metrics.xml policies/fragments/llm-semantic-cache.xml policies/fragments/model-routing.xml policies/fragments/quota-by-key.xml
git commit -m "feat(policies): add provider-agnostic llm-* policy fragments for multi-cloud gateway

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063"
```

---

### Task 2: Lab 8 — 멀티 클라우드 통합 게이트웨이 README

**Files:**
- Create: `labs/lab08-multicloud-gateway/README.md`

**Interfaces:**
- Consumes: T1의 `model-routing.xml`, `llm-token-limit.xml`, `llm-emit-token-metrics.xml`, 기존 `retry-with-fallback.xml`/`circuit-breaker.xml`.
- Produces: 통합 API 개념(`POST {gateway}/openai/v1/chat/completions`)과 `model` prefix 규칙. Lab 9/10이 이 API를 참조.

- [ ] **Step 1: README 스켈레톤 작성 (기존 랩 포맷 준수)**

`labs/lab08-multicloud-gateway/README.md`에 아래 순서/헤딩으로 작성한다. 상단에 드래프트 배지 포함:
```markdown
# Lab 8: 멀티 클라우드 통합 게이트웨이

> 🚧 **드래프트** — 스니펫은 정확하나, 실제 프로바이더 키 확보 후 E2E 검증 예정입니다.

하나의 OpenAI 호환 엔드포인트로 Azure OpenAI(기본) 와 Azure 외부의 OpenAI · Anthropic · Google Gemini를 통합 관리합니다. 클라이언트는 `model` 필드만 바꾸면 프로바이더가 전환되고, 게이트웨이가 토큰 제어·메트릭·Fallback을 동일하게 적용합니다.

## 목표
- Azure OpenAI(기본) + Azure 외부 3사(OpenAI·Anthropic·Google Gemini)를 단일 OpenAI 호환 API 로 통합 (Approach A: 통합 계약)
- 프로바이더별 백엔드 풀로 로드밸런싱 (Lab 3/5 개념 재사용)
- 프로바이더 무관 `llm-*` 정책으로 토큰 제어·메트릭 통일 (+ Provider 차원)
- 크로스클라우드 Fallback
- 외부 3사(OpenAI·Anthropic·Google Gemini)는 모두 OpenAI 호환 엔드포인트를 제공 → 별도 SDK 없이 동일 계약으로 통합

## 왜 llm-* 정책인가 (azure-openai-* 와 차이)
## 아키텍처
## 사전 준비 (.env / Named Value)
## 실습 단계
## 핵심 개념
## 다음 단계
```

- [ ] **Step 2: "왜 llm-* 정책인가" 비교 표 삽입**

```markdown
| | `azure-openai-*` (Lab 4/6) | `llm-*` (이번 Lab) |
|---|---|---|
| 대상 백엔드 | Azure OpenAI 전용 | OpenAI 호환 usage 를 반환하는 **모든** 프로바이더 |
| 토큰 제한 | `azure-openai-token-limit` | `llm-token-limit` |
| 토큰 메트릭 | `azure-openai-emit-token-metric` | `llm-emit-token-metric` (+ Provider 차원) |
| 시맨틱 캐시 | `azure-openai-semantic-cache-*` | `llm-semantic-cache-*` |

> 💡 OpenAI·Anthropic·Gemini 는 모두 OpenAI 호환 응답의 `usage` 필드를 반환하므로,
> `llm-*` 정책이 프로바이더와 무관하게 동일하게 토큰을 계량합니다.
```

- [ ] **Step 3: 아키텍처 mermaid 삽입**

```markdown
​```mermaid
graph TD
    Client["클라이언트<br/>OpenAI SDK · model 만 변경"] -->|Ocp-Apim-Subscription-Key| GW["APIM 통합 게이트웨이<br/>/openai/v1/chat/completions"]
    GW -->|model prefix 라우팅| R{provider}
    R -->|azure / (기본)| AOAI["Azure OpenAI 풀<br/>Lab3 재사용 · Managed Identity"]
    R -->|openai/*| OAI["OpenAI 직접"]
    R -->|anthropic/*| ANT["Anthropic"]
    R -->|gemini/*| GEM["Gemini 풀<br/>Lab5 재사용"]
    AOAI & OAI & ANT & GEM -.->|429/5xx 시 retry| FB["Fallback"]
​```
```

- [ ] **Step 4: 프로바이더 통합 표 + 엔드포인트/모델 삽입**

아래 표를 삽입하고, 각 값 옆에 "⚠️ 리전/모델 ID는 콘솔에서 확인" 주석을 단다:
```markdown
| 프로바이더 | 백엔드 URL | 인증 | model 필드 예시 |
|---|---|---|---|
| Azure OpenAI | 기존 풀 (Lab 2/3) | Managed Identity | `gpt-4.1-nano` (prefix 없음) |
| OpenAI 직접 | `https://api.openai.com/v1` | `Bearer {{openai-api-key}}` | `openai/gpt-4o` |
| Anthropic | `https://api.anthropic.com/v1` | `Bearer {{anthropic-api-key}}` | `anthropic/claude-3-5-sonnet-20241022` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | `Bearer {{gemini-api-key-1}}` | `gemini/gemini-2.0-flash` |

> ⚠️ OpenAI·Anthropic·Gemini 모델명은 각 콘솔에서 최신 값을 확인하세요.
> 세 프로바이더 모두 OpenAI 호환 `/openai/v1/chat/completions` 경로를 지원하므로
> 별도 SDK·서명 로직 없이 동일 계약으로 통합됩니다.
```

- [ ] **Step 5: 실습 단계 — Named Value 등록 (az CLI)**

```markdown
### 1단계: 프로바이더 키를 Named Value(secret)로 등록

​```bash
set -a; source .env; set +a

az apim nv create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --named-value-id openai-api-key --display-name "OpenAI-API-Key" \
  --value "$OPENAI_API_KEY" --secret true

az apim nv create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --named-value-id anthropic-api-key --display-name "Anthropic-API-Key" \
  --value "$ANTHROPIC_API_KEY" --secret true
​```

> Gemini 키(`gemini-api-key-1..3`)는 Lab 5에서 이미 등록되어 있습니다.
```

- [ ] **Step 6: 실습 단계 — 백엔드 등록 (az CLI)**

```markdown
### 2단계: 프로바이더별 백엔드 등록

​```bash
# OpenAI 직접
az apim backend create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --backend-id openai-direct-backend --protocol http \
  --url "https://api.openai.com/v1"

# Anthropic
az apim backend create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --backend-id anthropic-backend --protocol http \
  --url "https://api.anthropic.com/v1"
​```

> `openai-backend-pool`(Azure OpenAI)·`gemini-backend-pool`(Gemini)은 Lab 3/5에서 구성됨.
> 각 프로바이더에 여러 키/리전을 두려면 Lab 3 방식으로 backend pool 을 구성해 로드밸런싱합니다.
```

- [ ] **Step 7: 실습 단계 — 통합 API 정책 (라우팅 + llm-* + retry) 삽입**

전체 정책을 코드뷰로 제시한다. T1의 조각들을 인라인으로 합친 형태:
```markdown
### 3단계: 통합 API 등록 & 정책 적용

`/openai/v1/chat/completions` 경로의 API를 만들고, 아래 정책을 적용합니다.
개별 조각은 `policies/fragments/model-routing.xml`, `llm-token-limit.xml`, `llm-emit-token-metrics.xml` 참고.

​```xml
<policies>
    <inbound>
        <base />
        <!-- 구독별 토큰 제한 (프로바이더 무관) -->
        <llm-token-limit counter-key="@(context.Subscription.Id)"
            tokens-per-minute="10000" estimate-prompt-tokens="true"
            remaining-tokens-header-name="x-ratelimit-remaining-tokens" />
        <!-- model prefix 라우팅 + 인증 주입 (policies/fragments/model-routing.xml) -->
        <include-fragment fragment-id="model-routing" />
        <!-- 토큰 메트릭 (+ Provider 차원) -->
        <include-fragment fragment-id="llm-emit-token-metrics" />
    </inbound>
    <backend>
        <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)"
               count="3" interval="1" max-interval="10" delta="1" first-fast-retry="false">
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
​```

> `include-fragment`를 쓰려면 각 조각을 먼저 APIM Policy Fragment 로 등록해야 합니다.
> (Portal → APIM → Policy fragments → + Create, 또는 `az apim policy-fragment create`)
```

- [ ] **Step 8: 실습 단계 — 테스트 스니펫 + 핵심 개념 + 다음 단계**

```markdown
### 4단계: 테스트 (동일 SDK, model 만 변경)

​```python
from openai import OpenAI
client = OpenAI(base_url="https://<apim>.azure-api.net/openai/v1",
                api_key="<APIM_SUBSCRIPTION_KEY>")  # Ocp-Apim-Subscription-Key 로 전달되도록 설정

for model in ["gpt-4.1-nano", "openai/gpt-4o",
              "anthropic/claude-3-5-sonnet-20241022", "gemini/gemini-2.0-flash"]:
    r = client.chat.completions.create(model=model,
        messages=[{"role": "user", "content": "안녕하세요"}])
    print(model, "→", r.choices[0].message.content[:40], "| tokens:", r.usage.total_tokens)
​```

## 핵심 개념
- 통합 OpenAI 계약: 클라이언트는 `model` 만 바꾼다
- `llm-*` 정책이 프로바이더와 무관하게 토큰을 계량·제한
- Provider 차원으로 멀티 클라우드 토큰을 구분 관측 (→ Lab 10)

## 다음 단계
→ [Lab 9: Products & 개발자 포털](../lab09-products-portal/README.md)
```

- [ ] **Step 9: 링크·mermaid 검증**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
test -f labs/lab08-multicloud-gateway/README.md && echo "README exists"
grep -c '```mermaid' labs/lab08-multicloud-gateway/README.md
grep -n 'lab09-products-portal' labs/lab08-multicloud-gateway/README.md
```
Expected: "README exists", mermaid 블록 ≥1, 다음 단계 링크 1건.

- [ ] **Step 10: 커밋**

```bash
git add labs/lab08-multicloud-gateway/README.md
git commit -m "docs(lab08): add multi-cloud unified gateway draft lab

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063"
```

---

### Task 3: Lab 9 — Products & 개발자 포털 README + 포털 가이드

**Files:**
- Create: `labs/lab09-products-portal/README.md`
- Create: `docs/developer-portal-guide.md`

**Interfaces:**
- Consumes: T1의 `llm-token-limit.xml`, `quota-by-key.xml`; T2의 통합 API(`/openai/v1`).
- Produces: Product 2개(예: `team-a`, `team-b`) + 구독 격리 개념. Lab 10이 Product/구독 차원을 관측에 사용.

- [ ] **Step 1: README 스켈레톤 + 목표**

`labs/lab09-products-portal/README.md`:
```markdown
# Lab 9: Products & 개발자 포털 (구독 격리)

> 🚧 **드래프트** — 스니펫은 정확하나, 실제 배포 후 E2E 검증 예정입니다.

APIM Products · Subscriptions · Developer Portal 로 각 팀이 **격리된 구독 키**를 셀프서비스로 발급받게 합니다. API 접근과 토큰 예산을 subscriber 별로 격리합니다.

## 목표
- Product 로 API + 정책 + 구독요건을 묶기
- Product 별 **토큰 예산**(`llm-token-limit`: 분당 TPM + 월 토큰 quota) + **요청 예산**(`quota-by-key`: 월 호출 수) 적용
- Developer Portal 게시 & 셀프서비스 구독
- 2개 구독으로 격리(키/TPM/메트릭 분리) 검증

## Product 설계
## 아키텍처
## 실습 단계
## 핵심 개념
## 다음 단계
```

- [ ] **Step 2: Product 설계 결정 문서화 (팀형 기본)**

```markdown
## Product 설계

이 Lab 은 **팀형** Product 를 기본 예시로 사용합니다.

| Product | 대상 | 분당 토큰(TPM) | 월 quota | 구독 승인 |
|---|---|---|---|---|
| `team-a` | 팀 A | 10,000 | 10,000,000 | 자동 |
| `team-b` | 팀 B | 2,000 | 2,000,000 | 관리자 승인 |

> 💡 티어형(`free`/`standard`)으로 바꾸려면 Product 이름과 한도만 교체하면 됩니다.
> 두 Product 모두 Lab 8의 통합 API 를 포함합니다.
```

- [ ] **Step 3: 아키텍처 mermaid 삽입**

```markdown
​```mermaid
graph TD
    subgraph Portal["Developer Portal (셀프서비스)"]
        DevA["팀 A 개발자"] -->|구독 신청| PA["Product team-a"]
        DevB["팀 B 개발자"] -->|구독 신청| PB["Product team-b"]
    end
    PA -->|Subscription Key A| API["Lab 8 통합 API<br/>/openai/v1"]
    PB -->|Subscription Key B| API
    PA -. "TPM 10k · quota 10M" .- API
    PB -. "TPM 2k · quota 2M" .- API
​```
```

- [ ] **Step 4: 실습 단계 — Product 생성 & API 연결 (az CLI)**

```markdown
## 실습 단계

### 1단계: Product 생성 & 통합 API 연결

​```bash
# team-a: 자동 승인
az apim product create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --product-id team-a --product-name "Team A" \
  --subscription-required true --approval-required false --state published

# team-b: 관리자 승인
az apim product create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --product-id team-b --product-name "Team B" \
  --subscription-required true --approval-required true --state published

# 통합 API 를 각 Product 에 추가 (API_ID 는 Lab 8에서 만든 API 이름)
az apim product api add --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --product-id team-a --api-id multicloud-openai
az apim product api add --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --product-id team-b --api-id multicloud-openai
​```
```

- [ ] **Step 5: 실습 단계 — Product 정책 (구독별 TPM + quota)**

```markdown
### 2단계: Product 정책 — 구독별 TPM + 월 quota

Portal → APIM → Products → team-a → Policies (또는 `az apim product` REST). team-a 예시:

​```xml
<policies>
    <inbound>
        <base />
        <!-- 토큰 기반 제어: 분당 TPM(429) + 월 토큰 총량(403) -->
        <llm-token-limit counter-key="@(context.Subscription.Id)"
            tokens-per-minute="10000"
            token-quota="10000000" token-quota-period="Monthly"
            estimate-prompt-tokens="true"
            remaining-tokens-header-name="x-ratelimit-remaining-tokens"
            remaining-quota-tokens-header-name="x-quota-remaining-tokens" />
        <!-- 요청 기반 제어: 월 호출 수 상한 -->
        <quota-by-key calls="100000" renewal-period="2592000"
            counter-key="@(context.Subscription.Id)" />
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
​```

> team-b 는 `tokens-per-minute="2000"`, `calls="2000000"` 으로 낮춰 차등 적용합니다.
> `counter-key`가 `context.Subscription.Id` 이므로 **구독마다 독립된 카운터**가 유지됩니다(격리).
```

- [ ] **Step 6: 실습 단계 — 구독 생성 & 격리 테스트 + 다음 단계**

```markdown
### 3단계: 구독 생성 & 키 발급

​```bash
az apim subscription create --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --name sub-team-a --display-name "Sub Team A" \
  --scope "/products/team-a"
# Primary key 확인
az apim subscription show --resource-group $RESOURCE_GROUP --service-name $APIM_NAME \
  --sid sub-team-a --query primaryKey -o tsv
​```

### 4단계: 격리 검증
- 두 구독 키로 각각 호출 → 한 팀이 TPM 을 소진해도 다른 팀은 영향 없음
- `x-ratelimit-remaining-tokens` 헤더가 구독별로 독립적으로 감소

## 핵심 개념
- Product = API + 정책 + 구독요건 묶음
- 구독 키 = subscriber 격리의 단위 (API 접근 + 토큰 카운터)
- Developer Portal = 셀프서비스 구독 창구 → docs/developer-portal-guide.md

## 다음 단계
→ [Lab 10: 구독별 거버넌스 & Azure Monitor 대시보드](../lab10-governance-observability/README.md)
```

- [ ] **Step 7: `docs/developer-portal-guide.md` 작성**

기존 `docs/portal-deployment-guide.md` 톤을 따라 한국어로 작성. 최소 섹션:
```markdown
# 개발자 포털(Developer Portal) 게시 가이드

APIM 개발자 포털을 활성화·브랜딩·게시하여 팀이 셀프서비스로 구독하게 합니다.

## 1. 포털 관리 콘솔 열기
Azure Portal → API Management → **Developer portal** → **Developer portal (관리)** 클릭.

## 2. 콘텐츠 편집 & 브랜딩
- 홈/제품/API 페이지 편집, 로고·색상 적용

## 3. 게시(Publish)
- 관리 콘솔 상단 **Publish** 클릭 → 변경사항 공개

## 4. 회원가입 & 구독 흐름
1. 개발자가 포털에서 Sign up → 이메일 인증
2. Products → team-a → **Subscribe**
3. team-a(자동 승인)는 즉시 키 발급 / team-b(승인 필요)는 관리자 승인 후 발급
4. Profile 페이지에서 Primary/Secondary Key 확인

## 5. 구독 승인 (관리자)
Azure Portal → APIM → **Subscriptions** → 대기 중 요청 승인/거부

> ⚠️ 개발자 포털 최초 게시 전에는 익명 사용자가 API 를 볼 수 없습니다.
```

- [ ] **Step 8: 링크·존재 검증**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
test -f labs/lab09-products-portal/README.md && test -f docs/developer-portal-guide.md && echo "both exist"
grep -n 'lab10-governance-observability' labs/lab09-products-portal/README.md
grep -c '```mermaid' labs/lab09-products-portal/README.md
```
Expected: "both exist", 다음 단계 링크 1건, mermaid ≥1.

- [ ] **Step 9: 커밋**

```bash
git add labs/lab09-products-portal/README.md docs/developer-portal-guide.md
git commit -m "docs(lab09): add products & developer portal draft lab + portal guide

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063"
```

---

### Task 4: Lab 10 — 구독별 거버넌스 & Azure Monitor 관측 README

**Files:**
- Create: `labs/lab10-governance-observability/README.md`

**Interfaces:**
- Consumes: T1 `llm-emit-token-metrics.xml`(Provider 차원); T2 통합 API; T3 Product/구독; Lab 6 App Insights/KQL 기반.
- Produces: 없음(캡스톤). Event Hub 로깅·스트리밍 usage·Workbook·구독별 alert 를 제공.

- [ ] **Step 1: README 스켈레톤 + 목표**

`labs/lab10-governance-observability/README.md`:
```markdown
# Lab 10: 구독별 거버넌스 & Azure Monitor 대시보드

> 🚧 **드래프트** — 스니펫은 정확하나, 실제 배포 후 E2E 검증 예정입니다.

모든 **프로바이더 × 구독**에 걸친 토큰·비용·프롬프트를 하나의 관측 평면에서 통제합니다. Lab 6의 App Insights 관측을 멀티 클라우드·멀티 구독으로 확장하고, 스트리밍/대용량 프롬프트까지 풀 피델리티로 캡처합니다.

## 목표
- Provider × Model × Subscription × Product 차원 토큰 메트릭
- 구독별 TPM + 월 quota 거버넌스 (Lab 9 확장)
- Event Hub 로깅으로 8KB 초과·스트리밍 프롬프트/응답 무손실 캡처
- Azure Monitor Workbook + 구독별 Alert

## 관측 범위 (Lab 6 대비 확장)
## 아키텍처
## 실습 단계
## 핵심 개념
## 다음 단계
```

- [ ] **Step 2: Lab 6 대비 확장 표**

```markdown
## 관측 범위 (Lab 6 대비 확장)

| 항목 | Lab 6 | Lab 10 (이번) |
|---|---|---|
| 토큰 메트릭 대상 | Azure OpenAI | **모든 프로바이더** (Provider 차원) |
| 구독 구분 | Subscription ID | Subscription **+ Product** |
| 프롬프트/응답 로깅 | Diagnostics body (≤8KB, 스트리밍 미포착) | **Event Hub** 무손실 + 스트리밍 usage |
| 대시보드 | KQL 쿼리 | **Azure Monitor Workbook** + Dashboard 고정 |
| 알림 | 서비스 단위 | **구독별** 토큰 급증/quota 초과 |
```

- [ ] **Step 3: 아키텍처 mermaid**

```markdown
​```mermaid
graph LR
    API["Lab 8 통합 API"] -->|llm-emit-token-metric| AI["App Insights<br/>customMetrics"]
    API -->|log-to-eventhub| EH["Event Hub<br/>무손실 프롬프트/응답"]
    AI --> WB["Azure Monitor Workbook<br/>Provider×Subscription"]
    EH --> LA["Log Analytics / 저장소"]
    WB --> ALERT["구독별 Alert"]
​```
```

- [ ] **Step 4: 실습 단계 — 메트릭 차원 확장 (이미 T1에 Provider 포함) 설명 + KQL**

```markdown
## 실습 단계

### 1단계: 프로바이더별·구독별 토큰 (KQL)

​```kql
customMetrics
| where name in ("Total Tokens", "Prompt Tokens", "Completion Tokens")
| where timestamp > ago(24h)
| extend provider = tostring(customDimensions["Provider"])
| extend subscriptionId = tostring(customDimensions["Subscription ID"])
| extend model = tostring(customDimensions["Model"])
| summarize totalTokens = sum(value) by provider, subscriptionId, model
| order by totalTokens desc
​```

### 2단계: 크로스클라우드 구독별 비용 추정

​```kql
customMetrics
| where name == "Total Tokens"
| where timestamp > ago(1d)
| extend provider = tostring(customDimensions["Provider"])
| extend subscriptionId = tostring(customDimensions["Subscription ID"])
| summarize tokens = sum(value) by provider, subscriptionId
| extend estCostUsd = case(
    provider == "anthropic", tokens * 0.000003,
    provider == "gemini", tokens * 0.0000005,
    provider == "openai", tokens * 0.000005,
    tokens * 0.000002)   // azure 기본
| order by estCostUsd desc
​```
```

- [ ] **Step 5: 실습 단계 — Event Hub 로깅 (Bicep + logger + log-to-eventhub 정책)**

```markdown
### 3단계: Event Hub 무손실 로깅 (8KB 한계·스트리밍 보완)

Lab 6 Diagnostics body 로깅은 **8192바이트에서 잘리고 스트리밍(SSE) 응답을 포착하지 못합니다.**
전체 프롬프트/응답을 남기려면 Event Hub 경로를 사용합니다.

​```bicep
// infra/modules/eventhub-logging.bicep (초안)
resource ehNamespace 'Microsoft.EventHub/namespaces@2022-10-01-preview' = {
  name: 'ehns-ai-gateway-${suffix}'
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
}
resource eh 'Microsoft.EventHub/namespaces/eventhubs@2022-10-01-preview' = {
  parent: ehNamespace
  name: 'ai-gateway-logs'
  properties: { messageRetentionInDays: 1, partitionCount: 2 }
}
​```

APIM Event Hub logger 등록 후, 정책에 추가:

​```xml
<!-- Inbound: 전체 프롬프트 캡처 -->
<log-to-eventhub logger-id="eventhub-logger">@{
    return new JObject(
        new JProperty("subscriptionId", context.Subscription.Id),
        new JProperty("provider", (string)context.Variables.GetValueOrDefault("provider", "unknown")),
        new JProperty("requestBody", context.Request.Body.As<string>(preserveContent: true))
    ).ToString();
}</log-to-eventhub>
​```

> Event Hub 는 크기 제한이 훨씬 커서 8KB 초과 프롬프트도 무손실로 남습니다.
> 스트리밍 응답의 토큰은 4단계(`include_usage`)로 확보합니다.
```

- [ ] **Step 6: 실습 단계 — 스트리밍 usage + 레닥션/보존 주의**

```markdown
### 4단계: 스트리밍(SSE) 응답의 토큰 확보

스트리밍(`stream: true`)에서는 APIM 이 응답 본문을 버퍼링하지 못해 토큰이 누락됩니다.
클라이언트가 `stream_options.include_usage: true` 를 보내면, 스트림 마지막 청크에 `usage` 가 포함됩니다.

​```json
{ "model": "openai/gpt-4o", "stream": true,
  "stream_options": { "include_usage": true },
  "messages": [{ "role": "user", "content": "..." }] }
​```

> ⚠️ **레닥션/보존:** 프롬프트/응답에는 PII 가 포함될 수 있습니다. Event Hub 소비자 단에서
> 마스킹하고, Log Analytics 보존 기간과 접근 권한(RBAC)을 정책으로 통제하세요.
> 민감 라우트에만 body 로깅을 활성화하는 것을 권장합니다.
```

- [ ] **Step 7: 실습 단계 — Workbook + 구독별 Alert + 다음 단계**

```markdown
### 5단계: Azure Monitor Workbook

Portal → Azure Monitor → **Workbooks** → **+ New** → 아래 쿼리들을 타일로 추가:
- 프로바이더별 TPM (timechart)
- 구독별 토큰 Top 10 (barchart)
- 구독별 429율 (timechart)
- 크로스클라우드 비용 추정 (table)

> Workbook 은 JSON 으로 export/공유 가능합니다. (Advanced Editor → Gallery Template)

### 6단계: 구독별 Alert

​```bash
az monitor metrics alert create --name alert-sub-token-spike \
  --resource-group $RESOURCE_GROUP \
  --scopes $(az apim show -g $RESOURCE_GROUP -n $APIM_NAME --query id -o tsv) \
  --condition "total 'Total Tokens' > 500000" \
  --window-size 15m --evaluation-frequency 5m \
  --description "구독 토큰 급증 감지"
​```

## 핵심 개념
- 하나의 게이트웨이가 모든 프로토콜을 제어(제한/quota)하고 관측(토큰/프롬프트/비용)한다
- Provider 차원으로 멀티 클라우드를, Subscription/Product 차원으로 멀티 테넌트를 분해한다
- 8KB·스트리밍 한계는 Event Hub + include_usage 로 보완한다

## 다음 단계
→ [Lab 11: 리소스 정리](../lab11-cleanup/README.md) | [메인 README](../../README.md)
```

- [ ] **Step 8: 검증 (KQL/링크/mermaid)**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
test -f labs/lab10-governance-observability/README.md && echo exists
grep -c '```kql' labs/lab10-governance-observability/README.md
grep -n 'lab11-cleanup' labs/lab10-governance-observability/README.md
```
Expected: "exists", kql 블록 ≥2, lab11-cleanup 링크 1건.

- [ ] **Step 9: 커밋**

```bash
git add labs/lab10-governance-observability/README.md
git commit -m "docs(lab10): add governance & Azure Monitor observability capstone draft lab

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063"
```

---

### Task 5: Lab 6 로깅 한계 패치 (소규모·정직한 보완)

**Files:**
- Modify: `labs/lab06-monitoring/README.md`

**Interfaces:**
- Consumes: 없음.
- Produces: Lab 10으로의 전방 참조. Lab 10이 이 한계의 해결책을 제공.

- [ ] **Step 1: `bytes: 4096` → `8192` 로 상향 (2곳: frontend/backend response 및 request)**

`labs/lab06-monitoring/README.md`의 3-1단계 Bicep 블록에서 `body: { bytes: 4096 }` 을 모두 `body: { bytes: 8192 }` 로 변경한다(요청/응답 총 4곳).

Run(사전 확인):
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
grep -n 'bytes: 4096' labs/lab06-monitoring/README.md
```
Expected: 4건 매치. 각각을 `bytes: 8192` 로 치환.

- [ ] **Step 2: "3-2단계: 프롬프트/응답 로깅의 한계와 보완" 섹션 삽입**

3-1단계 블록 바로 뒤에 삽입:
```markdown
### 3-2단계: ⚠️ 프롬프트/응답 로깅의 한계와 보완

APIM Diagnostics body 로깅은 AI 관측의 **시작점**이지만, 프로덕션 프롬프트/응답 관측에는 세 가지 한계가 있습니다.

| 한계 | 내용 | 영향 |
|---|---|---|
| **8KB 하드 한계** | body 로깅은 최대 **8192바이트**까지만 저장(구성 불가). 위 설정도 8192가 상한 | 긴 시스템 프롬프트·RAG 컨텍스트·장문 응답이 **잘림** |
| **스트리밍(SSE) 미포착** | `stream: true` 응답은 APIM 이 버퍼링하지 못해 body·종료 `usage`(토큰)가 **로깅되지 않음** | ChatGPT식 스트리밍(Lab 7) 관측 공백 |
| **PII/보존** | 프롬프트/응답에 민감정보 포함 가능 | 마스킹·보존기간·접근통제 필요 |

> 💡 위 3-1단계에서 `bytes` 를 상한인 **8192** 로 올렸지만, 8KB 초과분은 여전히 잘립니다.
> **무손실 캡처(Event Hub) + 스트리밍 토큰(`include_usage`) + 레닥션**은
> **[Lab 10: 구독별 거버넌스 & 관측](../lab10-governance-observability/README.md)** 에서 다룹니다.
```

- [ ] **Step 3: 검증**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
grep -c 'bytes: 4096' labs/lab06-monitoring/README.md   # expect 0
grep -c 'bytes: 8192' labs/lab06-monitoring/README.md   # expect >=4
grep -n 'lab10-governance-observability' labs/lab06-monitoring/README.md  # expect 1
```
Expected: 4096 = 0건, 8192 ≥ 4건, Lab 10 링크 1건.

- [ ] **Step 4: 커밋**

```bash
git add labs/lab06-monitoring/README.md
git commit -m "docs(lab06): add prompt/response logging limits section + raise body cap to 8192

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063"
```

---

### Task 6: Cleanup 랩 재번호(lab08→lab11) + 상호 링크/루트 README 갱신

**Files:**
- Rename: `labs/lab08-cleanup/` → `labs/lab11-cleanup/` (git mv)
- Modify: `labs/lab07-advanced-patterns/README.md` (다음 단계 링크)
- Modify: `labs/lab11-cleanup/README.md` (자체 제목/번호 표기)
- Modify: `README.md` (루트: 진행 표, 폴더 트리, cleanup 링크들)
- Modify: `.env.sample` (Lab 8 프로바이더 키 자리표시자)

**Interfaces:**
- Consumes: T2/T3/T4가 만든 lab08/09/10 폴더(링크 대상).
- Produces: 없음(마무리).

- [ ] **Step 1: cleanup 폴더 git mv**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
git mv labs/lab08-cleanup labs/lab11-cleanup
ls labs
```
Expected: `lab11-cleanup` 존재, `lab08-cleanup` 없음.

- [ ] **Step 2: lab11-cleanup/README.md 내부 번호 표기 갱신**

Run(확인):
```bash
grep -n 'Lab 8\|lab08' labs/lab11-cleanup/README.md
```
매치되는 "Lab 8"(제목/본문의 자기 지칭)을 "Lab 11"로, 경로 `lab08` 을 `lab11` 로 치환한다. (자기 자신을 가리키는 표기만; 다른 랩 참조는 그대로.)

- [ ] **Step 3: lab07 다음 단계 링크 수정**

`labs/lab07-advanced-patterns/README.md:190`의
`→ [Lab 8: 리소스 정리](../lab08-cleanup/README.md) | ...` 를
`→ [Lab 8: 멀티 클라우드 통합 게이트웨이](../lab08-multicloud-gateway/README.md) | [메인 README로 돌아가기](../../README.md)` 로 변경.

- [ ] **Step 4: 루트 README 진행 상태 표 갱신**

`README.md`의 Lab 진행 상태 표(라인 7–16 부근)에서 Lab 8 행을 교체하고 신규 행 추가:
```markdown
| Lab 8 | 멀티 클라우드 통합 게이트웨이 (OpenAI, Anthropic, Gemini) | 🚧 드래프트 |
| Lab 9 | Products & 개발자 포털 (구독 격리) | 🚧 드래프트 |
| Lab 10 | 구독별 거버넌스 & Azure Monitor 대시보드 | 🚧 드래프트 |
| Lab 11 | 리소스 정리 | ✅ 완료 |
```

- [ ] **Step 5: 루트 README cleanup 링크·폴더 트리 치환**

Run(확인):
```bash
grep -n 'lab08-cleanup\|Lab 8: 리소스\|lab08-cleanup/                  # Lab 8' README.md
```
- `labs/lab08-cleanup/README.md` → `labs/lab11-cleanup/README.md` (링크 2곳: 라인 172, 561 부근)
- 폴더 트리(라인 231 부근) `└── lab08-cleanup/ # Lab 8: 리소스 정리` → 신규 4개 폴더 반영:
```
│   ├── lab08-multicloud-gateway/       # Lab 8: 멀티 클라우드 통합 게이트웨이
│   ├── lab09-products-portal/          # Lab 9: Products & 개발자 포털
│   ├── lab10-governance-observability/ # Lab 10: 거버넌스 & 관측
│   └── lab11-cleanup/                  # Lab 11: 리소스 정리
```
- "### Lab 8: 리소스 정리" 섹션 헤딩(라인 493 부근)과 `📁 labs/lab08-cleanup/`(라인 495/561 부근)을 Lab 11 로 갱신.

- [ ] **Step 6: 루트 README 비즈니스 시나리오에 신규 랩 추가**

기존 "### Lab 7" 시나리오 블록 뒤에 삽입:
```markdown
### Lab 8: 멀티 클라우드 통합 게이트웨이

| # | 비즈니스 요구사항 |
|---|-----------------|
| 1 | Azure뿐 아니라 **OpenAI·Anthropic·Google Gemini**를 하나의 엔드포인트로 호출하고 싶다 |
| 2 | 클라이언트 코드는 그대로 두고 `model` 값만 바꿔 **프로바이더를 전환**하고 싶다 |
| 3 | 프로바이더가 달라도 **토큰 제어·메트릭을 동일한 정책**으로 적용하고 싶다 |

### Lab 9: Products & 개발자 포털

| # | 비즈니스 요구사항 |
|---|-----------------|
| 1 | 팀마다 **격리된 구독 키**를 발급해 API 접근과 토큰 예산을 분리하고 싶다 |
| 2 | 개발자가 **셀프서비스로 구독**을 신청·발급받게 하고 싶다 |

### Lab 10: 구독별 거버넌스 & 관측

| # | 비즈니스 요구사항 |
|---|-----------------|
| 1 | **프로바이더별·구독별** 토큰/비용을 한 대시보드에서 보고 싶다 |
| 2 | 8KB를 넘는 긴 프롬프트나 **스트리밍 응답까지 무손실로 로깅**하고 싶다 |
| 3 | 구독이 토큰을 급증시키면 **구독 단위로 알림**을 받고 싶다 |
```

- [ ] **Step 7: `.env.sample` 에 Lab 8 프로바이더 키 자리표시자 추가**

Lab 5 Gemini 블록 뒤(파일 끝 부근)에 삽입:
```bash

# ═══════════════════════════════════════════════════════
# Lab 8: 멀티 클라우드 프로바이더 (선택사항)
# ═══════════════════════════════════════════════════════

# OpenAI 직접 — https://platform.openai.com/api-keys
OPENAI_API_KEY="<your-openai-api-key>"


# Anthropic 직접 — https://console.anthropic.com/settings/keys
ANTHROPIC_API_KEY="<your-anthropic-api-key>"
```

- [ ] **Step 8: 전체 상호 링크 검증(끊긴 링크 0)**

Run:
```bash
cd /Users/changjuahn/Repo/copilot-worktrees/Azure-AI-Gateway-KR/changju-ahn-ideal-fishstick
# 잔존 참조 없어야 함
grep -rn 'lab08-cleanup' README.md labs/ docs/ && echo "STALE FOUND" || echo "no stale lab08-cleanup refs"
# README 상대 링크가 실제 파일로 연결되는지 확인
python3 - <<'PY'
import re, os
root="."
bad=[]
for dp,_,fs in os.walk("labs"):
    for f in fs:
        if not f.endswith(".md"): continue
        p=os.path.join(dp,f)
        for m in re.finditer(r'\]\((\.\./[^)]+\.md)\)', open(p,encoding="utf-8").read()):
            tgt=os.path.normpath(os.path.join(dp,m.group(1)))
            if not os.path.exists(tgt): bad.append((p,m.group(1)))
print("BROKEN:",bad if bad else "none")
PY
```
Expected: "no stale lab08-cleanup refs" 그리고 "BROKEN: none".

- [ ] **Step 9: 커밋**

```bash
git add -A
git commit -m "docs: renumber cleanup to lab11, wire up lab08-10 links, root README & .env.sample

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>
Copilot-Session: 7e69b8e0-415b-4e97-b588-95639731f063"
```

---

## Self-Review (완료)

**Spec coverage:** §5 llm-* 평면 → T1. §6 Lab 8 → T2. §7 Lab 9 → T3. §8 Lab 10 → T4. §9 Lab 6 패치 → T5. §4 번호/폴더 + §10 .env → T6. 모든 스펙 섹션이 태스크에 매핑됨.

**Placeholder scan:** 모든 코드/스니펫 단계에 실제 XML/CLI/Bicep/KQL/Python 포함. "🚧 드래프트" 배지는 산출물의 명시적 상태 표기이며 플랜의 미완성 표시가 아님.

**Type consistency:** `provider`/`modelName` 변수는 T1 model-routing 에서 정의되고 T1 emit-metrics·T4 event-hub 에서 동일 이름으로 소비. backend-id(`openai-direct-backend`/`anthropic-backend`/`openai-backend-pool`/`gemini-backend-pool`)는 T1 정의 ↔ T2 백엔드 등록 일치. Named Value 키(`openai-api-key`/`anthropic-api-key`)는 T1 정책 ↔ T2 등록 ↔ T6 .env 일치.
