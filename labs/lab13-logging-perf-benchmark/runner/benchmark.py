#!/usr/bin/env python3
import argparse
import asyncio
import hashlib
import json
import math
import os
import re
import statistics
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
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
    # padding 과 hash 는 요청마다 동일하므로 런당 1회만 계산한다. requestId 는
    # f"{run_id}-{index:08d}" 로 길이가 고정이라, 조립만으로 정확한 크기가 보장된다.
    sample_id = f"{run_id}-{0:08d}"
    padding, digest = _pad_and_digest(sample_id, target_bytes)
    expected = len(_assemble(sample_id, digest, padding).encode("utf-8"))
    if expected != target_bytes:
        raise ValueError("payload factory did not reach the exact target size")

    def factory(request_id: str) -> tuple[str, str]:
        return _assemble(request_id, digest, padding), digest

    return factory


def percentile(values: list[float], pct: float) -> float:
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


def is_measurement_request_id(run_id: str, request_id: str) -> bool:
    return re.fullmatch(rf"{re.escape(run_id)}-\d{{8}}", request_id) is not None


def reconcile(successes: dict, events: list[dict], expected_size: int) -> dict:
    counts = Counter(event["requestId"] for event in events)
    event_by_id = {}
    for event in events:
        event_by_id.setdefault(event["requestId"], event)
    success_ids = set(successes)
    received_ids = set(event_by_id)
    missing = sorted(success_ids - received_ids)
    duplicates = sorted(key for key, count in counts.items() if count > 1)
    hash_mismatches = sorted(
        key for key in success_ids & received_ids
        if successes[key]["payloadHash"] != event_by_id[key].get("payloadHash")
    )
    size_mismatches = sorted(
        key for key in success_ids & received_ids
        if event_by_id[key].get("byteSize") != expected_size
    )
    return {
        "successCount": len(success_ids),
        "receivedUniqueCount": len(received_ids),
        "missingIds": missing,
        "duplicateIds": duplicates,
        "hashMismatches": hash_mismatches,
        "sizeMismatches": size_mismatches,
        "passed": not (missing or duplicates or hash_mismatches or size_mismatches),
    }


async def run_load(args, run_id: str) -> tuple[dict, dict]:
    import aiohttp
    import gc

    successes = {}
    latencies = []
    errors = []
    measure_body = make_payload_factory(run_id, args.payload_bytes)
    warmup_body = make_payload_factory(run_id + "-w", args.payload_bytes)
    connector = aiohttp.TCPConnector(
        limit=args.concurrency, ttl_dns_cache=300, force_close=False, enable_cleanup_closed=True
    )
    timeout = aiohttp.ClientTimeout(total=args.timeout)
    semaphore = asyncio.Semaphore(args.concurrency)

    async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
        async def one(request_id: str, record: bool, make_body):
            body, digest = make_body(request_id)
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
                        if response.status == 200:
                            if record:
                                successes[request_id] = {"payloadHash": digest, "latencyMs": elapsed}
                                latencies.append(elapsed)
                        else:
                            errors.append({"requestId": request_id, "status": response.status})
                except Exception as exc:
                    errors.append({"requestId": request_id, "error": type(exc).__name__})

        # 커넥션 풀 예열: 측정 시작 전에 concurrency 만큼 커넥션을 미리 열어
        # 측정 초반의 TLS 핸드셰이크 버스트가 꼬리 지연으로 잡히는 것을 막는다.
        await asyncio.gather(*[
            asyncio.create_task(one(f"{run_id}-w-prewarm-{k:03d}", False, warmup_body))
            for k in range(args.concurrency)
        ])

        async def phase(seconds: int, record: bool, prefix: str, make_body) -> tuple[int, float]:
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

    summary = {
        "offered": measure_total,
        "successful": len(successes),
        "errors": len(errors),
        "generatedRate": measure_total / dispatch_wall if dispatch_wall else 0,
        "successfulRps": len(successes) / args.duration,
        "errorRate": len(errors) / measure_total if measure_total else 0,
        "p50Ms": percentile(latencies, 50),
        "p95Ms": percentile(latencies, 95),
        "p99Ms": percentile(latencies, 99),
        "meanMs": statistics.fmean(latencies) if latencies else 0,
        "measureStartUtc": measure_start_utc.isoformat(),
        "measureEndUtc": measure_end_utc.isoformat(),
    }
    return {"successes": successes, "errors": errors}, summary


async def consume_events(args, run_id: str, events: list[dict], stop: asyncio.Event):
    from azure.eventhub.aio import EventHubConsumerClient
    from azure.identity.aio import DefaultAzureCredential

    credential = DefaultAzureCredential()
    client = EventHubConsumerClient(
        fully_qualified_namespace=args.eventhub_namespace,
        eventhub_name=args.eventhub_name,
        consumer_group=args.consumer_group,
        credential=credential,
    )

    async def on_event(_partition_context, event):
        raw = b"".join(event.body)
        try:
            message = json.loads(raw)
        except json.JSONDecodeError:
            return
        request_id = message.get("requestId", "")
        if is_measurement_request_id(run_id, request_id):
            events.append({
                "requestId": request_id,
                "payloadHash": message.get("payloadHash"),
                "byteSize": len(raw),
                "enqueuedTime": event.enqueued_time.isoformat() if event.enqueued_time else None,
            })

    # 소비 시작 시각에서 여유를 두고(과거 datetime) 읽어, consumer 기동 지연 중
    # 도착한 초반 측정 메시지도 놓치지 않는다. warmup 트래픽은 measurement id 필터가 제외한다.
    start_position = datetime.now(timezone.utc) - timedelta(seconds=60)
    task = asyncio.create_task(client.receive(on_event=on_event, starting_position=start_position))
    try:
        await stop.wait()
    finally:
        await client.close()
        await credential.close()
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)


async def execute(args):
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    run_id = args.run_id
    events = []
    stop = asyncio.Event()
    consumer_task = None
    if args.condition.startswith("E"):
        consumer_task = asyncio.create_task(consume_events(args, run_id, events, stop))
        await asyncio.sleep(5)

    records, summary = await run_load(args, run_id)
    if consumer_task:
        previous = -1
        quiet = 0
        for _ in range(args.drain_seconds):
            await asyncio.sleep(1)
            if len(events) == previous:
                quiet += 1
            else:
                quiet = 0
                previous = len(events)
            if quiet >= args.quiet_seconds:
                break
        stop.set()
        await consumer_task

    result = {"summary": summary, "errors": records["errors"]}
    if args.condition.startswith("E"):
        result["reconciliation"] = reconcile(records["successes"], events, args.payload_bytes)
    (output / "successes.json").write_text(json.dumps(records["successes"]), encoding="utf-8")
    (output / "events.json").write_text(json.dumps(events), encoding="utf-8")
    (output / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


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
    parser.add_argument("--drain-seconds", type=int, default=600)
    parser.add_argument("--quiet-seconds", type=int, default=120)
    parser.add_argument("--eventhub-namespace", default=os.getenv("LOGBENCH_EH_FQDN"))
    parser.add_argument("--eventhub-name", default=os.getenv("LOGBENCH_EH_NAME", "logbench-v4"))
    parser.add_argument("--consumer-group", default=os.getenv("LOGBENCH_EH_CONSUMER", "logbench-v4"))
    return parser.parse_args()


if __name__ == "__main__":
    asyncio.run(execute(parse_args()))
