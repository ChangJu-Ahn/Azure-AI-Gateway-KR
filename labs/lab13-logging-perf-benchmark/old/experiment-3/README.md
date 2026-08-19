# Lab 13: 로깅 성능 벤치마크 (배포 → 측정 → 삭제)

APIM 게이트웨이에서 **로깅 구성이 성능에 미치는 영향**을, 공식 문서의 가설을 세우고
**직접 호출해 정량 측정**하는 독립 실습 랩입니다. 공유 리소스와 완전히 격리된 전용
리소스그룹에 배포하고, 측정 후 **통째로 삭제**해 비용을 경계 짓습니다.

## 무엇을 비교하나

| 구성 | 설명 | 공식 문서 가설 |
|------|------|----------------|
| **C1** | 로깅 없음 | 기준선(최소 오버헤드), 감사 불가 |
| **C2** | App Insights + body 8KB | "payload 로깅은 성능 저하"·"1,000 req/s 초과 시 throughput 40~50%↓"; 8KB 에서 평탄화 |
| **C3** | App Insights body=0 + `log-to-eventhub` | "샘플링 무관·전량·200KB"; 부하에서 상대적 평탄 |

## 측정을 어떻게 신뢰하나 (백엔드/네트워크 배제)

- **백엔드 제거**: bench 엔드포인트는 `return-response` mock 이라 백엔드 호출이 없어
  `BackendTime≈0`. "APIM 이 제어 못 하는 백엔드 지연" 변수가 실험에 없습니다.
- **서버측 자(ruler)**: `ApiManagementGatewayLogs.TotalTime − BackendTime` 로 APIM
  순수 처리시간을 얻어 **클라이언트↔APIM 네트워크까지 배제**합니다. 이 GatewayLogs
  진단은 C1/C2/C3 전 구성 상시 ON 이라 그 자체 오버헤드는 delta 에서 상쇄됩니다.
- 클라이언트 wall-clock 은 엔드유저 체감(교차검증)용입니다.

## 실행 순서

```bash
# 1) 배포 (⚠️ Standard v2 · Event Hub · Load Testing = 시간당 과금)
ACK_STANDARD_V2_COST=true ./scripts/deploy-logbench.sh

# 2) 노트북 실행
#    - 1차(body 크기): 그대로 실행
#    - 2차(부하): 커널 환경에 RUN_LOAD_TEST=true, az extension add --name load 필요
jupyter notebook labs/lab13-logging-perf-benchmark/benchmark-logging-performance.ipynb

# 3) 삭제 (반드시!)
./scripts/teardown-logbench.sh
```

- **DRY_RUN**: 배포/호출 없이 노트북 흐름만 검증하려면 커널 환경에 `DRY_RUN=true`.
- 단위테스트: `cd labs/lab13-logging-perf-benchmark && python -m pytest test_benchlib.py -q`

## 비용 경고

Standard v2 APIM(시간당), Event Hubs(Standard), Azure Load Testing(VUH), App Insights
ingest 가 과금됩니다. **측정이 끝나면 즉시 `teardown-logbench.sh` 로 RG 를 삭제**하세요.

## 공식 문서 근거

- Integrate Azure API Management with Application Insights — payload 로깅 성능 영향, throughput 40~50%↓, body logging skip
- `log-to-eventhub` policy — 샘플링 무관·전량 로깅·200KB
- `return-response` policy — 파이프라인 취소(outbound 미실행)
- ApiManagementGatewayLogs — `TotalTime`/`BackendTime`
- API Management v2 tiers / Upgrade and scale — Standard v2 배포 속도·SLA

## 다음 단계

→ [Lab 12: 리소스 정리](../lab12-cleanup/README.md) (공유 랩 정리)
