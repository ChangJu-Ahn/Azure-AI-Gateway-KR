# Lab 13 재현 가이드

리소스를 삭제한 뒤 다시 실험하려면 이 순서를 따른다. 모든 결과·시간창은 `EXPERIMENT-LOG.md`에 보존돼 있고, Azure 서버측 메트릭은 조회 시점 기준 90일 보관된다.

## 자산 위치

| 자산 | 경로 |
|---|---|
| 실험 리소스 IaC (EH/VM/network, 기존 APIM 참조) | `infra/logbench-v4.bicep` |
| Basic v2 APIM IaC (SKU 비교용) | `infra/apim-basicv2.bicep` |
| 배포/조건전환/실행/삭제 | `scripts/logbench-v4/{deploy,configure-condition,run-experiment,teardown}.sh` |
| RPS 스윕 자동화 | `scripts/logbench-v4/sweeps/` |
| 부하 생성기 (순수, EH소비 없음) | `labs/lab13-logging-perf-benchmark/runner/benchmark.py` |
| 결과 대장 | `labs/lab13-logging-perf-benchmark/EXPERIMENT-LOG.md` |
| 설계 스펙 | `labs/lab13-logging-perf-benchmark/EXPERIMENT-SPEC.md` |

## 재현 순서

### 1. 기존 Developer v1 APIM으로 실험
```bash
export LOGBENCH_APIM_NAME="<기존 APIM 이름>"
export LOGBENCH_APIM_RG="<기존 APIM RG>"
./scripts/logbench-v4/deploy.sh   # 신규 RG에 EH 40TU + D8as_v5 VM 배포, 기존 APIM에 logbench-v4 API/로거 추가
```
- deploy가 `.env.logbench-v4` 생성 (RG, VM IP, EH FQDN, SSH키 등)
- 부하는 `benchmark.py`를 VM에서 nohup 실행 (SSH 끊김 대비 필수)

### 2. 단일 조건 측정 (예: 8KB 500 RPS E8)
```bash
source .env.logbench-v4
./scripts/logbench-v4/configure-condition.sh E8   # N8/A8/E8/N64/E64
URL="https://${LOGBENCH_APIM_NAME}.azure-api.net/logbench-v4/echo"
ssh -i "$LOGBENCH_SSH_KEY" "${LOGBENCH_VM_USER}@${LOGBENCH_VM_IP}" \
  "cd ~/logbench && nohup ./.venv/bin/python benchmark.py \
    --url '$URL' --condition E8 --run-id myrun --output ~/logbench/results/myrun \
    --payload-bytes 8192 --rate 500 --concurrency 20 --warmup-seconds 120 --duration 300 \
    > ~/logbench/myrun.log 2>&1 &"
```
- payload: 8KB=8192, 64KB=65536
- 결과 result.json에 measureStartUtc/EndUtc 기록됨 → 서버 메트릭 조회에 사용

### 3. RPS 스윕 (자동)
```bash
scripts/logbench-v4/sweeps/run_rps_sweep_500-300.sh   # 500,400,300 × N8/A8/E8
scripts/logbench-v4/sweeps/run_rps_sweep_200-100.sh   # 200,100 × N8/A8/E8
scripts/logbench-v4/sweeps/run_64k_500-300.sh         # 500,300 × N64/E64
```
각 스크립트가 `results/*-windows.txt`에 (run, condition, rps, startUtc, endUtc) 기록.

### 4. 서버측 메트릭 조회 (EXPERIMENT-LOG.md 상단 "서버측 재조회 명령" 참조)
측정창(UTC)만 있으면 APIM Capacity/Duration/EventHubDroppedEvents, EH IncomingMessages/Throttled, App Insights AppRequests count 를 조회.

### 5. Basic v2 SKU 비교 (선택) — 완전 자동화
```bash
./scripts/logbench-v4/setup-basicv2.sh   # Basic v2 배포 + API/EH로거/E8 정책 전부 설정
# 그 후 VM에서 benchmark.py로 8KB 500 RPS E8 측정
# 드롭 판정: EH IncomingMessages 분당 수 = 500×60=30,000 이면 무손실, 적으면 드롭
# (Basic v2는 EventHubDroppedEvents 메트릭이 비어있을 수 있어 EH IncomingMessages로 교차검증)
```
결과: Developer v1은 500 RPS에서 약 절반 드롭, Basic v2는 무손실 → 드롭 원인=게이트웨이 SKU 확정.

### 6. 삭제
```bash
./scripts/logbench-v4/teardown.sh   # 신규 RG만 삭제. 기존 APIM은 건드리지 않음
# ⚠️ SKU 상향 실험을 했다면 기존 APIM SKU 복원 확인 (EXPERIMENT-LOG.md "SKU 상향 실험" 참조)
```

## 알려진 함정 (재현 시 주의)

1. **NSG SSH 규칙이 거버넌스로 주기적 삭제됨** — 각 런 전 `ensure_ssh_rule`로 재적용 (sweep 스크립트에 포함).
2. **VM이 deallocate될 수 있음** — 자동 종료 정책 가능. `az vm start`로 재기동, runner 파일은 디스크에 보존됨.
3. **benchmark.py는 반드시 VM에서 nohup 실행** — SSH 세션에 묶으면 끊길 때 프로세스도 죽음.
4. **concurrency=20 고정** — 과도하면 TLS 핸드셰이크 churn으로 클라이언트 p99 꼬리 증가.
5. **드롭 판정은 서버 메트릭 EventHubDroppedEvents** — 클라이언트 EH 소비는 부하와 경합해 부정확(구버전 코드에서 제거됨).
