# Lab 13 인프라·실행기 설계

## 목표

기존 APIM Developer v1 인스턴스를 유지하면서 500 offered RPS에서 App Insights 8KB와 Event Hub 8/64KB 로깅을 비교할 수 있는 배포·실행 도구를 만든다.

산출물은 두 묶음이다.

1. 신규 실험 리소스를 배포하는 Bicep과 로컬 제어 shell
2. 부하 VM에서 실행하는 k6·Python 패키지

## 리소스 경계

### 신규 전용 Resource Group

다음 리소스는 모두 하나의 신규 RG에 생성한다.

- Event Hubs Standard namespace, event hub, consumer group
- Log Analytics workspace, Application Insights
- Standard_D8as_v5 Linux VM
- VNet, subnet, NSG, public IP, NIC
- VM managed identity와 신규 리소스 범위 RBAC

모든 신규 리소스에는 `managed-by=lab13-v4` 태그를 적용한다.

### 기존 APIM

기존 APIM은 삭제하거나 재배포하지 않는다. 다음 객체만 영구적으로 추가하고 다음 실험에서도 재사용한다.

- API `logbench-v4`
- operation `POST /echo`
- App Insights logger `logbench-v4-ai`
- Event Hub logger `logbench-v4-eh`
- API scope diagnostic
- API scope policy
- API-scoped subscription
- system-assigned managed identity

동일 이름 객체가 이미 존재하지만 `managed-by=lab13-v4` 표식과 일치하지 않으면 덮어쓰지 않고 중단한다. 전역 정책과 기존 API·logger·diagnostic은 변경하지 않는다.

### Teardown

teardown은 `managed-by=lab13-v4` 태그와 예상 RG 이름을 확인한 후 신규 RG만 삭제한다.

다음 항목은 삭제하지 않는다.

- 기존 APIM
- `logbench-v4` API와 operation
- 두 logger와 API diagnostic/policy
- API subscription
- APIM system-assigned MI

APIM 삭제와 soft-delete purge 명령은 구현하지 않는다.

## 구현 구조

```text
infra/
  logbench-v4.bicep
scripts/
  logbench-v4/
    deploy.sh
    configure-condition.sh
    run-experiment.sh
    download-results.sh
    teardown.sh
labs/lab13-logging-perf-benchmark/
  runner/
    bootstrap.sh
    load.js
    collector.py
    consume.py
    reconcile.py
    run.sh
    tests/
```

## IaC와 배포

### Bicep

Bicep은 신규 RG 내부 리소스만 생성한다. 기존 APIM principal ID를 parameter로 받아 신규 EH namespace 범위에 Event Hubs Data Sender 역할을 부여한다. VM MI에는 Event Hubs Data Receiver 역할을 부여한다.

Event Hubs는 다음으로 고정한다.

- Standard
- 40 TU
- auto-inflate OFF
- 32 partitions
- 실험 전용 consumer group

40 TU를 전체 실험 동안 유지해 E8과 E64 사이의 용량 변경을 제거한다.

### deploy.sh

배포 순서는 다음과 같다.

1. Azure 로그인·구독·기존 APIM·리전·SKU 확인
2. 현재 공인 IP 조회 후 `/32` SSH NSG parameter 생성
3. 공인 IP 조회 실패 시 `LOGBENCH_SSH_CIDR` 명시 입력 요구
4. 기존 APIM 객체와 MI 상태 조회
5. MI가 없으면 활성화하고 이후에도 유지
6. 신규 RG와 Bicep 배포
7. APIM MI의 EH Sender RBAC 전파 확인
8. APIM 전용 API·operation·subscription·logger·diagnostic 생성 또는 갱신
9. VM package SCP 전송과 bootstrap
10. `.env.logbench-v4`를 mode `0600`으로 저장

배포가 실패하면 성공 형태의 env 파일을 만들지 않는다.

## APIM 정책

모든 조건은 동일하게 다음을 수행한다.

1. API subscription key 검증
2. 요청 source IP가 현재 부하 VM public IP인지 확인
3. `x-logbench-request-id` header 검증
4. request body를 `preserveContent: true`로 한 번 읽기
5. 작은 고정 response와 같은 request ID response header 반환

조건 차이는 다음뿐이다.

| 조건 | App Insights body | Event Hub |
|---|---:|---|
| N8 | 0B | 없음 |
| A8 | 8192B | 없음 |
| E8 | 0B | body 전송 |
| N64 | 0B | 없음 |
| E64 | 0B | body 전송 |

정책은 현재 조건 ID와 policy hash를 response header로 반환한다. 로컬 제어기는 probe 응답이 기대값과 일치할 때만 부하 실행을 시작한다.

## 로컬 실행 제어

### configure-condition.sh

