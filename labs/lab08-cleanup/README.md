# Lab 8: 리소스 정리 (Clean Up)

모든 실습이 끝난 후 Azure 리소스를 정리하여 불필요한 과금을 방지합니다.

## 목표

- 배포된 Azure 리소스 확인
- 리소스 그룹 전체 삭제
- 삭제 완료 확인

## 왜 정리가 필요한가?

이 워크숍에서 배포한 리소스는 **사용하지 않아도 과금**될 수 있습니다:

| 리소스 | 과금 방식 |
|--------|-----------|
| API Management (Developer) | 시간당 과금 (월 ~$50) |
| Azure OpenAI | 프로비저닝 시 토큰 기반 과금 |
| Application Insights | 데이터 수집량 기반 |
| Log Analytics | 데이터 보존량 기반 |

## 실습 절차

### Step 1: 현재 리소스 확인

리소스 그룹에 어떤 리소스가 배포되어 있는지 확인합니다.

```bash
# 환경 변수 로드
set -a; source .env; set +a

# 리소스 그룹 상태 확인
az group show --name $RESOURCE_GROUP --query '{name:name, state:properties.provisioningState, location:location}' -o table

# 리소스 목록 확인
az resource list --resource-group $RESOURCE_GROUP --output table
```

### Step 2: 리소스 삭제

cleanup 스크립트를 실행하여 리소스 그룹 전체를 삭제합니다.

```bash
./scripts/cleanup.sh
```

스크립트가 수행하는 작업:
1. 리소스 그룹 존재 여부 확인
2. 삭제될 리소스 목록 출력
3. 삭제 확인 프롬프트 (y/N)
4. `az group delete` 실행 (백그라운드)

### Step 3: 삭제 완료 확인

리소스 그룹 삭제는 수 분이 소요됩니다. 아래 명령으로 확인합니다.

```bash
# 삭제 진행 중이면 "Deleting", 완료되면 에러 (그룹이 없으므로)
set -a; source .env; set +a
az group show --name $RESOURCE_GROUP --query 'properties.provisioningState' 2>/dev/null || echo "✅ 삭제 완료"
```

## 수동 삭제 (스크립트 없이)

```bash
# 리소스 그룹 전체 삭제
set -a; source .env; set +a
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## Soft Delete 리소스 정리

Azure OpenAI와 API Management는 삭제 후에도 **soft delete** 상태로 남을 수 있습니다.
완전히 제거하려면 다음을 실행합니다.

```bash
# Cognitive Services (OpenAI) soft delete 목록 확인
az cognitiveservices account list-deleted -o table

# soft delete된 리소스 영구 삭제 (purge)
az cognitiveservices account purge \
    --name <리소스_이름> \
    --resource-group $RESOURCE_GROUP \
    --location koreacentral

# APIM soft delete 목록 확인
az apim deletedservice list -o table

# APIM soft delete 영구 삭제
az apim deletedservice purge \
    --service-name <APIM_이름> \
    --location koreacentral
```

> **참고**: soft delete 리소스가 남아 있으면 같은 이름으로 재배포 시 충돌이 발생할 수 있습니다.

## 확인 체크리스트

- [ ] `az group show --name $RESOURCE_GROUP` 실행 시 "ResourceGroupNotFound" 반환
- [ ] Azure Portal에서 리소스 그룹이 보이지 않음
- [ ] (선택) soft delete 리소스 purge 완료

---

→ [메인 README로 돌아가기](../../README.md)
