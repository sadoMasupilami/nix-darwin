"""Bind upstream hooks to the immutable plugin and Node.js paths."""

import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
node, upstream_version, version = sys.argv[2:5]
for client in (".claude-plugin", ".codex-plugin"):
    manifest_path = root / client / "plugin.json"
    manifest = json.loads(manifest_path.read_text())
    if manifest["version"] != upstream_version:
        raise ValueError("Upstream version changed; review the package before updating")
    manifest["version"] = version
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
path = root / "hooks/claude-codex-hooks.json"
data = json.loads(path.read_text())
count = 0
for groups in data["hooks"].values():
    for group in groups:
        for hook in group["hooks"]:
            command = hook["command"]
            if hook["type"] != "command" or not command.startswith('node "${CLAUDE_PLUGIN_ROOT}/hooks/'):
                raise ValueError("Unexpected upstream hook; review the runtime patch")
            hook["command"] = command.replace("node ", f"{node} ", 1).replace(
                "${CLAUDE_PLUGIN_ROOT}", str(root)
            )
            count += 1
if count != 3:
    raise ValueError("Upstream hook inventory changed; review before updating")
path.write_text(json.dumps(data, indent=2) + "\n")
