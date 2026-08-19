import json
import tempfile
import unittest
from pathlib import Path

from runner.benchmark import (
    build_payload,
    is_measurement_request_id,
    percentile,
    reconcile,
)


class BenchmarkTests(unittest.TestCase):
    def test_payload_has_exact_size_and_hash(self):
        for size in (8192, 65536):
            body, digest = build_payload("run-1-000001", size)
            self.assertEqual(len(body.encode("utf-8")), size)
            parsed = json.loads(body)
            self.assertEqual(parsed["requestId"], "run-1-000001")
            self.assertEqual(parsed["payloadHash"], digest)

    def test_percentile_interpolates(self):
        self.assertEqual(percentile([1, 2, 3, 4], 50), 2.5)
        self.assertEqual(percentile([1, 2, 3, 4], 95), 3.85)

    def test_measurement_id_excludes_warmup_prefix_collision(self):
        self.assertTrue(is_measurement_request_id("01-E8", "01-E8-00000001"))
        self.assertFalse(is_measurement_request_id("01-E8", "01-E8-warmup-00000001"))
        self.assertFalse(is_measurement_request_id("01-E8", "01-E8-1"))

    def test_reconcile_detects_missing_duplicate_and_mismatch(self):
        successes = {
            "a": {"payloadHash": "ha"},
            "b": {"payloadHash": "hb"},
            "c": {"payloadHash": "hc"},
        }
        events = [
            {"requestId": "a", "payloadHash": "ha", "byteSize": 8192},
            {"requestId": "a", "payloadHash": "ha", "byteSize": 8192},
            {"requestId": "b", "payloadHash": "wrong", "byteSize": 1},
        ]
        result = reconcile(successes, events, 8192)
        self.assertEqual(result["missingIds"], ["c"])
        self.assertEqual(result["duplicateIds"], ["a"])
        self.assertEqual(result["hashMismatches"], ["b"])
        self.assertEqual(result["sizeMismatches"], ["b"])
        self.assertFalse(result["passed"])


if __name__ == "__main__":
    unittest.main()