- APIM API diagnostic과 policy를 조건별로 갱신
- 정책 XML과 diagnostic JSON hash 저장
- probe를 반복해 전파 완료 확인
- 고정 횟수 안에 전파되지 않으면 실패

### run-experiment.sh

- 8KB 블록: N8, A8, E8 각 3회
- 64KB 블록: N64, E64 각 3회
- 총 15회
- 조건이 앞·중간·뒤 위치를 고르게 경험하도록 균형 순서 manifest 생성
- 완료된 유효 run은 재실행하지 않고 중단 지점부터 재개
- 판정 경계 또는 한 반복만 반대 방향이면 해당 셀에 2회 추가 가능

각 run에서:

1. 조건 구성과 전파 확인
2. SSH로 VM `run.sh` 실행
3. VM 결과를 SCP로 로컬 `results/<run-id>/`에 회수
4. APIM CPU와 요청 metric 조회
5. run manifest에 유효성·실패 사유 기록

## VM 실행 패키지

### bootstrap.sh

- k6 설치
- Python venv 생성
- Azure Identity와 Event Hubs SDK 설치
- 실행 사용자와 결과 디렉터리 권한 설정
- 설치 버전 manifest 기록

### load.js

- k6 `constant-arrival-rate`
- 500 offered RPS
- retry OFF
- ASCII JSON을 정확히 8192 또는 65536 bytes로 생성
- 고유 request ID와 고정 길이 hash 포함
- response ID·condition·policy hash 확인
- 성공·실패 ID를 localhost collector에 기록
- collector 요청은 별도 tag로 분리해 APIM 성능 집계에서 제외

### collector.py

- localhost에서만 수신
- 성공·실패 request ID를 append-only JSONL로 기록
- 중복 ID를 표시
- 정상 종료 시 flush와 count summary 생성

### consume.py

- VM MI로 Event Hub 인증
- 실험 전용 consumer group 사용
- run 시작 시점 이후 이벤트만 수집
- request ID, hash, 전체 메시지 byte size 기록
- drain은 최대 10분이며 2분 연속 신규 이벤트가 없으면 종료

### reconcile.py

다음을 산출한다.

- APIM 성공 ID 수
- EH 고유 수신 ID 수
- 누락 ID
- 중복 ID
- hash 불일치
- size 불일치
- 최대·분위수 전달 지연

### run.sh

consumer와 collector를 먼저 시작한 뒤 k6를 실행한다. 어느 프로세스든 비정상 종료하면 run을 실패로 표시하되 부분 결과는 보존한다.

## 보안과 비밀

- VM public IP 사용
- SSH는 배포 시 조회한 현재 공인 IP `/32`만 허용
- 공인 IP 자동 조회 실패 시 명시적 CIDR 없이는 배포 중단
- API subscription key는 Git과 Bicep output에 저장하지 않음
- key는 로컬 mode `0600` env와 VM mode `0600` 파일에만 저장
- Event Hubs는 APIM MI Sender와 VM MI Receiver 사용
- connection string 기반 EH 인증은 사용하지 않음
- 실험 API는 subscription key와 VM source IP를 모두 확인

## 실패와 복구

- Bicep, RBAC, logger, policy, bootstrap 실패를 성공으로 처리하지 않음
- 임의 sleep만으로 정책 전파를 가정하지 않음
- VM CPU 평균 70% 초과, network 최대치 70% 초과, dropped iteration, generated/offered 99% 미만, socket/TLS 오류는 run 무효
- EH throttle, server error, drain timeout은 H2/H3 실패 사유로 분리 기록
- 기존 APIM 객체 충돌 시 중단
- teardown 중 APIM 관련 삭제 명령 실행 금지

## 검증

### 정적 검증

- `az bicep build`
- `az deployment group what-if`
- 모든 shell `bash -n`
- APIM delete·purge 및 전역 policy 변경 문자열 부재 확인

### 단위 검증

- 8192/65536 byte payload 정확성
- request ID와 hash 유지
- 정상 reconciliation
- 누락·중복·hash·size 불일치 판정
- resume manifest에서 완료 run 건너뛰기

### Smoke

- 1 RPS, 10초
- N8/A8/E8 설정·응답 header 확인
- E8 consumer 수신과 ID 대조
- App Insights A8 body 길이 소량 확인

## 완료 기준

- 신규 RG 배포와 삭제가 기존 APIM을 삭제하지 않는다.
- APIM 전용 객체는 다음 배포에서 재사용할 수 있다.
- VM에서 500 RPS open workload를 실행할 수 있다.
- 8KB·64KB EH run에서 성공 ID와 수신 ID를 대조할 수 있다.
- 모든 결과는 run별 원시 파일과 manifest로 보존된다.
- 실패 run이 성공 결과로 집계되지 않는다.
