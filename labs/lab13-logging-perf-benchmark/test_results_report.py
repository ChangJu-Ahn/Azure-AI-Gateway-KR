import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
ACTIVE = ROOT / "RESULTS.md"
OLD_RESULTS = ROOT / "old" / "RESULTS.md"
OLD_REVIEW = ROOT / "old" / "REVIEW.md"
ACTIVE_REVIEW = ROOT / "REVIEW.md"

EXPECTED_HASHES = {
    OLD_RESULTS: "123d2e9cac909bbca65e209029e8db02693f0960c07b43fb108b6413413d2e1e",
    OLD_REVIEW: "d63a309f29e31ccd235d4664fa55375cafc39acf2d48e1493eca332040f01ed6",
}

SUMMARY_HEADINGS = [
    "App Insights 본문 로깅은 처리시간을 늘렸다",
    "App Insights 집계는 무손실과 양립하지만 요청 단위 증명은 아니다",
    "API 성공과 Event Hub 로그 전달 성공은 별개다",
    "관측된 드롭은 EH 스로틀링으로 설명되지 않았다",
    "8KB 드롭 전이는 300~400 RPS 사이에서 관측됐다",
    "큰 요청은 처리시간과 로깅 운영 범위에 영향을 줬다",
    "Developer v1과 Basic v2에서 전달 결과 차이가 관측됐다",
]

QUESTION_HEADINGS = [
    "질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가",
    "질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가",
    "질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가",
    "질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가",
    "질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가",
]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ReviewedResultsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = ACTIVE.read_text(encoding="utf-8")

    def test_archived_files_are_exact(self):
        for path, expected in EXPECTED_HASHES.items():
            self.assertTrue(path.exists(), path)
            self.assertEqual(sha256(path), expected)

    def test_review_is_archived_only(self):
        self.assertTrue(OLD_REVIEW.exists())
        self.assertFalse(ACTIVE_REVIEW.exists())

    def test_summary_has_required_order(self):
        summary = re.search(
            r"^## 요약\s*(?P<body>.*?)(?=^---$)",
            self.text,
            re.MULTILINE | re.DOTALL,
        ).group("body")
        positions = [summary.index(f"**{heading}.**") for heading in SUMMARY_HEADINGS]
        self.assertEqual(positions, sorted(positions))

    def test_has_five_reviewed_questions(self):
        for heading in QUESTION_HEADINGS:
            self.assertIn(f"## {heading}", self.text)

    def test_uses_metadata_only_baseline_wording(self):
        self.assertIn("App Insights 메타데이터만 기록한 기준선", self.text)
        self.assertNotIn("N8 무로깅", self.text)
        self.assertNotIn("N64 (무로깅)", self.text)

    def test_prohibited_overclaims_are_absent(self):
        banned = [
            "App Insights(100%)가 EH보다 기록 완전성이 높았다",
            "이중 인과 확정",
            "8KB는 300 RPS까지 무손실",
            "약 16배 안정화",
            "실질 처리 한계는 500 RPS",
            "정상(무손실) 구간에서는 App Insights가",
            "Basic v2로 올리면 EH가 무손실로 모든 로그를 남긴다",
            "EH 로깅 순수 비용",
        ]
        for phrase in banned:
            self.assertNotIn(phrase, self.text)

    def test_limitations_cover_execution_deviations(self):
        required = [
            "조건별 3회 반복",
            "요청 ID",
            "페이로드 해시",
            "대부분 1회",
            "warmup",
            "v2 CPU/메모리",
            "1,000 RPS",
        ]
        for phrase in required:
            self.assertIn(phrase, self.text)


if __name__ == "__main__":
    unittest.main()
