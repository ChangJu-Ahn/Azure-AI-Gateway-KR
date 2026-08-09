# 공식 문서 대비 검토 리포트 (Microsoft Learn 기준)

이 리포트는 레포지토리의 기술 문서/정책 내용을 **Microsoft 공식 문서(learn.microsoft.com)**와 대조하여
**변경이 필요한 내용이 있는지**를 검토한 결과입니다.

- 검토 방식: 서로 독립적인 **2회 검토**(1차 정책 레퍼런스 교차검증, 2차 핵심·불확실 항목 재검증)를 수행했습니다.
- 원칙: **공식 문서에서 확인되지 않은 내용은 이 리포트에 사실로 포함하지 않았습니다.** 공식 문서로 단정할 수 없는 항목은 "확인 권장"으로만 표기했습니다.
- 검토 일자: 2026-08-09

---

## 요약

- 검토한 기술적 주장(정책 속성, 섹션, 상태 코드, 역할명 등)의 **대부분이 공식 문서와 일치**합니다.
- **변경/정합성 정리가 필요한 항목: 1건** (토큰 메트릭 정책 배치 위치의 내부 불일치)
- **공식 문서로 단정 불가 → 확인 권장 항목: 1건** (AI Foundry용 Managed Identity `resource` 값)

---

## 1. 변경(정합성 정리)이 필요한 항목

### 1-1. `azure-openai-emit-token-metric` 배치 섹션의 내부 불일치

**현상 — 레포 내부가 서로 다른 배치를 안내합니다.**

- `policies/ai-gateway-policy.xml`, `policies/fragments/emit-token-metrics.xml`:
  `<inbound>`에 배치하고 주석으로 **"inbound에 배치 — 공식 문서 기준"** 이라고 명시.
- `docs/policy-reference.md` §11:
  `<outbound>`에 배치하고 **"왜 Outbound인가?"** 로 설명.

**공식 문서 확인 내용**

- `azure-openai-emit-token-metric` 정책은 **inbound, backend, outbound** 섹션에서 사용할 수 있습니다.
  (`on-error`는 지원 목록에 없음)
- 즉, inbound와 outbound **둘 다 공식적으로 허용**됩니다.
- 참고: `https://learn.microsoft.com/en-us/azure/api-management/azure-openai-emit-token-metric-policy`

**판단 및 권장**

- 두 배치 모두 공식 문서상 허용되므로 "오류"는 아니지만, **레포 내부 안내가 상호 모순**입니다.
- 특히 XML 주석의 **"공식 문서 기준"이라는 표현은 마치 공식 문서가 inbound를 강제하는 것처럼 오해**를 줄 수 있습니다. 공식 문서는 inbound/backend/outbound를 모두 허용합니다.
- **권장:** 배치 위치를 한쪽으로 통일하고, "공식 문서 기준" 문구를 "공식 문서상 inbound·backend·outbound 모두 허용" 과 같이 정확히 수정.

---

## 2. 공식 문서로 단정 불가 → 확인 권장 항목

### 2-1. AI Foundry용 `authentication-managed-identity` 의 `resource` 값

- 위치: `docs/policy-reference.md` — `> AI Foundry 사용 시: resource="https://ml.azure.com"`
- 검토 결과: Azure OpenAI용 값인 `resource="https://cognitiveservices.azure.com"` 는 공식 문서로 **확인됨(정확)**.
  그러나 **AI Foundry / Azure Machine Learning용 `https://ml.azure.com`** 값은 공식 정책 레퍼런스 페이지에서 **명확히 단정할 수 있는 근거를 확보하지 못했습니다.**
- **원칙에 따라 "오류"로 단정하지 않습니다.** 다만 실제 적용 전, 공식 `authentication-managed-identity` 문서와 대상 서비스의 Application ID URI(및 후행 슬래시 `/` 유무)를 **직접 확인할 것을 권장**합니다.
- 참고: `https://learn.microsoft.com/en-us/azure/api-management/authentication-managed-identity-policy`

---

## 3. 공식 문서와 일치하여 변경 불필요한 항목 (검증 완료)

| 항목 | 검증 결과 | 공식 문서 |
|------|-----------|-----------|
| `authentication-managed-identity` — Azure OpenAI `resource="https://cognitiveservices.azure.com"` | ✅ 일치 | `.../api-management/authentication-managed-identity-policy` |
| RBAC 역할 — Azure OpenAI: **Cognitive Services OpenAI User** / Content Safety: **Cognitive Services User** | ✅ 일치 | `.../ai-services/openai/how-to/role-based-access-control` |
| `azure-openai-token-limit` — 속성(`counter-key`, `tokens-per-minute`, `estimate-prompt-tokens`, `remaining-tokens-*`, `tokens-consumed-*`), 초과 시 **429**, **inbound** | ✅ 일치 | `.../api-management/azure-openai-token-limit-policy` |
| `llm-token-limit` — `token-quota`, `token-quota-period`(Hourly/Daily/Weekly/Monthly/Yearly), 누적 초과 **403** / TPM 초과 **429** | ✅ 일치 | `.../api-management/llm-token-limit-policy` |
| `llm-content-safety` — `backend-id`, `shield-prompt`, `output-type`(EightSeverityLevels·FourSeverityLevels), `<blocklists>`, 차단 시 **403** | ✅ 일치 | `.../api-management/llm-content-safety-policy` |
| 시맨틱 캐시 — `azure-openai-semantic-cache-lookup`(inbound), `-store`(outbound), `score-threshold`·`embeddings-backend-id`·`embeddings-backend-auth`·`duration` | ✅ 일치 | `.../api-management/azure-openai-semantic-cache-lookup-policy` |
| Backend Circuit Breaker — `failureCondition`(`count`, `interval`, `statusCodeRanges`, `errorReasons`), `tripDuration`, `acceptRetryAfter` | ✅ 일치 | `.../templates/microsoft.apimanagement/service/backends` |
| `quota-by-key` — **호출 수/대역폭** 집계(토큰 아님), `calls`·`renewal-period`·`counter-key` | ✅ 일치 | `.../api-management/quota-by-key-policy` |
| `retry` — `condition`, `count`, `interval`, `max-interval`, `delta`, `first-fast-retry` | ✅ 일치 | `.../api-management/retry-policy` |
| `azure-openai-emit-token-metric` / `llm-emit-token-metric` — 커스텀 dimension **정책당 최대 5개** | ✅ 일치 | `.../api-management/azure-openai-emit-token-metric-policy` |

---

## 4. 검토 범위 및 한계

- 본 검토는 **공식 문서로 검증 가능한 기술적 사실**(정책 속성/섹션/상태 코드/역할명/한도)에 한정했습니다.
- 샌드박스에서 `learn.microsoft.com` 직접 접속이 차단되어, 공식 문서 내용은 웹 검색을 통해 확인했습니다. URL은 공식 표준 경로를 표기했습니다.
- 실제 반영 전, 위 "확인 권장" 항목과 각 공식 문서의 최신본을 한 번 더 대조하시기 바랍니다.
