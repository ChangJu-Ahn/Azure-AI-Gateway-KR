# Lab 13 실행

기존 APIM Developer v1은 유지하고, 나머지 실험 리소스만 신규 Resource Group에 배포합니다.

## 사전 조건

- Azure CLI, `jq`, `curl`, `ssh`, `scp`
- 기존 APIM이 Japan East의 Developer SKU
- APIM과 신규 리소스에 대한 배포/RBAC 권한

## 배포

```bash
export LOGBENCH_APIM_NAME="<existing-apim-name>"
export LOGBENCH_APIM_RG="<existing-apim-resource-group>"
./scripts/logbench-v4/deploy.sh
```

배포 스크립트는 현재 공인 IP만 VM SSH에 허용하고, APIM에 `logbench-v4` API와 두 logger를 유지 가능한 형태로 생성합니다.

## 실행

```bash
./scripts/logbench-v4/run-experiment.sh
```

N8/A8/E8/N64/E64 총 15런을 수행하며 결과는 `results/<run-id>/`에 저장합니다. 이미 `result.json`이 있는 런은 건너뜁니다.

## 조건 하나만 확인

```bash
./scripts/logbench-v4/configure-condition.sh E8
```

## 삭제

```bash
./scripts/logbench-v4/teardown.sh
```

teardown은 `managed-by=lab13-v4` 태그를 확인한 뒤 신규 Resource Group만 삭제합니다. **기존 APIM, `logbench-v4` API, logger와 APIM managed identity는 삭제하지 않습니다.**

## 비용 주의

Event Hubs Standard 40 TU와 Standard_D8as_v5 VM은 배포된 시간 동안 과금됩니다. 실험 직후 teardown을 실행하세요.
