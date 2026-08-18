# Lab 13 — 테스트 스펙 (v2, 재실험 확정본)

> 이 문서는 재실험 **전 리뷰·확정**해야 하는 세 가지를 정의한다: **① 부하 테스트 조건 · ② 반복 횟수 정의 · ③ SKU 사전 리뷰(APIM·Event Hub·Azure Load Testing)**. 전체 가설·측정지표·검증절차·격리원칙은 [`RESULTS.md`](RESULTS.md) 참조.

---

## ① 부하 테스트 조건

ALT은 **closed-model**(고정 VU) → `RPS = 동시성 ÷ 응답시간`. **정확한 RPS 고정 불가** → 동시성을 고정하고 **달성 RPS를 실측**한다. 매 측정은 **steady-state만**(ramp 제외), 배포 직후 **워밍업 런 1회 폐기**.

### 프로파일 A — CPU 포화 (가설 H2·H3, body = 8KB 고정)
| 항목 | 값 |
|---|---|
| 목적 | 게이트웨이 CPU를 포화(≥90%)까지 밀어 로깅 CPU 비용의 throughput 영향 관측 |
| knee 탐색 | 동시성 계단식 `2×250(500)` → `4×250(1000)` → `6×250(1500)`, ramp 30s, dur 120s, 각 1회 |
| knee 판정 | CPU% 포화 & 성공RPS 평탄 & **오류 < 5%** 인 동시성 |
| 본 측정 | knee 동시성에서 C1/C2/C3, 각 **R회**(②), 워밍업+균형순서 |
| body | 8,192 B 고정 |

### 프로파일 B — EH 대용량 방향성 (가설 H5·H6)
| 항목 | 값 |
|---|---|
| body 스윕 | **8 / 32 / 64 / 128 / 200 KB** |
| 부하 | **1 엔진 × 100 threads**(동시성 100), ramp 20s, dur 90s |
| 구성 | 각 body에서 **C2·C3**(+ C1 기준 1회), 각 **R회** |
| 관측 | C3의 **EH Throttled/Dropped/BytesSent** + CPU% + 성공RPS (C2는 8KB 상한 대조) |
| EH 대역폭 참고 | 1 TU=1MB/s. 100 rps 가정 시 8KB=0.8·32KB=3.2·64KB=6.4·128KB=12.8·200KB=20 MB/s |
| EH 용량 세트 | 기본 **1 TU·auto-inflate OFF**(한계 관측). 선택 대조: auto-inflate ON 또는 파티션↑(스케일 관측) |

---

## ② 반복 횟수 정의

| 규칙 | 값 |
|---|---|
| 반복 R | **셀(구성×부하)당 3회.** 범위 > 평균의 15% 면 **R=5로 증량** |
| 순서 균형 | 정순·역순 교차. 3회 예: `C1 C2 C3` · `C3 C2 C1` · `C1 C2 C3` (각 구성이 1·2·3위치 고루 경험) |
| 워밍업 | 배포 직후 1회 **폐기**. 구성 전환 시 전파 대기 90~150s |
| 게이트웨이 | **단일 워밍업된 게이트웨이**에서 구성만 토글(배포 편차 상수화) |
| 이상치 | mean ± (min/max) 보고. 콜드 등 이상치는 **표시**, 제외 시 **근거 명시** |

**실행 예산(가늠)**: A ≈ 12런, B ≈ 33런 → 합 **~45런 ≈ 3~4h + 배포**. 축소안: body 3개(8/64/200)·R=2 → **~20런 ≈ 1.5~2h**. ⚠️ ALT VUH·APIM·EH 시간당 과금.

---

## ③ SKU 사전 리뷰 (이상치를 만들 수 있는 경우의 수 포함)

