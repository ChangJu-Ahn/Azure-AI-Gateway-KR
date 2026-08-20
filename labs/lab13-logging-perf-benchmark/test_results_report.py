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
    "App Insights 본문 로깅은 처리시간을 늘렸다.",
    "App Insights 집계는 무손실과 양립하지만 요청 단위 증명은 아니다.",
    "API 성공과 Event Hub 로그 전달 성공은 별개다.",
    "관측된 드롭은 EH 스로틀링으로 설명되지 않았다.",
    "8KB 드롭 전이는 300~400 RPS 사이에서 관측됐다.",
    "큰 요청은 처리시간과 로깅 운영 범위에 영향을 줬다.",
    "Developer v1과 Basic v2에서 전달 결과 차이가 관측됐다.",
]

QUESTION_HEADINGS = [
    "질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가",
    "질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가",
    "질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가",
    "질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가",
    "질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가",
]

SECTION_HEADINGS = [
    "## 용어와 검증 범위",
    "## 요약",
    "## 질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가",
    "## 질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가",
    "## 질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가",
    "## 질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가",
    "## 질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가",
    "## 직접 확인된 사실",
    "## 조건부로 지지되는 해석",
    "## 고객이 고려할 운영 사항",
    "## 한계와 미검증 영역",
    "## 실험 조건과 원천 문서",
]

QUESTION_VERDICTS = {
    "질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가": "조건부 지지",
    "질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가": "미검증",
    "질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가": "반박(본 Developer v1 고부하 조건)",
    "질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가": "조건부 강함",
    "질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가": "조건부 지지",
}

