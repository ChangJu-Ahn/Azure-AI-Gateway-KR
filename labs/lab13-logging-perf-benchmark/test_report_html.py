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


if __name__ == "__main__":
    unittest.main()
