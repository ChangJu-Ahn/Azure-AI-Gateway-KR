import benchlib as b


def test_clamp_body_bytes_bounds():
    assert b.clamp_body_bytes(0) == 1
    assert b.clamp_body_bytes(-5) == 1
    assert b.clamp_body_bytes(1024) == 1024
    assert b.clamp_body_bytes(10_000_000) == 262144


def test_diagnostic_body_bytes_per_config():
    assert b.diagnostic_body_bytes("C1") is None
    assert b.diagnostic_body_bytes("C2") == 8192
    assert b.diagnostic_body_bytes("C3") == 0


def test_config_uses_eventhub():
    assert b.config_uses_eventhub("C3") is True
    assert b.config_uses_eventhub("C1") is False
    assert b.config_uses_eventhub("C2") is False


def test_bench_policy_xml_eventhub_toggle():
    with_eh = b.bench_policy_xml(True)
    without = b.bench_policy_xml(False)
    assert "log-to-eventhub" in with_eh
    assert 'logger-id="logbench-eh"' in with_eh
    assert "log-to-eventhub" not in without
    # 두 경우 모두 return-response 로 파이프라인 취소
    assert with_eh.count("return-response") == 2
    assert "return-response" in without
    # log-to-eventhub 는 return-response 앞에 있어야 한다 (inbound, 취소 전)
    assert with_eh.index("log-to-eventhub") < with_eh.index("return-response")


def test_gatewaylogs_kql_shape():
    kql = b.gatewaylogs_kql("bench")
    assert "ApiManagementGatewayLogs" in kql
    assert "ApiId == 'bench'" in kql
    assert "TotalTime - BackendTime" in kql


def test_summarize_latencies_percentiles():
    out = b.summarize_latencies([10, 20, 30, 40, 50])
    assert out["n"] == 5
    assert out["mean"] == 30
    assert out["p50"] == 30
    assert 48 <= out["p95"] <= 50
    empty = b.summarize_latencies([])
    assert empty == {"p50": 0.0, "p95": 0.0, "mean": 0.0, "n": 0}


def test_parse_load_test_throughput():
    run = {"testRunStatistics": {"Total": {
        "transactionsPerSecond": 123.4, "pct95ResponseTime": 57.0, "errorPct": 0.5}}}
    out = b.parse_load_test_throughput(run)
    assert out["rps"] == 123.4
    assert out["p95_ms"] == 57.0
    assert out["error_pct"] == 0.5
    assert b.parse_load_test_throughput({}) == {"rps": None, "p95_ms": None, "error_pct": None}
