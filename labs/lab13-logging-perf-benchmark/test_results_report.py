import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
ACTIVE = ROOT / "RESULTS.md"
OLD_RESULTS_CANDIDATES = (ROOT / "old" / "RESULTS-Old.md", ROOT / "old" / "RESULTS.md")
OLD_REVIEW = ROOT / "old" / "REVIEW.md"
OLD_README = ROOT / "old" / "README.md"
ACTIVE_REVIEW = ROOT / "REVIEW.md"

EXPECTED_ACTIVE_H1 = "# Lab 13 최종 결과 보고서 — APIM 로깅 성능·로그 전달 벤치마크"

EXPECTED_OLD_RESULTS_HASH = "123d2e9cac909bbca65e209029e8db02693f0960c07b43fb108b6413413d2e1e"
EXPECTED_OLD_REVIEW_HASH = "d63a309f29e31ccd235d4664fa55375cafc39acf2d48e1493eca332040f01ed6"

QUESTION_HEADINGS = [
    "질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가",
    "질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가",
    "질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가",
    "질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가",
    "질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가",
]

SECTION_HEADINGS = [
    "## 검증 범위",
    "## 핵심 결론",
    "## 질문 1 — App Insights 본문 로깅은 APIM 처리에 영향을 주는가",
    "## 질문 2 — 성능 저하 없이 모든 요청을 로깅할 수 있는가",
    "## 질문 3 — Event Hub 연결은 무손실 로그 전송을 보장하는가",
    "## 질문 4 — 요청 크기는 APIM 처리와 로그 전달에 영향을 주는가",
    "## 질문 5 — Developer v1과 Basic v2 비교에서 전달 결과가 달랐는가",
    "## 고객 운영 권고",
    "## 한계",
    "## 원천 문서",
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
    "| 200 | 0.02 ms | 0.05 ms |",
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


def section_body(text, heading, next_heading_level="##"):
    match = re.search(
        rf"^{re.escape(heading)}\s*(?P<body>.*?)(?=^{re.escape(next_heading_level)} |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"Missing section: {heading}")
    return match.group("body")


class ReviewedResultsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = ACTIVE.read_text(encoding="utf-8")

    def test_archived_files_are_exact(self):
        old_results = next((path for path in OLD_RESULTS_CANDIDATES if path.exists()), None)
        self.assertIsNotNone(old_results, OLD_RESULTS_CANDIDATES)
        self.assertEqual(sha256(old_results), EXPECTED_OLD_RESULTS_HASH)
        self.assertTrue(OLD_REVIEW.exists(), OLD_REVIEW)
        self.assertEqual(sha256(OLD_REVIEW), EXPECTED_OLD_REVIEW_HASH)

    def test_archive_readme_marks_superseded_files_without_changing_archives(self):
        self.assertTrue(OLD_README.exists())
        readme = OLD_README.read_text(encoding="utf-8")
        for phrase in (
            "old/RESULTS.md",
            "old/REVIEW.md",
            "archived/superseded",
            "2026-08-20",
            "../RESULTS.md",
            "byte-for-byte",
            "traceability",
        ):
            self.assertIn(phrase, readme)

    def test_review_is_archived_only(self):
        self.assertTrue(OLD_REVIEW.exists())
        self.assertFalse(ACTIVE_REVIEW.exists())

    def test_h1_and_required_separators_are_exact(self):
        self.assertTrue(self.text.startswith(f"{EXPECTED_ACTIVE_H1}\n\n"))
        separators = re.findall(r"^---$", self.text, re.MULTILINE)
        self.assertEqual(len(separators), 2)
        self.assertIsNotNone(
            re.search(r"^## 핵심 결론[\s\S]*?^---\n\n^## 질문 1", self.text, re.MULTILINE)
        )
        self.assertIsNotNone(
            re.search(
                r"^## 질문 5[\s\S]*?^---\n\n^## 고객 운영 권고",
                self.text,
                re.MULTILINE,
            )
        )

    def test_section_headings_have_exact_required_order(self):
        headings = re.findall(r"^## .+$", self.text, re.MULTILINE)
        self.assertEqual(headings, SECTION_HEADINGS)

    def test_report_is_concise(self):
        line_count = len(self.text.splitlines())
        self.assertGreaterEqual(line_count, 100)
        self.assertLessEqual(line_count, 120)

    def test_has_five_question_conclusion_table(self):
        table = re.search(
            r"^## 핵심 결론\s*(?P<body>.*?)(?=^---$)",
            self.text,
            re.MULTILINE | re.DOTALL,
        ).group("body")
        self.assertEqual(table.count("| Q"), 5)
        for verdict in (
            "조건부 지지",
            "미검증",
            "반박(본 Developer v1 고부하 조건)",
            "조건부 강함",
        ):
            self.assertIn(verdict, table)

    def test_removes_duplicate_finding_sections(self):
        self.assertNotIn("## 직접 확인된 사실", self.text)
        self.assertNotIn("## 조건부로 지지되는 해석", self.text)

    def test_each_question_is_compact(self):
        matches = list(re.finditer(r"^## 질문 [1-5] —", self.text, re.MULTILINE))
        self.assertEqual(len(matches), 5)
        for index, match in enumerate(matches):
            end = (
                matches[index + 1].start()
                if index + 1 < len(matches)
                else self.text.index("\n---", match.start())
            )
            section_lines = self.text[match.start():end].splitlines()
            self.assertLessEqual(len(section_lines), 14)

    def test_shared_caveats_are_consolidated(self):
        limitations = section_body(self.text, "## 한계")
        for phrase in (
            "조건별 대부분 1회",
            "요청 ID",
            "warmup",
            "v2 CPU/메모리",
            "1,000 RPS",
        ):
            self.assertIn(phrase, limitations)

    def test_required_terms_and_scope_are_defined(self):
        for phrase in (
            "로그 저장소",
            "무손실",
            "요청 단위 증명은 완료되지 않았다",
            "드롭",
            "RPS",
            "payload",
            "요청 데이터 크기",
            "SKU",
            "Capacity",
            "Duration",
            "metadata-only 기준선",
            "Developer v1과 Basic v2의 8KB 500 RPS 비교 한 건",
            "대부분 한 번만 실행",
            "1,000 RPS는 테스트하지 않았다",
        ):
            self.assertIn(phrase, self.text)

    def test_decision_tree_is_explicitly_superseded_for_conflicting_guidance(self):
        sources = section_body(self.text, "## 원천 문서")
        self.assertIn("DECISION-TREE.md", sources)
        self.assertIn("앞선 의사결정 가이드", sources)
        self.assertIn(
            "손실 여부·임계값·지연·인과 표현이 충돌하면 활성 RESULTS.md가 우선한다",
            sources,
        )

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
            self.assertIn(f"**판정:** {verdict}", question.group("body"))

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
        self.assertIn("100/200/300/400/500 RPS 포인트", self.text)

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
            r"(EH|Event Hub).*로깅.*순수 (비용|cost)[^\n.?!]*(이다|측정|확정|작다|낮다|낮았다)",
            r"순수 (EH|Event Hub) 로깅 (비용|cost)[^\n.?!]*(이다|측정|확정|작다|낮다|낮았다)",
            r"Duration.*(로그 전달 완전성|delivery-completeness).*지표다",
            r"Capacity.*(보편|universal).*(임계값|threshold).*(이다|로 삼|적용|제시한다)",
            r"(보편|universal).*(Capacity).*(임계값|threshold).*(이다|로 삼|적용|제시한다)",
        ]
        for pattern in banned_patterns:
            self.assertNotRegex(self.text, pattern)

    def test_basic_v2_safe_negations_are_allowed(self):
        self.assertIn("Basic v2 관측 결과는 Developer v1과 다르지만", self.text)
        self.assertIn("원인을 SKU 하나로 단정하지 않는다", self.text)
        self.assertNotRegex(
            self.text,
            r"Basic v2[^.\n]*(무손실.*보장|모든 로그|항상)[^.\n]*(?<!않는다)(?<!아니다)",
        )

    def test_event_hub_throttling_and_64kb_duration_cautions_are_scoped(self):
        required = [
            "EH 스로틀링은 측정창 집계에서 0으로 확인됐고, RPS 구간별 개별 확인은 일부만 기록됐다",
            "E64 300 RPS는 N64보다 Duration이 낮지만 APIM-reported drop 41,435건이 함께 발생했다",
            "Duration은 로그 전달 완전성 지표가 아니며",
            "순수 EH 로깅 비용이나 더 나은 성능으로 해석하지 않는다",
            "활성 고객 결과보고서",
        ]
        for phrase in required:
            self.assertIn(phrase, self.text)

    def test_limitations_cover_execution_deviations(self):
        limitations = section_body(self.text, "## 한계")
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
            self.assertIn(phrase, limitations)

    def test_customer_guidance_includes_body_minimization_and_retest(self):
        guidance = section_body(self.text, "## 고객 운영 권고")
        for phrase in (
            "기록할 본문 크기를 최소화",
            "고객 환경에서 재시험",
        ):
            self.assertIn(phrase, guidance)

    def test_sources_include_required_documents(self):
        sources = section_body(self.text, "## 원천 문서")
        for phrase in (
            "EXPERIMENT-SPEC.md",
            "EXPERIMENT-LOG.md",
            "old/RESULTS-Old.md",
            "old/REVIEW.md",
            "DECISION-TREE.md",
            "REPORT.html",
        ):
            self.assertIn(phrase, sources)


if __name__ == "__main__":
    unittest.main()