### APIM
| 항목 | 내용 |
|---|---|
| 후보 | Developer(SLA×·스케일×, 벤치 부적합) · Basic/Standard(classic) · **StandardV2(선택)** · Premium(V2) · Consumption(서버리스·자동스케일=변수) |
| **선택** | **StandardV2 · capacity 1 · autoscale 규칙 없음** (SLA·분단위 배포·현대 v2) |
| 처리량(v1 실측) | ~600 rps @50VU(동시성 제한) · **~2,500~3,000 성공 rps @1000 동시성(CPU 65~80%)** |
| ⚠️ 이상치 경우의 수 | **autoscale 켜지면 유닛 변동→용량 급변**(OFF 확인) · **배포별 유닛 편차**(단일 게이트웨이로 상수화) · 콜드/JIT(워밍업) · 극한부하 플랫폼 429(config-window 분리) · 진단 sampling<100%면 CPU↓(100% 고정) · 메트릭명 classic `Capacity` vs v2 **`CpuPercent_Gateway`** |

### Event Hub (공식 한계 확인됨)
| 항목 | 내용 |
|---|---|
| 후보 | Basic(메시지 **256KB**·1일·파티션32·Capture×) · **Standard(선택)** · Premium/Dedicated |
| Standard 한계 | 메시지 **최대 1MB** · 보존 7일 · **최대 40 TU** · 파티션 **최대 32** · 동시 수신요청 5,000 · **1 TU=1MB/s ingress** |
| **선택** | **Standard · 1 TU · auto-inflate OFF · 4 파티션** (log-to-eventhub는 200KB 상한이라 1MB 메시지로 충분) |
| ⚠️ 이상치 경우의 수 | **auto-inflate ON이면 TU가 1→N 자동증가로 실험 중 용량 변동**(OFF 고정) · **1 TU=1MB/s라 큰 body×RPS에서 throttle/drop**(이게 H6 관측 포인트) · 파티션 부족 시 병렬 병목(4 고정·기록) · 로거 **`isBuffered`** 배치 거동(고정) · partition-key 지정 시 쏠림(미지정=라운드로빈) · 메시지 200KB 초과분 절단 |

### Azure Load Testing
| 항목 | 내용 |
|---|---|
| SKU/과금 | 관리형, **VUH(virtual-user-hours)** = 엔진×VU×시간. 서버측 메트릭 90일·클라이언트 365일 보존 |
| 한계(공식) | 엔진/런 **1~400(max 400)** · 동시 엔진 5~400(max 1000) · JMeter 권장 **≤250 VU/엔진** · 런당 duration ≤24h |
| **선택** | 프로파일 A: **2~6 엔진 × 250** · 프로파일 B: **1 엔진 × 100** |
| ⚠️ 이상치 경우의 수 | **엔진 콜드스타트**(첫 런 느림→워밍업) · **auto-stop**(오류>90%/60s→런 중단, v1 과부하 카오스; 부하를 임계 미만 또는 완화) · **closed-model**(RPS=동시성/응답, 큰 body면 RPS 자연 감소) · **엔진 병목**(엔진 부족→클라이언트-바운드로 게이트웨이 미포화, v1 실패) · ramp 구간 오염(steady-state만) · `testRunStatistics` null(→`metrics list`) |

### 교란 공통
전파 지연(~1-2분)·수집 지연(~2-5분) → 변경 후 대기·재조회 · 단일 리전(japaneast)·동일 세션 시간대 · GatewayLogs **Dedicated** 필수(TotalTime).

---

## 확정 체크리스트 (재실험 착수 전)
- [ ] 부하 조건(①) 확정: knee 탐색 동시성, body 스윕, 프로파일 B 동시성
- [ ] 반복(②) 확정: R=3(또는 축소안), 순서 균형
- [ ] SKU(③) 확정: APIM StandardV2/cap1/autoscale off · EH Standard/1TU/inflate off/4파티션 · ALT 엔진·VU
- [ ] EH 용량 대조 세트(auto-inflate/파티션↑) 포함 여부
- [ ] 실행 예산(시간/비용) 승인
