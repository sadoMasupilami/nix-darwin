"""Activation tests use temporary settings only; no client is launched."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

import tomlkit

spec = importlib.util.spec_from_file_location(
    "reconcile", Path(__file__).resolve().parents[1] / "config/ponytail/reconcile.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PonytailTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.codex = self.home / ".codex/config.toml"
        self.claude = self.home / ".claude/settings.json"
        self.codex.parent.mkdir()
        self.claude.parent.mkdir()

    def apply(self, source="/nix/store/example-marketplace"):
        module.reconcile(self.home, source)

    def test_preserves_settings_comments_and_is_idempotent(self):
        self.codex.write_text('# keep this comment\nmodel = "custom"\n[plugins."other@market"]\nenabled = false\n')
        self.codex.chmod(0o600)
        self.claude.write_text(json.dumps({"permissions": {"deny": ["Read(.env)"]}, "enabledPlugins": {"other@market": False}}))
        self.apply()
        config = tomlkit.parse(self.codex.read_text())
        self.assertEqual(config["model"], "custom")
        self.assertFalse(config["plugins"]["other@market"]["enabled"])
        self.assertTrue(config["plugins"]["ponytail@nix-ponytail"]["enabled"])
        self.assertIn("# keep this comment", self.codex.read_text())
        claude = json.loads(self.claude.read_text())
        self.assertEqual(claude["permissions"]["deny"], ["Read(.env)"])
        self.assertFalse(claude["enabledPlugins"]["other@market"])
        self.assertTrue(claude["enabledPlugins"]["ponytail@skills-dir"])
        before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in (self.codex, self.claude)]
        self.apply()
        self.assertEqual(before, [(p.read_bytes(), p.stat().st_mtime_ns) for p in (self.codex, self.claude)])
        self.assertEqual(self.codex.stat().st_mode & 0o777, 0o600)

    def test_fresh_install_and_rollback(self):
        self.apply("/nix/store/old")
        self.apply("/nix/store/new")
        self.apply("/nix/store/old")
        self.assertEqual(tomlkit.parse(self.codex.read_text())["marketplaces"]["nix-ponytail"]["source"], "/nix/store/old")
        self.assertEqual(self.claude.stat().st_mode & 0o777, 0o600)

    def test_invalid_claude_leaves_codex_unchanged(self):
        self.codex.write_text('model = "custom"\n')
        self.claude.write_text("{invalid")
        with self.assertRaises(ValueError):
            self.apply()
        self.assertEqual(self.codex.read_text(), 'model = "custom"\n')

    def test_invalid_codex_leaves_claude_unchanged(self):
        self.codex.write_text("[invalid")
        self.claude.write_text("{}")
        with self.assertRaises(Exception):
            self.apply()
        self.assertEqual(self.claude.read_text(), "{}")

    def test_symlinked_settings_are_not_replaced(self):
        target = self.home / "managed.toml"
        target.write_text("# managed elsewhere\n")
        self.codex.symlink_to(target)
        with self.assertRaises(ValueError):
            self.apply()
        self.assertTrue(self.codex.is_symlink())
        self.assertEqual(target.read_text(), "# managed elsewhere\n")
        self.assertFalse(self.claude.exists())


if __name__ == "__main__":
    unittest.main()
