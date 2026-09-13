"""Exercise the installed hooks with private state and no Node.js on PATH."""

import json
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

plugin, expected_version = Path(sys.argv[1]), sys.argv[2]
hooks = json.loads((plugin / "hooks/claude-codex-hooks.json").read_text())["hooks"]
versions = [json.loads((plugin / client / "plugin.json").read_text())["version"]
            for client in (".claude-plugin", ".codex-plugin")]
assert versions == [expected_version, expected_version], versions
with tempfile.TemporaryDirectory(prefix="ponytail-runtime-") as tmp:
    root = Path(tmp)
    for client in ("claude", "codex"):
        env = {
            "PATH": "/nonexistent",
            "CLAUDE_CONFIG_DIR": str(root / client),
            "XDG_CONFIG_HOME": str(root / "config"),
            "PONYTAIL_DEFAULT_MODE": "full",
        }
        if client == "codex":
            env["PLUGIN_DATA"] = str(root / "codex-state")
        for event in ("SessionStart", "SubagentStart", "UserPromptSubmit"):
            command = hooks[event][0]["hooks"][0]["command"]
            result = subprocess.run(
                shlex.split(command),
                input=json.dumps({"prompt": "hello", "agent_type": "general-purpose"}),
                env=env, capture_output=True, text=True, timeout=10,
            )
            assert result.returncode == 0, (client, event, result.stderr)
            if event == "SessionStart":
                assert "YAGNI" in result.stdout
                if client == "codex":
                    assert json.loads(result.stdout)["systemMessage"] == "PONYTAIL:FULL"
            if event == "SubagentStart":
                assert "YAGNI" in json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        state = root / ("codex-state" if client == "codex" else client) / ".ponytail-active"
        assert state.read_text() == "full"
        command = hooks["UserPromptSubmit"][0]["hooks"][0]["command"]
        subprocess.run(shlex.split(command), input='{"prompt":"/ponytail off"}',
                       env=env, capture_output=True, text=True, check=True, timeout=10)
        assert not state.exists() or state.read_text() == "off"
print("Packaged hooks passed for Claude and Codex without Node.js on PATH.")
