import json
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).parent
REPORT = ROOT / "REPORT.html"

TAB_IDS = [
    "summary",
    "hypotheses",
    "conditions",
    "results",
    "limitations",
    "guidance",
    "sources",
]

SOURCE_DOCS = [
    "EXPERIMENT-SPEC.md",
    "EXPERIMENT-LOG.md",
    "RESULTS.md",
    "DECISION-TREE.md",
]

RESULT_FILES = sorted(
    str(path.relative_to(ROOT))
    for path in (ROOT / "results").glob("*/result.json")
)

REQUIRED_CHARTS = [
    "chart-capacity-8k",
    "chart-duration-8k",
    "chart-drops-8k",
    "chart-duration-64k",
    "chart-drops-64k",
    "chart-client-latency",
    "chart-request-success",
    "chart-sku-comparison",
    "chart-confidence",
]

REQUIRED_EVIDENCE_LABELS = [
    "확정",
    "조건부",
    "드롭/위험",
    "미검증",
    "교정",
]

LIGHT_TOKEN_LINES = [
    "color-scheme: light;",
    "--cp-bg: #f7f4ef;",
    "--cp-bg-elevated: #fcfbf8;",
    "--cp-surface: #ffffff;",
    "--cp-surface-soft: #f5f5f5;",
    "--cp-border: #dedede;",
    "--cp-border-strong: #919191;",
    "--cp-text: #242424;",
    "--cp-text-muted: #5c5c5c;",
    "--cp-text-soft: #6f6f6f;",
    "--cp-accent: #b11f4b;",
    "--cp-accent-hover: #9a1a41;",
    "--cp-accent-soft: rgba(177, 31, 75, 0.08);",
    "--cp-accent-fg: #ffffff;",
    "--cp-success: #16a34a;",
    "--cp-danger: #dc2626;",
    "--cp-warning: #f59e0b;",
    "--cp-link: #0078d4;",
    "--cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.12);",
    "--cp-overlay: rgba(255, 255, 255, 0.8);",
    "--cp-panel: rgba(255, 255, 255, 0.86);",
    "--cp-panel-strong: rgba(255, 255, 255, 0.96);",
    "--cp-sheen: rgba(255, 255, 255, 0.55);",
    "--cp-highlight: rgba(177, 31, 75, 0.12);",
]

RESULT_FIELDS = ["offered", "successful", "errors", "p50Ms", "p95Ms", "p99Ms"]


class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.tabs = []
        self.external_assets = []
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"])
        if values.get("role") == "tab":
            self.tabs.append(values)
        if tag in {"script", "link", "img"}:
            target = values.get("src") or values.get("href")
            if target and re.match(r"^(?:https?:)?//", target):
                self.external_assets.append(target)
        if tag == "a" and values.get("href"):
            self.hrefs.append(values["href"])


class ReportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = REPORT.read_text(encoding="utf-8")
        cls.parser = ReportParser()
        cls.parser.feed(cls.html)
        cls.results = {
            str(path.relative_to(ROOT)): json.loads(path.read_text(encoding="utf-8"))
            for path in sorted((ROOT / "results").glob("*/result.json"))
        }

    def chart_fragment(self, chart_id):
        match = re.search(
            rf'<figure class="chart-card[^"]*" id="{re.escape(chart_id)}"[\s\S]*?</figure>',
            self.html,
        )
        self.assertIsNotNone(match, chart_id)
        return match.group(0)

    def css_body(self, selector):
        match = re.search(
            rf"{re.escape(selector)}\s*\{{(?P<body>.*?)\n\s*\}}",
            self.html,
            re.DOTALL,
        )
        self.assertIsNotNone(match, selector)
        return match.group("body")

    def print_media(self):
        match = re.search(r"@media print\s*\{(?P<body>[\s\S]*?)\n\s*\}\s*@media", self.html)
        self.assertIsNotNone(match)
        return match.group("body")

    def text_without_tags(self, fragment):
        return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", fragment)).strip()

    def chart_text_sequence(self, chart_id):
        fragment = self.chart_fragment(chart_id)
        return re.findall(
            r'<text class="(?:group-label|series-label(?: mono)?|value-label)"[^>]*>([^<]+)</text>',
            fragment,
        )

    def test_has_required_tabs_and_panels(self):
        self.assertEqual(
            [tab["data-tab"] for tab in self.parser.tabs],
            TAB_IDS,
        )
        for tab_id in TAB_IDS:
            self.assertIn(f"panel-{tab_id}", self.parser.ids)

    def test_is_self_contained(self):
        self.assertEqual(self.parser.external_assets, [])
        banned_runtime_loading = [
            r"\bfetch\s*\(",
            r"\bXMLHttpRequest\b",
            r"\bimport\s*\(",
            r"@import\b",
            r"url\(\s*['\"]?https?://",
        ]
        for pattern in banned_runtime_loading:
            self.assertNotRegex(self.html, pattern)

    def test_references_all_source_documents(self):
        for source in SOURCE_DOCS:
            self.assertIn(source, self.html)

    def test_source_references_are_relative_links(self):
        expected = SOURCE_DOCS + RESULT_FILES
        for href in expected:
            self.assertIn(href, self.parser.hrefs)
        for href in self.parser.hrefs:
            self.assertNotRegex(href, r"^(?:https?:)?//")

    def test_has_accessible_tab_markup(self):
        for tab in self.parser.tabs:
            self.assertEqual(tab.get("aria-controls"), f"panel-{tab['data-tab']}")
        self.assertIn('role="tabpanel"', self.html)

    def test_print_and_no_script_fallbacks_exist(self):
        self.assertIn("@media print", self.html)
        self.assertIn("<noscript>", self.html)

    def test_print_only_hides_tab_navigation(self):
        self.assertRegex(
            self.html,
            r"@media print[\s\S]*?\[role=\"tablist\"\]\s*\{\s*display:\s*none;",
        )
        self.assertRegex(
            self.html,
            r"@media print[\s\S]*?\[role=\"tabpanel\"\]\s*\{\s*display:\s*block\s*!important;",
        )
        self.assertNotRegex(
            self.html,
            r"@media print[\s\S]*?\.tabs\s*\{\s*display:\s*none;",
        )

    def test_print_forces_light_tokens_and_avoids_card_breaks(self):
        media = self.print_media()
        for token_line in LIGHT_TOKEN_LINES:
            self.assertIn(token_line, media)
        self.assertIn("background: var(--cp-surface);", media)
        self.assertIn("color: var(--cp-text);", media)
        self.assertIn("break-inside: avoid;", media)
        self.assertIn("page-break-inside: avoid;", media)

    def test_maintenance_notice_mentions_manual_html_update_for_source_numbers(self):
        self.assertRegex(
            self.html,
            r"source-number changes require a manual HTML update",
            re.IGNORECASE,
        )

    def test_evidence_legend_uses_required_meanings(self):
        match = re.search(
            r"<dt>Evidence legend</dt>\s*<dd>(.*?)</dd>",
            self.html,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        legend = re.sub(r"<[^>]+>", " ", match.group(1)).lower()
        for required in ("초록=확정", "노랑=조건부", "빨강=드롭/위험", "회색=미검증", "교정=별도 텍스트 상태"):
            self.assertIn(required, legend)
        for banned in ("drops/risks(교정)", "planned", "reconciled", "pending"):
            self.assertNotIn(banned, legend)

    def test_evidence_badges_use_neutral_text_and_semantic_accent_tokens(self):
        base = next(
            match.group("body")
            for match in re.finditer(r"\.evidence\s*\{(?P<body>.*?)\n\s*\}", self.html, re.DOTALL)
            if "--evidence-accent" in match.group("body")
        )
        self.assertIn("--evidence-accent: var(--cp-border-strong);", base)
        self.assertIn("color: var(--cp-text);", base)
        self.assertIn("border: 1px solid var(--evidence-accent);", base)
        dot = self.css_body(".evidence::before")
        self.assertIn("background: var(--evidence-accent);", dot)
        for selector, token in (
            (".evidence.confirmed", "var(--cp-success)"),
            (".evidence.conditional", "var(--cp-warning)"),
            (".evidence.risk", "var(--cp-danger)"),
            (".evidence.unverified", "var(--cp-text-muted)"),
            (".evidence.corrected", "var(--cp-accent)"),
        ):
            body = self.css_body(selector)
            self.assertIn(f"--evidence-accent: {token};", body)
            self.assertNotRegex(body, r"\bcolor\s*:")

    def test_references_all_19_client_results(self):
        self.assertEqual(len(RESULT_FILES), 19)
        for result_file in RESULT_FILES:
            self.assertIn(result_file, self.html)

    def test_has_all_required_charts(self):
        for chart_id in REQUIRED_CHARTS:
            self.assertIn(chart_id, self.parser.ids)

    def test_chart_cards_reset_default_figure_margin_and_can_shrink(self):
        match = re.search(
            r"\.chart-card\s*\{(?P<body>.*?)\n\s*\}",
            self.html,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        body = match.group("body")
        self.assertIn("margin: 0;", body)
        self.assertIn("min-width: 0;", body)

    def test_value_labels_are_right_aligned_for_narrow_viewports(self):
        match = re.search(
            r"\.value-label\s*\{(?P<body>.*?)\n\s*\}",
            self.html,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        self.assertIn("text-anchor: start;", match.group("body"))

    def test_long_metric_names_wrap_inside_cards(self):
        self.assertRegex(
            self.html,
            r"\.panel-card p,\s*\.panel-card li,\s*\.source-item p,\s*\.chart-note,\s*\.chart-source\s*\{"
            r"[\s\S]*?overflow-wrap:\s*anywhere;",
        )

    def test_numeric_chart_bars_stay_within_tracks(self):
        for chart_id in REQUIRED_CHARTS:
            if chart_id in {"chart-sku-comparison", "chart-confidence"}:
                continue
            fragment = self.chart_fragment(chart_id)
            tracks = [
                (float(x), float(width))
                for x, width in re.findall(
                    r'<rect class="range-track" x="([0-9.]+)" y="[0-9.]+" width="([0-9.]+)"',
                    fragment,
                )
            ]
            bars = [
                (float(x), float(width))
                for x, width in re.findall(
                    r'<rect class="bar [^"]+" x="([0-9.]+)" y="[0-9.]+" width="([0-9.]+)"',
                    fragment,
                )
            ]
            self.assertLessEqual(len(bars), len(tracks), chart_id)
            for (track_x, track_width), (bar_x, bar_width) in zip(tracks, bars):
                self.assertGreaterEqual(bar_x + 0.01, track_x, chart_id)
                self.assertLessEqual(bar_x + bar_width, track_x + track_width + 0.1, chart_id)

    def test_representative_chart_widths_follow_declared_scales(self):
        expectations = [
            ("chart-capacity-8k", 'width="94.5"', "31.5% of 300px track"),
            ("chart-duration-64k", 'width="196.5"', "5.24/8ms of 300px track"),
            ("chart-drops-8k", 'width="293.3"', "2933/3000 drops of 300px track"),
            ("chart-drops-64k", 'width="286.6"', "76434/80000 drops of 300px track"),
        ]
        for chart_id, expected_width, description in expectations:
            with self.subTest(description):
                self.assertIn(expected_width, self.chart_fragment(chart_id))

    def test_capacity_chart_matches_every_source_matrix_value(self):
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

    def test_duration_charts_match_every_source_matrix_value(self):
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
        self.assertEqual(
            self.chart_text_sequence("chart-duration-64k"),
            [
                "300 RPS", "N64", "6.04 ms", "E64", "5.24 ms",
                "500 RPS", "N64", "7.32 ms", "E64", "7.58 ms",
            ],
        )

    def test_500_rps_e8_drop_marker_is_off_scale_qualitative(self):
        fragment = self.chart_fragment("chart-drops-8k")
        row = re.search(r">500 RPS</text>(?P<row>[\s\S]*?)</svg>", fragment).group("row")
        self.assertNotIn('<rect class="bar', row)
        self.assertNotRegex(row, r">[0-9][0-9,]*</text>")
        marker = re.search(r'data-run="real-E8"[^>]*cx="([0-9.]+)"', row)
        self.assertIsNotNone(marker)
        self.assertGreater(float(marker.group(1)), 430.0)
        self.assertIn("off-scale · 정확한 드롭률 미확정", row)

    def test_uses_all_evidence_labels(self):
        for label in REQUIRED_EVIDENCE_LABELS:
            self.assertIn(label, self.html)

    def test_contains_required_scope_and_cautions(self):
        required = [
            "Korea Central",
            "Developer v1",
            "Basic v2",
            "8KB",
            "64KB",
            "100~500 RPS",
            "3회 반복",
            "metadata-only",
            "1,000 RPS",
            "warmup",
            "request ID",
        ]
        for phrase in required:
            self.assertIn(phrase, self.html)

    def test_experiment_conditions_include_required_infrastructure_without_row_grades(self):
        conditions = re.search(
            r'<section role="tabpanel" id="panel-conditions"[\s\S]*?</section>',
            self.html,
        ).group(0)
        required = [
            "Event Hubs Standard 40 TU",
            "32 partitions",
            "auto-inflate OFF",
            "Standard_D8as_v5",
            "Python asyncio/aiohttp",
            "concurrency 20",
            "retry disabled",
            "warmup",
        ]
        for phrase in required:
            self.assertIn(phrase, conditions)
        self.assertNotIn("<th>증거 등급</th>", conditions)

    def test_condition_definition_source_line_has_no_evidence_badge(self):
        conditions = re.search(
            r'<section role="tabpanel" id="panel-conditions"[\s\S]*?</section>',
            self.html,
        ).group(0)
        source = re.search(r'<p class="chart-source">(?P<body>[\s\S]*?)</p>', conditions).group("body")
        self.assertIn("조건 정의에는 색상 등급을 붙이지 않고", self.text_without_tags(source))
        self.assertNotRegex(source, r'class="evidence')

    def test_summary_has_customer_action_list_and_scoped_eh_bottleneck_evidence(self):
        summary = re.search(r'id="panel-summary"[\s\S]*?</section>', self.html).group(0)
        required_actions = [
            "API SLO와 로깅 SLO를 분리",
            "APIM EH drop/success와 EH ingress/throttling을 함께 모니터링",
            "피크 RPS × 기록 페이로드 크기",
            "v1은 classic Capacity, v2는 gateway CPU/memory",
        ]
        for action in required_actions:
            self.assertIn(action, summary)
        for evidence in ("8KB 500 RPS", "약 4 MB/s", "40 TU의 약 10%", "EH throttling 0"):
            self.assertIn(evidence, summary)

    def test_hero_marks_queue_mechanism_as_conditional_or_inferred(self):
        hero = re.search(r"<header class=\"hero\">[\s\S]*?</header>", self.html).group(0)
        self.assertIn("큐 한도 메커니즘은 조건부/추정", hero)

    def test_hypothesis_cards_include_safe_reuse_payload_sku_and_corrections(self):
        hypotheses = re.search(r'id="panel-hypotheses"[\s\S]*?</section>', self.html).group(0)
        self.assertGreaterEqual(hypotheses.count("안전 재사용 문장:"), 5)
        for heading in ("payload 운영 범위", "SKU 비교", "교정된 문장:"):
            self.assertIn(heading, hypotheses)
        self.assertIn("Event Hub가 항상 App Insights보다 빠르다고 말하지 않는다", hypotheses)
        self.assertIn("Developer v1의 최대 처리량을 500 RPS로 확정하지 않는다", hypotheses)

    def test_64kb_duration_chart_has_delivery_completeness_caution(self):
        fragment = self.chart_fragment("chart-duration-64k")
        self.assertIn("APIM Duration은 전달 완전성 지표가 아닙니다", fragment)
        self.assertIn("E/N 차이는 순수한 로깅 비용 측정치가 아닙니다", fragment)

    def test_client_latency_chart_is_supporting_and_uses_neutral_series_color(self):
        fragment = self.chart_fragment("chart-client-latency")
        self.assertIn("APIM 권위 지표 아님 · 보조 증거", fragment)
        self.assertNotRegex(fragment, r'class="bar series-(?:a|n|e|warning|danger|success)"')
        self.assertRegex(fragment, r'class="bar series-neutral"')

    def test_customer_facing_limitations_and_confidence_matrix_are_korean(self):
        checked = "\n".join(
            [
                re.search(r'id="panel-limitations"[\s\S]*?</section>', self.html).group(0),
                self.chart_fragment("chart-confidence"),
                self.chart_fragment("chart-sku-comparison"),
            ]
        )
        banned = [
            "planned three repeats",
            "missing request-ID",
            "metadata-only baseline",
            "warmup contamination",
            "drop=0 versus",
            "stable threshold",
            "asymmetric v1/v2 metrics",
            "client p99 artifacts",
            "untested 1,000 RPS",
            "HTTP 200 can coexist",
            "was not collected라",
            "mechanism and SKU-only causality unproven",
        ]
        for phrase in banned:
            self.assertNotIn(phrase, checked)
        for phrase in ("반복 실행 부족", "요청 ID·해시 대조 누락", "메타데이터만 기록한 기준선", "v2 CPU/memory 미수집"):
            self.assertIn(phrase, checked)

    def test_confidence_matrix_source_line_is_not_mislabeled_as_confirmed(self):
        fragment = self.chart_fragment("chart-confidence")
        source = re.search(r'<p class="chart-source">(?P<body>[\s\S]*?)</p>', fragment).group("body")
        self.assertIn("확정/조건부/미검증/교정", self.text_without_tags(source))
        self.assertNotRegex(source, r'class="evidence')

    def test_latency_rows_match_all_json_results_with_sensible_precision(self):
        self.assertEqual(len(self.results), 19)
        table = re.search(
            r"<caption>Client latency values from all 19 result\.json files \(rounded to 2 decimals\)</caption>[\s\S]*?<tbody>(?P<body>[\s\S]*?)</tbody>",
            self.html,
        )
        self.assertIsNotNone(table)
        row_matches = re.findall(r"<tr>(?P<row>[\s\S]*?)</tr>", table.group("body"))
        rows = {}
        for row in row_matches:
            cells = re.findall(r"<td>(?P<cell>[\s\S]*?)</td>", row)
            text_cells = [self.text_without_tags(cell) for cell in cells]
            if text_cells:
                rows[text_cells[0]] = text_cells
        self.assertEqual(set(rows), set(self.results))
        for path, data in self.results.items():
            expected = [
                path,
                data["condition"],
                str(data["payloadBytes"]),
                str(data["rate"]),
                str(data["offered"]),
                str(data["successful"]),
                str(data["errors"]),
                f"{data['p50Ms']:.2f}",
                f"{data['p95Ms']:.2f}",
                f"{data['p99Ms']:.2f}",
            ]
            self.assertEqual(rows[path], expected)

    def test_no_raw_colors_outside_clawpilot_token_definitions(self):
        style = re.search(r"<style>(?P<style>[\s\S]*?)</style>", self.html).group("style")
        color_pattern = re.compile(r"#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(")
        offenders = [
            line.strip()
            for line in style.splitlines()
            if color_pattern.search(line) and "--cp-" not in line
        ]
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
