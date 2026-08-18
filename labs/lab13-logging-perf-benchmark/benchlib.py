"""Lab 13 로깅 성능 벤치마크 순수 헬퍼.

Azure 없이 단위테스트 가능하도록 stdlib 만 사용한다. 노트북은 이 모듈을
import 해서 정책 XML·진단 설정·KQL·통계·부하테스트 파싱을 재사용한다.
"""
from __future__ import annotations
from typing import Optional

MAX_BODY_BYTES = 262144  # 256KB 생성 상한 (log-to-eventhub 는 200KB 에서 자동 절단)


def clamp_body_bytes(n: int) -> int:
    """요청 body 크기를 [1, MAX_BODY_BYTES] 로 클램프."""
    if n < 1:
        return 1
    if n > MAX_BODY_BYTES:
        return MAX_BODY_BYTES
    return n


def bench_policy_xml(with_eventhub: bool, logger_id: str = "logbench-eh") -> str:
    """bench echo 엔드포인트의 API 정책.

    inbound 에서 ?bytes=N 크기의 payload 를 만들고, C3 인 경우 그 payload 를
    Event Hub 로 방출한 뒤 return-response 로 파이프라인을 취소한다.
    return-response 는 outbound 를 실행하지 않으므로 log-to-eventhub 는 반드시
    inbound(return-response 이전)에 둔다.
    """
    eh = (
        f'<log-to-eventhub logger-id="{logger_id}">'
        '@((string)context.Variables["payload"])</log-to-eventhub>'
    ) if with_eventhub else ""
    return (
        "<policies>"
        "<inbound><base />"
        '<set-variable name="payload" value="@{'
        'var q = context.Request.Url.Query.GetValueOrDefault(&quot;bytes&quot;, new [] {&quot;1024&quot;});'
        'int n; if (!int.TryParse(q.FirstOrDefault() ?? &quot;1024&quot;, out n)) { n = 1024; }'
        'n = System.Math.Min(System.Math.Max(n, 1), 262144);'
        "return new string('x', n);"
        '}" />'
        f"{eh}"
        "<return-response>"
        '<set-status code="200" reason="OK" />'
        '<set-header name="Content-Type" exists-action="override"><value>text/plain</value></set-header>'
        '<set-body>@((string)context.Variables["payload"])</set-body>'
        "</return-response>"
        "</inbound>"
        "<backend><base /></backend>"
        "<outbound><base /></outbound>"
        "<on-error><base /></on-error>"
        "</policies>"
    )


def diagnostic_body_bytes(config: str) -> Optional[int]:
    """구성별 applicationinsights 진단의 응답 body 로깅 바이트.

    C1 -> None(진단 비활성/삭제), C2 -> 8192, C3 -> 0(메타만).
    """
    return {"C1": None, "C2": 8192, "C3": 0}[config]


def config_uses_eventhub(config: str) -> bool:
    return config == "C3"


def gatewaylogs_kql(api_id: str, start_iso=None, end_iso=None, lookback_min: int = 30) -> str:
    """서버측 게이트웨이 처리시간(TotalTime - BackendTime)을 ResponseSize 별 집계.

    start_iso/end_iso(둘 다 UTC ISO8601)를 주면 그 시간창으로만 필터해 특정 구성의
    트래픽을 귀속한다. 없으면 최근 lookback_min 분을 본다. mock(return-response)은
    BackendTime 이 null 이므로 coalesce 로 0 처리한다(그러지 않으면 percentile 이 전부 null).
    """
    if start_iso and end_iso:
        time_filter = f"| where TimeGenerated between (datetime('{start_iso}') .. datetime('{end_iso}')) "
    else:
        time_filter = f"| where TimeGenerated > ago({lookback_min}m) "
    return (
        "ApiManagementGatewayLogs "
        f"| where ApiId == '{api_id}' "
        f"{time_filter}"
        "| extend gateway_ms = TotalTime - coalesce(BackendTime, 0) "
        "| summarize p50=percentile(gateway_ms,50), p95=percentile(gateway_ms,95), "
        "avg=avg(gateway_ms), n=count() by ResponseSize "
        "| order by ResponseSize asc"
    )


def summarize_latencies(samples_ms: list) -> dict:
    """레이턴시 샘플(ms) 리스트에서 p50/p95/mean/n. 빈 리스트는 0 반환."""
    if not samples_ms:
        return {"p50": 0.0, "p95": 0.0, "mean": 0.0, "n": 0}
    s = sorted(float(x) for x in samples_ms)

    def pct(p: float) -> float:
        if len(s) == 1:
            return s[0]
        k = (len(s) - 1) * (p / 100.0)
        f = int(k)
        c = min(f + 1, len(s) - 1)
        return s[f] + (s[c] - s[f]) * (k - f)

    return {"p50": pct(50), "p95": pct(95), "mean": sum(s) / len(s), "n": len(s)}


def parse_load_test_throughput(run: dict) -> dict:
    """`az load test-run show` 결과에서 throughput/p95/오류율 추출(누락 허용)."""
    out = {"rps": None, "p95_ms": None, "error_pct": None}
    stats = (run or {}).get("testRunStatistics") or {}
    if not stats:
        return out
    total = stats.get("Total") or next(iter(stats.values()), {})
    if total:
        out["rps"] = total.get("transactionsPerSecond")
        out["p95_ms"] = total.get("pct95ResponseTime")
        out["error_pct"] = total.get("errorPct")
    return out
