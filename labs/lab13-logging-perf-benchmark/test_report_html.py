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


if __name__ == "__main__":
    unittest.main()
