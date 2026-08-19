#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import stat
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "config"
    / "qwen-meeting"
    / "runtime"
    / "fetch-models.py"
)
SPEC = importlib.util.spec_from_file_location("qwen_fetch_models", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FetchModelTests(unittest.TestCase):
    def test_revisions_are_exact(self) -> None:
        revisions = {model.name: model.revision for model in MODULE.MODELS}
        self.assertEqual(
            revisions["asr"], "7278e1e70fe206f11671096ffdd38061171dd6e5"
        )
        self.assertEqual(
            revisions["aligner"], "c7cbfc2048c462b0d63a45797104fc9db3ad62b7"
        )

    def test_validation_rejects_a_different_snapshot_revision(self) -> None:
        model = MODULE.MODELS[0]
        with tempfile.TemporaryDirectory() as directory:
            snapshot = Path(directory) / ("0" * 40)
            snapshot.mkdir()
            (snapshot / "config.json").write_text("{}", encoding="utf-8")
            (snapshot / "model.safetensors").write_bytes(b"weights")
            with self.assertRaisesRegex(RuntimeError, "Unexpected revision"):
                MODULE.validate_snapshot(snapshot, model)

    def test_activation_refuses_non_symlink_targets(self) -> None:
        model = MODULE.MODELS[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            models = root / "models"
            models.mkdir()
            (models / model.name).mkdir()
            with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
                MODULE.activate_snapshot(models, model, root / model.revision)

    def test_existing_insecure_state_directory_is_rejected_not_changed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir(mode=0o755)
            state.chmod(0o755)
            with self.assertRaisesRegex(RuntimeError, "not private"):
                MODULE.private_directory(state)
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o755)


if __name__ == "__main__":
    unittest.main()
