#!/usr/bin/env python3
"""Regression tests for sync_all_docs.py's symbol-resolution heuristics."""

import importlib.util
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("sync_all_docs", TOOLS_DIR / "sync_all_docs.py")
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)

CHECK_SPEC = importlib.util.spec_from_file_location("check_doc_refs", TOOLS_DIR / "check_doc_refs.py")
CHECK = importlib.util.module_from_spec(CHECK_SPEC)
CHECK_SPEC.loader.exec_module(CHECK)


class SyncAllDocsTests(unittest.TestCase):
    def test_signature_wins_over_inline_description_code(self):
        line = (
            "  - `YapperAPI:GetRegisteredSettingsCategories() → table[]`: "
            "Get non-internal categories as `{id, label}` tables. "
            "([`../Src/API.lua#L1326`](../Src/API.lua#L1326))"
        )
        name, receiver, confident = SYNC.extract_link_identifier(line, line.index("(["))
        self.assertEqual(name, "GetRegisteredSettingsCategories")
        self.assertEqual(receiver, "YapperAPI")
        self.assertTrue(confident)

    def test_signature_wins_over_inline_or_expression(self):
        line = (
            "  - `Utils:SafeNumber(value, fallback) → number`: "
            "Convenience wrapper around SanitizeNumber; values may pass `or 0`. "
            "([`../Src/Utils.lua#L243`](../Src/Utils.lua#L243))"
        )
        name, receiver, confident = SYNC.extract_link_identifier(line, line.index("(["))
        self.assertEqual(name, "SafeNumber")
        self.assertEqual(receiver, "Utils")
        self.assertTrue(confident)

    def test_checker_uses_signature_over_inline_description_tokens(self):
        line = (
            "  - `YapperTable.InstallCompatMethods(box) → nil`: "
            "Supports `GetAttribute` and `GetChatType`. "
            "([`../Src/EditBoxCompat.lua#L32`](../Src/EditBoxCompat.lua#L32))"
        )
        name, receiver, confident = CHECK.extract_identifier(line, line.index("(["))
        self.assertEqual(name, "InstallCompatMethods")
        self.assertEqual(receiver, "YapperTable")
        self.assertTrue(confident)

    def test_definition_search_does_not_match_arbitrary_words(self):
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as handle:
            handle.write("local value = x or 0\n")
            handle.write("function Utils:SanitizeNumber(value)\n")
            handle.write("    return value\n")
            handle.write("end\n")
            path = Path(handle.name)
        try:
            self.assertEqual(SYNC.find_definition_lines(path, "or"), [])
            self.assertEqual(SYNC.find_definition_lines(path, "SanitizeNumber"), [2])
        finally:
            path.unlink()

    def test_ambiguous_definitions_are_not_auto_selected(self):
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as handle:
            handle.write("function First:Refresh() end\n")
            handle.write("function Second:Refresh() end\n")
            path = Path(handle.name)
        try:
            self.assertEqual(SYNC.find_definition_lines(path, "Refresh"), [1, 2])
            self.assertIsNone(SYNC.find_unique_definition_line(path, "Refresh"))
        finally:
            path.unlink()

    def test_bridge_module_alias_is_documented_by_module_name(self):
        aliases = SYNC.documentation_table_names(
            "Bridges/TypingTrackerBridge.lua", "Bridge"
        )
        self.assertIn("Bridge", aliases)
        self.assertIn("TypingTrackerBridge", aliases)
        self.assertEqual(
            SYNC.documentation_table_name("Bridges/TypingTrackerBridge.lua", "Bridge"),
            "TypingTrackerBridge",
        )


if __name__ == "__main__":
    unittest.main()
