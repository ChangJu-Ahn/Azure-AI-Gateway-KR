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
    "미검증",
    "교정",
]


class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.tabs = []
        self.external_assets = []

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


class ReportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = REPORT.read_text(encoding="utf-8")
        cls.parser = ReportParser()
        cls.parser.feed(cls.html)

    def test_has_required_tabs_and_panels(self):
        self.assertEqual(
            [tab["data-tab"] for tab in self.parser.tabs],
            TAB_IDS,
        )
        for tab_id in TAB_IDS:
            self.assertIn(f"panel-{tab_id}", self.parser.ids)

    def test_is_self_contained(self):
        self.assertEqual(self.parser.external_assets, [])
        self.assertNotRegex(self.html, r"\bfetch\s*\(")

    def test_references_all_source_documents(self):
        for source in SOURCE_DOCS:
            self.assertIn(source, self.html)

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
        for required in ("confirmed", "conditional", "drops/risks", "unverified"):
            self.assertIn(required, legend)
        for banned in ("planned", "reconciled", "pending"):
            self.assertNotIn(banned, legend)

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
        self.assertIn("text-anchor: end;", match.group("body"))

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

    def test_does_not_invent_exact_500_rps_e8_drop_count(self):
        self.assertIn("정확한 드롭률 미확정", self.html)
        self.assertNotRegex(
            self.html,
            r'data-run="real-E8"[^>]*data-drop-count="\d+"',
        )


if __name__ == "__main__":
    unittest.main()
