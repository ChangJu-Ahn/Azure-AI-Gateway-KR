# Lab 1: Azure API Management 기본 설정

이 실습에서는 Azure API Management 인스턴스를 생성하고 기본 구조를 이해합니다.

## 목표

- APIM 인스턴스 생성 (Consumption 티어 - 최저 비용)
- APIM 포털 구조 이해 (API, Product, Subscription)
- Gateway URL 확인 및 기본 Health Check

## 사전 준비

```bash
az login
az account set --subscription "<구독 ID>"
```

## 실습 단계

### 1단계: 전체 인프라 배포

```bash
# 프로젝트 루트에서 실행
./scripts/deploy.sh
```

> 💡 `deploy.sh`가 다음을 자동으로 수행합니다:
> 1. 리소스 그룹 `rg-ai-gw-{suffix}` 생성
> 2. Bicep으로 APIM + Azure OpenAI × 3 + 백엔드 풀 + 모니터링 배포
> 3. `.env` 자동 생성 (APIM URL 포함)
>
> **모델 배포 용량(TPM):** 기본 **5K TPM**(5,000 토큰/분)으로 배포됩니다.
> 이는 Lab 3의 429/Circuit Breaker 테스트를 쉽게 하기 위한 설정입니다.
> 프로덕션에서는 `infra/modules/openai.bicep`의 `modelCapacity`를 높이세요 (예: 30 = 30K TPM).
>
> 리소스 이름은 `infra/parameters/dev.bicepparam`의 `suffix` 값으로 결정됩니다.
> 재배포 시 이름 충돌을 피하려면 suffix를 변경하세요: `./scripts/deploy.sh dev newSuffix`

### 2단계: 배포 확인

```bash
# 배포된 리소스 목록 확인
set -a; source .env; set +a
az resource list --resource-group $RESOURCE_GROUP --output table

# APIM Gateway URL 확인
echo $APIM_URL
```

### 3단계: Python 환경 설정

노트북 테스트를 위한 Python 가상환경을 설정합니다:

```bash
# 프로젝트 루트에서 실행
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

> 💡 VS Code에서 노트북을 열 때 커널을 `.venv`로 선택하세요:
> 노트북 우상단 **Select Kernel** → **Python Environments** → `.venv`

### 4단계: .env Subscription Key 설정

`deploy.sh`가 생성한 `.env`에 APIM Subscription Key를 입력합니다:

1. Azure Portal → APIM → APIs → **Subscriptions**
2. **Built-in all-access subscription** → **Show/hide keys** 클릭
3. Primary key 복사
4. `.env`에서 `APIM_SUBSCRIPTION_KEY` 값 입력

### 5단계: Azure Portal에서 확인

1. [Azure Portal](https://portal.azure.com) → API Management 서비스
2. 다음 항목 탐색:
   - **APIs**: 등록된 API 목록
   - **Products**: API를 묶는 논리적 단위
   - **Subscriptions**: API 접근 키 관리
   - **Policies**: 요청/응답 처리 파이프라인
   ![alt text](image.png)

## 핵심 개념

### APIM SKU 비교

| 항목 | Consumption | Developer | Standard v2 |
|------|------------|-----------|-------------|
| 비용 | 호출당 과금 | 월 ~$50 | 월 ~$300+ |
| SLA | 없음 | 없음 | 99.95% |
| VNet | 불가 | 가능 | 가능 |
| 용도 | 테스트/저사용량 | 개발/테스트 | 프로덕션 |

### APIM 핵심 구성 요소

```
Client → Gateway → API → Operation → Backend
              │
              └── Policy Pipeline
                  ├── Inbound (요청 전처리)
                  ├── Backend (백엔드 호출)
                  ├── Outbound (응답 후처리)
                  └── On-Error (에러 처리)
```

## 다음 단계

→ [Lab 2: Azure OpenAI 백엔드 연결](../lab02-azure-openai-backend/README.md)
