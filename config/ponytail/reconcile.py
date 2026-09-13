"""Merge Ponytail's managed entries without owning either client's settings."""

import json
import os
import stat
import sys
import tempfile
from pathlib import Path

import tomlkit


def read(path):
    if path.is_symlink():
        raise ValueError(f"Refusing to replace symlinked settings: {path}")
    return path.read_text() if path.exists() else ""


def write(path, old, new):
    if old == new:
        return
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(new)
        if read(path) != old:
            raise ValueError(f"Settings changed during activation: {path}")
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def reconcile(home, marketplace):
    codex_path = home / ".codex/config.toml"
    claude_path = home / ".claude/settings.json"
    codex_old, claude_old = read(codex_path), read(claude_path)
    # Validate both documents before changing either one.
    codex = tomlkit.parse(codex_old)
    claude = json.loads(claude_old) if claude_old else {}
    codex.setdefault("features", {})["plugins"] = True
    entry = codex.setdefault("marketplaces", {}).setdefault("nix-ponytail", {})
    entry["source_type"] = "local"
    entry["source"] = marketplace
    codex.setdefault("plugins", {}).setdefault("ponytail@nix-ponytail", {})["enabled"] = True
    claude.setdefault("enabledPlugins", {})["ponytail@skills-dir"] = True
    codex_new = tomlkit.dumps(codex)
    claude_new = (
        claude_old
        if claude_old and json.loads(claude_old) == claude
        else json.dumps(claude, indent=2, ensure_ascii=False) + "\n"
    )
    write(codex_path, codex_old, codex_new)
    write(claude_path, claude_old, claude_new)


if __name__ == "__main__":
    try:
        reconcile(Path(sys.argv[1]), sys.argv[2])
    except (ValueError, TypeError, KeyError, AttributeError, OSError):
        # Parser exceptions can contain configuration values. Keep them private.
        sys.exit("Ponytail activation failed: check settings syntax, ownership, and concurrent edits.")
