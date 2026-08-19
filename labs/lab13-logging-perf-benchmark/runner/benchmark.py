#!/usr/bin/env python3
"""Lab 13 순수 부하 생성기.

APIM에 고정 도착률로 POST를 보내고, 클라이언트 관점의 성공 수/RPS/latency와
측정 창(UTC)만 기록한다. EH 유실·App Insights 유실 등 로깅 sink의 무손실 여부는
이 프로세스가 아니라 실험 후 서버측 메트릭으로 판정한다:
  - APIM Capacity (게이트웨이 부하%)
  - APIM EventHubSuccessfulEvents / EventHubDroppedEvents
  - Event Hubs IncomingMessages
클라이언트가 EH를 직접 소비하면 부하 생성과 이벤트 루프를 다투어 측정이 오염되므로
소비/대조 로직은 두지 않는다.
"""
import argparse
import asyncio
import gc
import hashlib
import json
import math
import statistics
import time
from datetime import datetime, timezone
from pathlib import Path


def _assemble(request_id: str, digest: str, padding: str) -> str:
    return (
        '{"requestId":"' + request_id
        + '","payloadHash":"' + digest
        + '","payload":"' + padding + '"}'
    )


def _pad_and_digest(request_id: str, target_bytes: int) -> tuple[str, str]:
    overhead = len(_assemble(request_id, "0" * 64, "").encode("utf-8"))
    padding_size = target_bytes - overhead
    if padding_size < 0:
        raise ValueError(f"target size {target_bytes} is too small")
    padding = "x" * padding_size
    digest = hashlib.sha256(padding.encode("ascii")).hexdigest()
    return padding, digest


def build_payload(request_id: str, target_bytes: int) -> tuple[str, str]:
    padding, digest = _pad_and_digest(request_id, target_bytes)
    body = _assemble(request_id, digest, padding)
    if len(body.encode("utf-8")) != target_bytes:
        raise ValueError("payload serialization did not reach the exact target size")
    return body, digest


def make_payload_factory(run_id: str, target_bytes: int):
    sample_id = f"{run_id}-{0:08d}"
    padding, digest = _pad_and_digest(sample_id, target_bytes)
    expected = len(_assemble(sample_id, digest, padding).encode("utf-8"))
    if expected != target_bytes:
        raise ValueError("payload factory did not reach the exact target size")

    def factory(request_id: str) -> tuple[str, str]:
        return _assemble(request_id, digest, padding), digest

    return factory


def percentile(values, pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    index = (len(ordered) - 1) * pct / 100
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return float(ordered[lower])
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


async def run_load(args, run_id: str) -> dict:
    import aiohttp

    successful = 0
    latencies = []
    errors = []
    status_counts = {}
    measure_body = make_payload_factory(run_id, args.payload_bytes)
    warmup_body = make_payload_factory(run_id + "-w", args.payload_bytes)
    connector = aiohttp.TCPConnector(
        limit=args.concurrency, ttl_dns_cache=300, force_close=False, enable_cleanup_closed=True
    )
    timeout = aiohttp.ClientTimeout(total=args.timeout)
    semaphore = asyncio.Semaphore(args.concurrency)

    async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
        async def one(request_id, record, make_body):
            nonlocal successful
            body, _ = make_body(request_id)
            headers = {
                "Content-Type": "application/json",
                "x-logbench-request-id": request_id,
            }
            async with semaphore:
                before = time.perf_counter()
                try:
                    async with session.post(args.url, data=body, headers=headers) as response:
                        await response.read()
                        elapsed = (time.perf_counter() - before) * 1000
                        if record:
                            status_counts[response.status] = status_counts.get(response.status, 0) + 1
                        if response.status == 200:
                            if record:
                                successful += 1
                                latencies.append(elapsed)
                        elif record:
                            errors.append({"requestId": request_id, "status": response.status})
                except Exception as exc:
                    if record:
                        errors.append({"requestId": request_id, "error": type(exc).__name__})

        # 커넥션 풀 예열: 초반 TLS 핸드셰이크 버스트가 측정 꼬리로 잡히는 것을 줄인다.
        await asyncio.gather(*[
            asyncio.create_task(one(f"{run_id}-w-prewarm-{k:03d}", False, warmup_body))
            for k in range(args.concurrency)
        ])

        async def phase(seconds, record, prefix, make_body):
            total = args.rate * seconds
            start = time.monotonic()
            tasks = []
            for index in range(total):
                due = start + index / args.rate
                delay = due - time.monotonic()
                if delay > 0:
                    await asyncio.sleep(delay)
                tasks.append(asyncio.create_task(one(f"{prefix}-{index:08d}", record, make_body)))
            dispatch_wall = time.monotonic() - start
            await asyncio.gather(*tasks)
            return total, dispatch_wall

        if args.warmup_seconds > 0:
            await phase(args.warmup_seconds, False, run_id + "-w", warmup_body)
        gc.collect()
        gc.disable()
        measure_start_utc = datetime.now(timezone.utc)
        try:
            measure_total, dispatch_wall = await phase(args.duration, True, run_id, measure_body)
        finally:
            gc.enable()
        measure_end_utc = datetime.now(timezone.utc)

    return {
        "runId": run_id,
        "condition": args.condition,
        "payloadBytes": args.payload_bytes,
        "rate": args.rate,
        "offered": measure_total,
        "successful": successful,
        "errors": len(errors),
        "statusCounts": status_counts,
        "generatedRate": measure_total / dispatch_wall if dispatch_wall else 0,
        "successfulRps": successful / args.duration,
        "errorRate": len(errors) / measure_total if measure_total else 0,
        "p50Ms": percentile(latencies, 50),
        "p95Ms": percentile(latencies, 95),
        "p99Ms": percentile(latencies, 99),
        "meanMs": statistics.fmean(latencies) if latencies else 0,
        "measureStartUtc": measure_start_utc.isoformat(),
        "measureEndUtc": measure_end_utc.isoformat(),
        "errorSample": errors[:20],
    }


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--condition", choices=["N8", "A8", "E8", "N64", "E64"], required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--payload-bytes", type=int, required=True)
    parser.add_argument("--rate", type=int, default=500)
    parser.add_argument("--warmup-seconds", type=int, default=120)
    parser.add_argument("--duration", type=int, default=300)
    parser.add_argument("--concurrency", type=int, default=20)
    parser.add_argument("--timeout", type=int, default=10)
    return parser.parse_args()


def main():
    args = parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    summary = asyncio.run(run_load(args, args.run_id))
    (output / "result.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
