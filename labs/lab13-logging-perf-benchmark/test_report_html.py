import re
import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).parent
REPORT = ROOT / "REPORT.html"

SOURCE_DOCS = [
    "RESULTS.md",
    "EXPERIMENT-LOG.md",
    "EXPERIMENT-SPEC.md",
    "DECISION-TREE.md",
]

SECTION_IDS = [
    "executive-summary",
    "results-full",
    "decision",
    "evidence",
    "experiment",
    "guardrails",
    "limitations",
]

CHART_IDS = [
    "chart-capacity-8k",
    "chart-duration-8k",
    "chart-drops-8k",
    "chart-duration-64k",
    "chart-drops-64k",
    "chart-saturation-outcomes",
    "chart-sku-comparison",
]

CAPACITY_VALUES = ["31.5%", "58%", "79%", "85.5%", "~89%", "39%", "66%", "88.5%", "84.5%", "38%", "85%", "86.5%", "~87%"]
DURATION_VALUES = ["0.01 ms", "0.03 ms", "0.02 ms", "0.05 ms", "0.04 ms", "0.06 ms", "0.13 ms", "0.36 ms", "0.64 ms", "1.00 ms", "0.10~0.35 ms", "0.90~2.50 ms", "0.40~1.70 ms"]
BASIC_V2_MINUTES = ["30,056", "29,900", "29,926", "30,108", "29,796", "30,186"]

RESULT_FILES = sorted(
    str(path.relative_to(ROOT))
    for path in (ROOT / "results").glob("*/result.json")
)


class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []
        self.external_assets = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        element_id = values.get("id")
        if element_id:
            self.ids.add(element_id)
        if tag == "a" and values.get("href"):
            self.links.append(values["href"])
        if tag in {"script", "link", "img"}:
            target = values.get("src") or values.get("href")
            if target and re.match(r"^(?:https?:)?//", target):
                self.external_assets.append(target)


class VisibleTextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self._skip_tags = []
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style"}:
            self._skip_tags.append(tag)

    def handle_endtag(self, tag):
        if self._skip_tags and self._skip_tags[-1] == tag:
            self._skip_tags.pop()

    def handle_data(self, data):
        if self._skip_tags:
            return
        text = " ".join(data.split())
        if text:
            self.parts.append(text)


class ReportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = REPORT.read_text(encoding="utf-8")
        cls.parser = ReportParser()
        cls.parser.feed(cls.html)
        visible_parser = VisibleTextParser()
        visible_parser.feed(cls.html)
        cls.visible_text = " ".join(visible_parser.parts)

    def chart_fragment(self, chart_id):
        match = re.search(
            rf'<figure[^>]*id="{re.escape(chart_id)}"[\s\S]*?</figure>',
            self.html,
        )
        self.assertIsNotNone(match, chart_id)
        return match.group(0)

    def section_fragment(self, section_id):
        match = re.search(
            rf'<section[^>]*id="{re.escape(section_id)}"[\s\S]*?</section>',
            self.html,
        )
        self.assertIsNotNone(match, section_id)
        return match.group(0)

    def text_without_tags(self, fragment):
        return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", fragment)).strip()

    def chart_text_sequence(self, chart_id):
        fragment = self.chart_fragment(chart_id)
        return re.findall(
            r'<text class="(?:group-label|series-label(?: mono)?|value-label)"[^>]*>([^<]+)</text>',
            fragment,
        )

    def svg_group_fragment(self, fragment, *, rps, value, series=None):
        open_tag_pattern = re.compile(r'<g\b[^>]*>')
        token_pattern = re.compile(r'</g>|<g\b[^>]*>')
        rps_pattern = re.compile(rf'\bdata-rps="{re.escape(str(rps))}"')
        value_pattern = re.compile(rf'\bdata-value="{re.escape(str(value))}"')
        series_pattern = (
            re.compile(rf'\bdata-series="{re.escape(str(series))}"')
            if series is not None
            else None
        )

        for opening_match in open_tag_pattern.finditer(fragment):
            opening_tag = opening_match.group(0)
            if not (rps_pattern.search(opening_tag) and value_pattern.search(opening_tag)):
                continue
            if series_pattern is not None and not series_pattern.search(opening_tag):
                continue

            depth = 1
            for token_match in token_pattern.finditer(fragment, opening_match.end()):
                token = token_match.group(0)
                if token.startswith('<g'):
                    depth += 1
                else:
                    depth -= 1
                    if depth == 0:
                        return fragment[opening_match.start():token_match.end()]

            self.fail(f"unbalanced svg group for rps={rps} value={value}")

        self.fail(f"missing svg group for rps={rps} value={value}")

    def test_has_scroll_sections_in_approved_order(self):
        positions = []
        for section_id in SECTION_IDS:
            position = self.html.find(f'id="{section_id}"')
            self.assertNotEqual(position, -1, section_id)
            positions.append(position)
        self.assertEqual(positions, sorted(positions))

    def test_has_semantic_navigation_and_accessible_charts(self):
        self.assertIn("<nav", self.html)
        self.assertIn("<main", self.html)
        self.assertRegex(self.html, r'href="#main-content"')
        self.assertRegex(self.html, r'class="[^"]*skip-link[^"]*"')
        self.assertRegex(self.html, r':focus-visible\s*\{[\s\S]*?outline:\s*(?!none\b)[^;}]+')
        self.assertRegex(self.html, r'@media\s*(?:screen\s+and\s+)?\(max-width:')
        self.assertIn("@media print", self.html)
        for section_id in SECTION_IDS:
            self.assertIn(f'href="#{section_id}"', self.html)
        self.assertEqual(re.findall(r'<li><a href="#([^"]+)"', self.html), SECTION_IDS)
        for chart_id in CHART_IDS:
            fragment = self.chart_fragment(chart_id)
            self.assertIn('role="img"', fragment)
            self.assertRegex(fragment, r'aria-label="[^"]*[가-힣][^"]*"')
            self.assertIn("<title>", fragment)

    def test_is_self_contained(self):
        self.assertEqual(self.parser.external_assets, [])
        for pattern in (r"\bfetch\s*\(", r"\bXMLHttpRequest\b", r"@import\b"):
            self.assertNotRegex(self.html, pattern)

    def test_progressive_enhancement_keeps_content_visible(self):
        self.assertNotRegex(self.html, r"\.js\s+main\s*\{[^}]*display:\s*none")
        self.assertIn("<noscript>", self.html)

    def test_sticky_navigation_preserves_headings_and_marks_current_location(self):
        self.assertRegex(
            self.html,
            r'<a\b(?=[^>]*\bhref="#executive-summary")(?=[^>]*\baria-current="location")[^>]*>',
        )
        self.assertIn('a[aria-current="location"]', self.html)
        self.assertIn('setAttribute("aria-current", "location")', self.html)
        self.assertIn('addEventListener("hashchange"', self.html)
        self.assertIn("scrollHeight", self.html)
        self.assertRegex(
            self.html,
            r'main\s*>\s*section\s*\{[^}]*scroll-margin-top:\s*(?:[7-9]\d|\d{3,})px',
        )

    def test_report_body_wraps_long_technical_identifiers(self):
        self.assertRegex(
            self.html,
            r'main\s*\{[^}]*overflow-wrap:\s*anywhere',
        )

    def test_source_names_are_listed_without_dead_links(self):
        self.assertEqual([href for href in self.parser.links if not href.startswith("#")], [])
        for name in SOURCE_DOCS + RESULT_FILES:
            self.assertIn(name, self.html)
        self.assertEqual(len(RESULT_FILES), 19)

    def test_capacity_duration_and_drop_values_are_present(self):
        self.assertEqual(
            self.chart_text_sequence("chart-capacity-8k"),
            [
                "100 RPS", "N8", "31.5%", "A8", "39%", "E8", "38%",
                "200 RPS", "N8", "58%", "A8", "66%", "E8", "85%",
                "300 RPS", "N8", "79%", "A8", "88.5%", "E8", "86.5%",
                "400 RPS", "N8", "85.5%", "A8", "84.5%", "E8", "85.5%",
                "500 RPS", "N8", "~89%", "A8", "~89%", "E8", "~87%",
            ],
        )
        self.assertEqual(
            self.chart_text_sequence("chart-duration-8k"),
            [
                "100 RPS", "N8", "0.01 ms", "A8", "0.03 ms", "E8", "0.03 ms",
                "200 RPS", "N8", "0.02 ms", "A8", "0.05 ms", "E8", "0.04 ms",
                "300 RPS", "N8", "0.06 ms", "A8", "0.13 ms", "E8", "0.36 ms",
                "400 RPS", "N8", "0.03 ms", "A8", "0.64 ms", "E8", "1.00 ms",
                "500 RPS", "N8", "0.10~0.35 ms", "A8", "0.90~2.50 ms", "E8", "0.40~1.70 ms",
            ],
        )
        drops_fragment = self.chart_fragment("chart-drops-8k")
        self.assertIn("300 RPS", drops_fragment)
        self.assertIn("400 RPS", drops_fragment)
        self.assertIn("500 RPS", drops_fragment)
        row_300 = self.svg_group_fragment(drops_fragment, rps=300, value=0)
        self.assertIn('<text', row_300)
        self.assertIn('>0</text>', row_300)
        row_400 = self.svg_group_fragment(drops_fragment, rps=400, value="2,933")
        self.assertIn('<text', row_400)
        self.assertIn('>2,933</text>', row_400)
        row_500 = self.svg_group_fragment(drops_fragment, rps=500, value="unknown")
        self.assertRegex(row_500, r'class="[^"]*(?:offscale|qualitative)-marker[^"]*"')
        self.assertIn("정확한 드롭률 미확정", row_500)
        self.assertNotRegex(row_500, r'<rect[^>]*class="[^"]*\bbar\b[^"]*"')
        self.assertNotRegex(row_500, r'<text[^>]*>\s*\d[\d,]*\s*</text>')
        self.assertIn("300 RPS", self.chart_text_sequence("chart-drops-8k"))
        self.assertIn("400 RPS", self.chart_text_sequence("chart-drops-8k"))
        self.assertIn("500 RPS", self.chart_text_sequence("chart-drops-8k"))
        self.assertEqual(
            self.chart_text_sequence("chart-duration-64k"),
            [
                "300 RPS", "N64", "6.04 ms", "E64", "5.24 ms",
                "500 RPS", "N64", "7.32 ms", "E64", "7.58 ms",
            ],
        )

    def test_metric_chart_rows_expose_machine_readable_observations(self):
        capacity = self.chart_fragment("chart-capacity-8k")
        self.assertEqual(capacity.count('class="metric-row"'), 15)
        self.svg_group_fragment(capacity, rps=200, series="E8", value=85)

        duration = self.chart_fragment("chart-duration-8k")
        self.assertEqual(duration.count('class="metric-row"'), 15)
        self.svg_group_fragment(
            duration,
            rps=500,
            series="E8",
            value="0.40~1.70",
        )

        duration_64k = self.chart_fragment("chart-duration-64k")
        self.assertEqual(duration_64k.count('class="metric-row"'), 4)
        self.svg_group_fragment(duration_64k, rps=300, series="E64", value=5.24)

        drops_64k = self.chart_fragment("chart-drops-64k")
        self.assertEqual(drops_64k.count('class="metric-row"'), 2)
        self.svg_group_fragment(drops_64k, rps=300, series="E64", value="41,435")
        self.svg_group_fragment(drops_64k, rps=500, series="E64", value="76,434")

    def test_dense_svg_labels_use_separate_layout_slots(self):
        drops = self.chart_fragment("chart-drops-8k")
        self.assertEqual(
            len(re.findall(r'<text class="series-label mono" x="88"[^>]*>E8</text>', drops)),
            3,
        )

        sku = self.chart_fragment("chart-sku-comparison")
        self.assertIn("동일 조건 · SKU만 교체", sku)
        self.assertNotIn("Event Hub 도달 (기대 ~30,000/분)", sku)

    def test_sku_comparison_puts_both_skus_side_by_side(self):
        sku = self.chart_fragment("chart-sku-comparison")
        self.assertIn('data-sku="developer-v1"', sku)
        self.assertIn('data-sku="basic-v2"', sku)
        self.assertIn("\uc57d \uc808\ubc18", sku)
        self.assertIn("\uc815\ud655\ud55c \ube44\uc728 \ubbf8\ud655\uc815", sku)
        self.assertNotRegex(sku, r"\ub4dc\ub86d\s*0\b")
        for minute in BASIC_V2_MINUTES:
            self.assertIn(minute, sku)

    def test_client_latency_is_only_used_where_it_is_a_controlled_comparison(self):
        # 클라이언트 p99는 Q6(SKU 대조)에서만 증거 능력이 있다. Q1~Q5의 권위 지표는 서버측이다.
        self.assertNotIn('id="chart-client-latency"', self.html)
        sku = self.chart_fragment("chart-sku-comparison")
        svg = sku[sku.index("<svg") : sku.index("</svg>")]
        self.assertIn('data-measure="client-p99"', svg)
        self.assertRegex(svg, r"약\s*500\s*ms")
        self.assertRegex(svg, r"\b30\s*ms")
        annotation = sku[sku.index("</svg>") :]
        self.assertRegex(annotation, r"같은 방식|동일 수집|공통 조건")

    def test_report_never_claims_the_client_tail_originates_outside_apim(self):
        # SKU만 교체하자 ~500ms 꼬리가 30ms로 사라졌으므로 '게이트웨이 밖' 단정은 반박된다.
        self.assertNotRegex(self.html, r"APIM 밖에서 생긴")
        self.assertNotRegex(self.html, r"APIM 서버측과 무관")

    def test_run_ledger_survives_under_experiment_design(self):
        experiment = self.section_fragment("experiment")
        self.assertIn('id="run-ledger"', experiment)
        ledger = experiment[experiment.index('id="run-ledger"') :]
        self.assertIn("오류 0", ledger)
        self.assertEqual(len(re.findall(r"results/[^<]+/result\.json", ledger)), 19)
        for value in ("506.87", "563.79", "1112.23"):
            self.assertIn(value, ledger)

    def test_run_ledger_warns_that_client_ranking_contradicts_server_ranking(self):
        experiment = self.section_fragment("experiment")
        ledger = experiment[experiment.index('id="run-ledger"') :]
        self.assertRegex(ledger, r"546\.83")
        self.assertRegex(ledger, r"563\.79")
        self.assertRegex(ledger, r"뒤집|역전|반대")

    def test_every_evidence_chart_opens_with_a_meaning_line(self):
        for chart_id in CHART_IDS:
            with self.subTest(chart=chart_id):
                fragment = self.chart_fragment(chart_id)
                lede = fragment[fragment.index("</h3>") : fragment.index("<svg")]
                self.assertRegex(lede, r'<p class="chart-lede"><span class="lede-label">의미</span>')
                prose = re.sub(r"<[^>]+>", "", lede).replace("의미", "", 1).strip()
                self.assertGreaterEqual(len(prose), 40)
        self.assertIn(".lede-label {", self.html)

    def test_aggregate_counts_are_not_presented_as_end_to_end_lossless(self):
        saturation = self.chart_fragment("chart-saturation-outcomes")
        self.assertRegex(
            saturation,
            r'<text class="outcome-line"[^>]*>AppRequests 측정창 집계 150,178건</text>',
        )
        self.assertIn("요청 ID 단위 대조 없음", saturation)

        sku = self.chart_fragment("chart-sku-comparison")
        self.assertIn("드롭 미관측", sku)
        self.assertIn("요청 ID 대조 미수행", sku)
        self.assertIn("종단 간 무손실이나 원인을 확정할 수 없습니다", sku)
        self.assertNotIn("일정 도달로 무손실", sku)

        self.assertNotRegex(self.html, r"빨간 띠|빨간 띄")

    def test_executive_headline_scopes_log_loss_to_event_hub_saturation(self):
        executive = self.section_fragment("executive-summary")
        headline = re.search(
            r'<h2[^>]*class="primary-statement"[^>]*>([\s\S]*?)</h2>',
            executive,
        )
        self.assertIsNotNone(headline)
        self.assertIn("<br", headline.group(1))
        statement = self.text_without_tags(headline.group(1))
        self.assertIn("Event Hub", statement)
        self.assertIn("포화", statement)
        self.assertNotEqual(statement, "API 요청은 100% 성공해도 감사 로그는 유실될 수 있다")
        for phrase in (
            "Developer v1",
            "8KB 400 RPS · 64KB 300 RPS",
            "App Insights",
            "부하 완화 또는 SKU 상향",
        ):
            self.assertIn(phrase, executive)
        self.assertIn("게이트웨이가 포화하면", self.html)

    def test_embedded_results_stay_collapsed_by_default(self):
        embedded = self.section_fragment("results-full")
        details = re.search(r"<details[^>]*>", embedded)
        self.assertIsNotNone(details)
        self.assertNotIn("open", details.group(0))

    def test_executive_summary_points_to_embedded_results(self):
        executive = self.section_fragment("executive-summary")
        self.assertRegex(
            executive,
            r'<a href="#results-full"[^>]*>[^<]*결과 보고서 원문[^<]*</a>',
        )

    def test_executive_summary_stays_scannable_not_narrative(self):
        executive = self.section_fragment("executive-summary")
        self.assertNotIn("습니다", executive)
        self.assertNotIn('class="lede"', executive)

    def test_executive_summary_visualizes_two_path_sacrifice(self):
        executive = self.section_fragment("executive-summary")
        self.assertIn('data-path="app-insights"', executive)
        self.assertIn('data-path="event-hub"', executive)
        self.assertIn("150,000 / 150,000 HTTP 성공", executive)
        self.assertIn("처리시간 증가 · 로그 보존", executive)
        self.assertIn("로그 폐기 · 작업량 감소", executive)
        self.assertIn("0.9~2.5 ms", executive)
        self.assertIn("0.4~1.7 ms", executive)

    def test_executive_summary_lists_six_key_findings_and_scope(self):
        executive = self.section_fragment("executive-summary")
        self.assertEqual(len(re.findall(r'class="finding-item"', executive)), 6)
        for phrase in (
            "8,192 bytes",
            "N8 58% · A8 66% · E8 85%",
            "Event Hubs가 아닌 APIM 게이트웨이",
            "Developer v1의 공식 예상 최대치",
            "APIM 전송 성공·드롭 수",
            "Event Hubs 수신·스로틀링",
            "API 응답 성공률만으로는 로그 유실 감지 불가",
            "Korea Central",
            "대부분 1회 실행",
        ):
            self.assertIn(phrase, executive)

    def test_exact_visible_labels_cover_basic_v2_and_limit_phrases(self):
        for phrase in CAPACITY_VALUES + DURATION_VALUES + BASIC_V2_MINUTES:
            self.assertIn(phrase, self.visible_text)
        for phrase in (
            "정확한 드롭률 미확정",
            "300~400 RPS 사이에서 드롭 전이가 관측",
            "드롭 구간 Duration은 성능 우열 근거가 아님",
            "8,192 bytes",
            "200KB",
        ):
            self.assertIn(phrase, self.visible_text)

    def test_experiment_section_keeps_cautions_in_scope(self):
        experiment = self.section_fragment("experiment")
        for phrase in (
            "APIM success/drop",
            "Event Hubs ingress/throttling",
            "API 성공률",
            "로그 전달 성공률",
            "요청 ID",
            "워밍업",
        ):
            self.assertIn(phrase, experiment)
        self.assertNotIn("운영 모니터링", experiment)

    def test_guardrails_section_keeps_operational_monitoring_copy_in_scope(self):
        guardrails = self.section_fragment("guardrails")
        for phrase in (
            "APIM 권위 지표 아님 · 보조 증거",
            "APIM 서버측 Duration/Capacity",
            "EventHubDroppedEvents",
            "판정의 우선 근거",
        ):
            self.assertIn(phrase, guardrails)

    def test_sources_section_keeps_precedence_copy_in_scope(self):
        embedded = self.section_fragment("results-full")
        for phrase in (
            "RESULTS.md가 우선",
            "활성 공식 결과 보고서",
            "보관된 이전 해석",
        ):
            self.assertIn(phrase, embedded)

    def test_decision_tree_has_required_nodes_and_loop_warning(self):
        decision = self.section_fragment("decision")
        for phrase in (
            "로깅 목적",
            "본문 필요 여부",
            "8KB 초과 여부",
            "목표 RPS × payload",
            "용량 확보",
            "같은 부하로 재시험",
            "저장소 선택",
            "Event Hubs TU 증설은 APIM 드롭의 기본 해법이 아닙니다",
        ):
            self.assertIn(phrase, decision)
        self.assertRegex(self.text_without_tags(decision), r"재시험\s*→\s*부하 판정")

    def test_decision_tree_branches_and_terminates_at_sink_alerts(self):
        decision = self.section_fragment("decision")
        sinks = re.search(r'<ul class="sink-branches"[\s\S]*?</ul>', decision)
        self.assertIsNotNone(sinks)
        self.assertIn('data-node="app-insights"', sinks.group(0))
        self.assertIn('data-node="event-hub"', sinks.group(0))
        self.assertIn('data-node="app-insights-alert"', decision)
        self.assertIn('data-node="event-hub-alert"', decision)
        self.assertIn('data-node="monitoring-exit"', decision)
        self.assertIn("데이터 수집 한도", decision)
        self.assertIn("EventHubDroppedEvents 알림 필수", decision)
        self.assertIn("드롭이 나도 요청은 200", decision)

    def test_sink_choice_states_destination_criteria_not_body_size_only(self):
        decision = self.section_fragment("decision")
        sink_choice = re.search(
            r'<li class="decision-node" data-node="sink-choice"[\s\S]*?<ul class="sink-branches"',
            decision,
        )
        self.assertIsNotNone(sink_choice)
        for phrase in (
            "본문이 필요 없어도",
            "갈림은 목적지",
            "외부 실시간 스트리밍",
            "이 분기에 오지 않습니다",
        ):
            self.assertIn(phrase, sink_choice.group(0))

    def test_results_report_is_embedded_for_standalone_sharing(self):
        embedded = self.section_fragment("results-full")
        self.assertIn("Lab 13 \ucd5c\uc885 \uacb0\uacfc \ubcf4\uace0\uc11c", embedded)
        for heading in (
            "\uc9c8\ubb38 1 \u2014",
            "\uc9c8\ubb38 2 \u2014",
            "\uc9c8\ubb38 3 \u2014",
            "\uc9c8\ubb38 4 \u2014",
            "\uc9c8\ubb38 5 \u2014",
            "\uc9c8\ubb38 6 \u2014",
        ):
            self.assertIn(heading, embedded)
        for value in ("2,933", "41,435", "76,434", "150,178", "30056"):
            self.assertIn(value, embedded)
        self.assertGreaterEqual(embedded.count("<table>"), 10)
        self.assertIn("\uc774\ub984\uc73c\ub85c\ub9cc 표기", embedded)

    def test_scenario_recommendations_are_not_duplicated_as_a_section(self):
        for token in (
            'id="recommendations"',
            'href="#recommendations"',
            "recommendation-item",
            "recommendation-grid",
            "\uc2dc\ub098\ub9ac\uc624\ubcc4",
        ):
            self.assertNotIn(token, self.html)
        self.assertIn("\uc2f1\ud06c \uc18c\ube44 \uc9c0\uc5f0\uacfc \ud30c\ud2f0\uc158 \ucc98\ub9ac\ub7c9", self.section_fragment("limitations"))

    def test_decision_steps_are_collapsed_below_the_flowchart(self):
        decision = self.section_fragment("decision")
        chart_pos = decision.index('class="diagram-scroll"')
        details = re.search(
            r'<details class="[^"]*step-details[^"]*">\s*<summary>([^<]+)</summary>',
            decision,
        )
        self.assertIsNotNone(details)
        self.assertIn("단계별", details.group(1))
        self.assertGreater(details.start(), chart_pos)
        self.assertGreater(decision.index('class="decision-flow"'), details.start())

    def test_decision_track_layout_keeps_branching_steps_readable(self):
        self.assertRegex(self.html, r"\.decision-track\s*\{[^}]*align-items:\s*start")
        self.assertRegex(
            self.html,
            r'\.decision-node\[data-node="sink-choice"\][\s\S]{0,160}?grid-column:\s*1\s*/\s*-1',
        )
        self.assertNotRegex(
            self.html,
            r"\.decision-track\s*\{[^}]*grid-template-columns:\s*repeat\(4,",
        )

    def test_drop_check_is_scoped_to_event_hub_paths(self):
        decision = self.section_fragment("decision")
        chart = re.search(r'<svg class="decision-connectors[^"]*"[\s\S]*?</svg>', decision).group(0)
        self.assertIn('data-role="sink-choice"', chart)
        self.assertEqual(chart.count('data-role="eh-load-check"'), 1)
        self.assertIn("Event Hub 경로 전용 판정", chart)
        self.assertIn("드롭 미관측 · 처리시간 증가 감안", chart)
        self.assertIn("외부 실시간 스트리밍(SIEM·데이터레이크)", chart)
        self.assertIn("Azure Monitor 통합(쿼리·알림·분석)", chart)
        for leaked in (
            "본문 &gt; 8KB 고정",
            "8KB 이하 또는 메타데이터만",
            "8KB 초과는 이미 고정됨",
            "실시간 스트리밍 · 본문 &gt; 8KB",
        ):
            self.assertNotIn(leaked, chart)

    def test_decision_flowchart_mirrors_source_tree(self):
        decision = self.section_fragment("decision")
        chart = re.search(r'<svg class="decision-connectors[^"]*"[\s\S]*?</svg>', decision)
        self.assertIsNotNone(chart)
        svg = chart.group(0)
        self.assertIn('role="img"', svg)
        self.assertNotIn('aria-hidden="true"', svg)
        self.assertRegex(svg, r'aria-label="[^"]*[가-힣][^"]*"')
        self.assertIn("<title>", svg)
        for label in (
            "APIM 로깅 설계 시작",
            "로깅 목적?",
            "App Insights 선택",
            "App Insights + 적정 기록 비율",
            "본문 크기 &gt; 8KB?",
            "Event Hub 경로만 가능",
            "부하 재측정",
            "드롭 0 달성 → 재판정",
            "저장소 선택",
            "App Insights 100% 기록",
            "Event Hub + 드롭 알림",
            "데이터 수집 한도",
            "EventHubDroppedEvents 알림 필수",
        ):
            self.assertIn(label, svg)

    def test_report_uses_korean_chart_context_not_tabbed_copy(self):
        self.assertNotIn('role="tab"', self.html)
        self.assertNotIn('role="tabpanel"', self.html)
        self.assertNotIn('data-tab=', self.html)


if __name__ == "__main__":
    unittest.main()