REQUIRED_TABLE_ROWS = [
    # 8 KB Duration table
    "| 100 | 0.01 ms | 0.03 ms |",
    "| 300 | 0.06 ms | 0.13 ms |",
    "| 400 | 0.03 ms | 0.64 ms |",
    "| 500 | 0.1~0.35 ms | 0.9~2.5 ms |",
    # 8 KB Capacity table
    "| 100 | 31.5% | 39% | 38% |",
    "| 200 | 58% | 66% | 85% |",
    "| 300 | 79% | 88.5% | 86.5% |",
    "| 400 | 85.5% | 84.5% | 85.5% |",
    "| 500 | 약 89% | 약 89% | 약 87% |",
    # 8 KB Event Hub drops
    "| E8 | 300 | 54,000 / 54,000 | 0 |",
    "| E8 | 400 | 72,000 / 72,000 | 2,933 |",
    "| E8 | 500 | 150,000 / 150,000 | 대량, 약 절반으로 기록됨 |",
    # 64 KB Duration and drops
    "| 300 | 6.04 ms | 5.24 ms | 41,435 |",
    "| 500 | 7.32 ms | 7.58 ms | 76,434 |",
    # Developer v1 versus Basic v2
    "| EH 도달 | 약 절반만 도달한 것으로 기록, 대량 drop | 분당 약 30,000건 수준: 30056, 29900, 29926, 30108, 29796, 30186 | Basic v2는 EH 도달 수로 판단 |",
    "| APIM EventHubDroppedEvents | 대량 drop 보고 | 직접 비교 가능한 drop 카운터 확보 못 함 | v2 메트릭 수집 비대칭 |",
    "| 게이트웨이 리소스 | classic Capacity 관측 | v2 CPU/메모리 미수집 | 메커니즘 확정 불가 |",
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

    def test_section_headings_have_exact_required_order(self):
        headings = re.findall(r"^## .+$", self.text, re.MULTILINE)
        self.assertEqual(headings, SECTION_HEADINGS)

    def test_summary_has_exactly_seven_required_items(self):
        summary = re.search(
            r"^## 요약\s*(?P<body>.*?)(?=^---$)",
            self.text,
            re.MULTILINE | re.DOTALL,
        ).group("body")
        summary_items = re.findall(r"^\s*(\d+)\.\s+\*\*(.*?)\*\*", summary, re.MULTILINE)
        self.assertEqual([int(number) for number, _ in summary_items], list(range(1, 8)))
        self.assertEqual([heading for _, heading in summary_items], SUMMARY_HEADINGS)

    def test_has_five_reviewed_questions(self):
        for heading in QUESTION_HEADINGS:
            self.assertIn(f"## {heading}", self.text)

    def test_has_five_exact_question_verdicts(self):
        for heading, verdict in QUESTION_VERDICTS.items():
            question = re.search(
                rf"^## {re.escape(heading)}\s*(?P<body>.*?)(?=^## |\Z)",
                self.text,
                re.MULTILINE | re.DOTALL,
            )
            self.assertIsNotNone(question, heading)
            self.assertIn(f"**판정: {verdict}.**", question.group("body"))

    def test_contains_required_measured_tables(self):
        required_headers = [
            "| RPS | N8 — App Insights 메타데이터만 기록한 기준선 Duration | A8 — App Insights body 8KB Duration |",
            "| RPS | N8 Capacity | A8 Capacity | E8 Capacity |",
            "| 조건 | RPS | 클라이언트 성공 | APIM-reported EH drop | 해석 |",
            "| RPS | N64 — App Insights 메타데이터만 기록한 기준선 Duration | E64 — Event Hub 64KB Duration | E64 APIM-reported EH drop |",
            "| 지표 | Developer v1 관측 | Basic v2 관측 | 주의점 |",
        ]
        for header in required_headers:
            self.assertIn(header, self.text)
        for row in REQUIRED_TABLE_ROWS:
            self.assertIn(row, self.text)

    def test_capacity_evidence_is_scoped(self):
        required = [
            "N8/N64 조건은 App Insights diagnostic을 완전히 끈 상태가 아니다",
            "200 RPS에서 E8 Capacity는 85%였고 N8은 58%, A8은 66%였다",
            "400~500 RPS에서는 세 조건 모두 상단 범위에 가까워 Capacity만으로 로깅 효과를 분리할 수 없었다",
            "이 단일 실행들에서 보편 Capacity 임계값을 제시하지 않는다",
        ]
        for phrase in required:
            self.assertIn(phrase, self.text)

    def test_uses_metadata_only_baseline_wording(self):
        self.assertIn("App Insights 메타데이터만 기록한 기준선", self.text)
        self.assertNotIn("N8 무로깅", self.text)
        self.assertNotIn("N64 (무로깅)", self.text)
        self.assertNotRegex(self.text, r"N8[^\n]*(무로깅|diagnostics[- ]?off|완전히 끈 상태다)")
        self.assertNotRegex(self.text, r"N64[^\n]*(무로깅|diagnostics[- ]?off|완전히 끈 상태다)")

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
            "materially",
            "active customer result report",
        ]
        for phrase in banned:
            self.assertNotIn(phrase, self.text)
        banned_patterns = [
            r"Basic v2.*(무손실.*보장|모든 로그|항상)",
            r"Event Hub를 쓰면[^\n]*(무손실|손실 없이)[^\n]*(보장|전달)",
            r"Event Hub 연결만으로[^\n]*(무손실|손실 없이)[^\n]*(보장|전달)",
            r"Event Hub가[^\n]*(모든 로그|전건)[^\n]*(보장|전달)",
            r"8KB.*300 RPS까지.*(무손실|손실 없음|lossless)",
            r"(EH|Event Hub).*로깅.*순수 (비용|cost)",
            r"Duration.*(로그 전달 완전성|delivery-completeness).*지표다",
            r"Capacity.*(보편|universal).*(임계값|threshold).*(이다|로 삼|적용|제시한다)",
        ]
        for pattern in banned_patterns:
            self.assertNotRegex(self.text, pattern)

    def test_event_hub_throttling_and_64kb_duration_cautions_are_scoped(self):
        required = [
            "기록상 EH 스로틀링 관측 없음",
            "각 RPS 행마다 독립 필드가 완전하게 채워졌다는 뜻은 아니다",
            "E64 300 RPS는 N64보다 Duration이 낮지만 APIM-reported drop 41,435건이 함께 발생했다",
            "Duration은 로그 전달 완전성 지표가 아니며",
            "순수 EH 로깅 비용이나 더 나은 성능으로 해석하지 않는다",
            "활성 고객 결과보고서",
        ]
        for phrase in required:
            self.assertIn(phrase, self.text)

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
