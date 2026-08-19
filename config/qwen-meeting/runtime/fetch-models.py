#!/usr/bin/env python3
"""Download the exact Qwen meeting models and activate local-only paths."""

from __future__ import annotations

import argparse
import os
import stat
from dataclasses import dataclass
from pathlib import Path


ALLOW_PATTERNS = ("*.json", "*.safetensors", "*.txt", "*.model")


@dataclass(frozen=True)
class ModelSpec:
    name: str
    repo_id: str
    revision: str


MODELS = (
    ModelSpec(
        name="asr",
        repo_id="Qwen/Qwen3-ASR-1.7B",
        revision="7278e1e70fe206f11671096ffdd38061171dd6e5",
    ),
    ModelSpec(
        name="aligner",
        repo_id="Qwen/Qwen3-ForcedAligner-0.6B",
        revision="c7cbfc2048c462b0d63a45797104fc9db3ad62b7",
    ),
)


def private_directory(path: Path) -> None:
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        raise RuntimeError(f"Refusing unsafe state path: {path}")
    if path.exists():
        if stat.S_IMODE(path.stat().st_mode) != 0o700:
            raise RuntimeError(
                f"Existing state directory is not private (expected mode 700): {path}"
            )
        return
    path.mkdir(mode=0o700, parents=True)
    if stat.S_IMODE(path.stat().st_mode) != 0o700:
        raise RuntimeError(f"Could not create private state directory: {path}")


def validate_snapshot(path: Path, spec: ModelSpec) -> Path:
    resolved = path.resolve(strict=True)
    if resolved.name != spec.revision:
        raise RuntimeError(
            f"Unexpected revision for {spec.repo_id}: {resolved.name}; "
            f"expected {spec.revision}"
        )
    if not (resolved / "config.json").is_file():
        raise RuntimeError(f"Downloaded snapshot has no config.json: {resolved}")
    if not any(resolved.glob("*.safetensors")):
        raise RuntimeError(f"Downloaded snapshot has no safetensors weights: {resolved}")
    return resolved


def activate_snapshot(models_dir: Path, spec: ModelSpec, snapshot: Path) -> None:
    link = models_dir / spec.name
    if os.path.lexists(link) and not link.is_symlink():
        raise RuntimeError(f"Refusing to replace non-symlink model path: {link}")

    temporary = models_dir / f".{spec.name}.{os.getpid()}.tmp"
    if os.path.lexists(temporary):
        temporary.unlink()

    try:
        temporary.symlink_to(snapshot, target_is_directory=True)
        temporary.replace(link)
    finally:
        if os.path.lexists(temporary):
            temporary.unlink()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download revision-pinned Qwen meeting models."
    )
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Use only already cached snapshots and never access the network.",
    )
    return parser.parse_args()


def main() -> int:
    os.umask(0o077)
    args = parse_args()
    state_dir = args.state_dir.expanduser().resolve()
    cache_dir = state_dir / "huggingface" / "hub"
    models_dir = state_dir / "models"

    private_directory(state_dir)
    private_directory(cache_dir)
    private_directory(models_dir)

    from huggingface_hub import snapshot_download

    for spec in MODELS:
        print(f"Lade {spec.repo_id} bei Revision {spec.revision} ...")
        downloaded = snapshot_download(
            repo_id=spec.repo_id,
            revision=spec.revision,
            cache_dir=cache_dir,
            allow_patterns=list(ALLOW_PATTERNS),
            local_files_only=args.offline,
        )
        snapshot = validate_snapshot(Path(downloaded), spec)
        activate_snapshot(models_dir, spec, snapshot)

    print(f"Modelle sind revisionsfest unter {models_dir} aktiviert.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
