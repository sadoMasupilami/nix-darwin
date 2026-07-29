#!/usr/bin/env python3
"""Create Parakeet transcripts for completed Minutes WAV files.

The original Minutes Markdown remains untouched. Parakeet word timestamps are
aligned to the speaker timeline in that Markdown and written to deterministic
`.parakeet.md` and `.parakeet.json` sidecars next to the WAV file.
"""

from __future__ import annotations

import argparse
import bisect
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from typing import Any


SCHEMA_VERSION = 1
PIPELINE_VERSION = 1
MODEL_ID = "parakeet-tdt-0.6b-v3"
SPEAKER_LINE = re.compile(
    r"^\[(?P<label>.+?) (?P<minutes>\d+):(?P<seconds>\d{2})\]\s*(?P<text>.*)$"
)
SENTENCE_ENDINGS = (".", "!", "?", "…")


def file_fingerprint(path: Path | None) -> dict[str, Any] | None:
    if path is None or not path.is_file():
        return None
    stat = path.stat()
    return {
        "path": str(path.resolve()),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def parse_speaker_timeline(markdown_path: Path | None) -> list[dict[str, Any]]:
    if markdown_path is None or not markdown_path.is_file():
        return []

    timeline: list[dict[str, Any]] = []
    with markdown_path.open(encoding="utf-8") as handle:
        for line in handle:
            match = SPEAKER_LINE.match(line.rstrip("\n"))
            if not match:
                continue
            start = int(match.group("minutes")) * 60 + int(match.group("seconds"))
            timeline.append({"start": float(start), "speaker": match.group("label")})

    timeline.sort(key=lambda item: item["start"])
    return timeline


def parse_title(markdown_path: Path | None, fallback: str) -> str:
    if markdown_path is None or not markdown_path.is_file():
        return fallback

    in_frontmatter = False
    with markdown_path.open(encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if line == "---":
                if in_frontmatter:
                    break
                in_frontmatter = True
                continue
            if in_frontmatter and line.startswith("title:"):
                title = line.removeprefix("title:").strip().strip('"').strip("'")
                return title or fallback
    return fallback


def speaker_for_time(
    timestamp: float, timeline: list[dict[str, Any]], starts: list[float]
) -> str:
    if not timeline:
        return "UNKNOWN"
    index = bisect.bisect_right(starts, timestamp) - 1
    if index < 0:
        return timeline[0]["speaker"] if starts[0] <= 5.0 else "UNKNOWN"
    return timeline[index]["speaker"]


def merge_words_with_speakers(
    word_timings: list[dict[str, Any]], timeline: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    starts = [float(item["start"]) for item in timeline]
    assigned: list[dict[str, Any]] = []

    for timing in word_timings:
        word = str(timing.get("word", "")).strip()
        if not word:
            continue
        start = float(timing.get("startTime", 0.0))
        end = float(timing.get("endTime", start))
        assigned.append(
            {
                "word": word,
                "start": start,
                "end": end,
                "confidence": timing.get("confidence"),
                "speaker": speaker_for_time((start + end) / 2.0, timeline, starts),
            }
        )

    segments: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    previous_end: float | None = None

    for item in assigned:
        should_break = current is None
        if current is not None:
            gap = item["start"] - (previous_end if previous_end is not None else item["start"])
            sentence_complete = (
                current["words"][-1].endswith(SENTENCE_ENDINGS)
                and len(current["words"]) >= 16
                and current["end"] - current["start"] >= 4.0
            )
            should_break = (
                item["speaker"] != current["speaker"]
                or gap >= 1.25
                or sentence_complete
                or len(current["words"]) >= 42
            )

        if should_break:
            if current is not None:
                segments.append(finalize_segment(current))
            current = {
                "speaker": item["speaker"],
                "start": item["start"],
                "end": item["end"],
                "words": [item["word"]],
                "confidences": [item["confidence"]],
            }
        else:
            assert current is not None
            current["words"].append(item["word"])
            current["confidences"].append(item["confidence"])
            current["end"] = item["end"]
        previous_end = item["end"]

    if current is not None:
        segments.append(finalize_segment(current))
    return segments


def finalize_segment(segment: dict[str, Any]) -> dict[str, Any]:
    confidences = [
        float(value) for value in segment.pop("confidences") if value is not None
    ]
    words = segment.pop("words")
    segment["text"] = " ".join(words)
    segment["confidence"] = (
        sum(confidences) / len(confidences) if confidences else None
    )
    return segment


def format_timestamp(seconds: float) -> str:
    whole_seconds = max(0, int(seconds))
    return f"{whole_seconds // 60}:{whole_seconds % 60:02d}"


def render_markdown(
    *,
    title: str,
    wav_path: Path,
    source_markdown: Path | None,
    generated_at: str,
    segments: list[dict[str, Any]],
) -> str:
    diarization = "minutes-timestamp-alignment" if source_markdown else "none"
    lines = [
        "---",
        f"title: {json.dumps(title + ' - Parakeet v3', ensure_ascii=False)}",
        "type: transcript",
        f"source_audio: {json.dumps(str(wav_path.resolve()), ensure_ascii=False)}",
        f"engine: {json.dumps('fluidaudio/' + MODEL_ID)}",
        f"generated_at: {json.dumps(generated_at)}",
        f"diarization: {json.dumps(diarization)}",
    ]
    if source_markdown:
        lines.append(
            f"diarization_source: {json.dumps(str(source_markdown.resolve()), ensure_ascii=False)}"
        )
    lines.extend(["---", "", "## Transcript", ""])

    for segment in segments:
        lines.append(
            f"[{segment['speaker']} {format_timestamp(segment['start'])}] {segment['text']}"
        )
    lines.append("")
    return "\n".join(lines)


def is_current(
    json_path: Path,
    markdown_path: Path,
    source: dict[str, Any],
    diarization_source: dict[str, Any] | None,
) -> bool:
    if not json_path.is_file() or not markdown_path.is_file():
        return False
    try:
        with json_path.open(encoding="utf-8") as handle:
            existing = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return False
    pipeline = existing.get("pipeline", {})
    return (
        pipeline.get("version") == PIPELINE_VERSION
        and existing.get("source") == source
        and existing.get("diarization_source") == diarization_source
    )


def run_fluidaudio(
    *,
    fluidaudio: Path,
    model_dir: Path,
    wav_path: Path,
    temporary_dir: Path,
) -> dict[str, Any]:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="fluidaudio-", suffix=".json", dir=temporary_dir
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        command = [
            str(fluidaudio),
            "transcribe",
            str(wav_path),
            "--model-version",
            "v3",
            "--model-dir",
            str(model_dir),
            "--word-timestamps",
            "--output-json",
            str(temporary_path),
        ]
        completed = subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=1800,
            check=False,
        )
        if completed.returncode != 0:
            detail = completed.stderr.strip()[-2000:] or "no error output"
            raise RuntimeError(
                f"FluidAudio exited with {completed.returncode}: {detail}"
            )
        with temporary_path.open(encoding="utf-8") as handle:
            payload = json.load(handle)
        if not isinstance(payload.get("wordTimings"), list):
            raise RuntimeError("FluidAudio JSON contains no wordTimings array")
        return payload
    finally:
        temporary_path.unlink(missing_ok=True)


def process_wav(args: argparse.Namespace, wav_path: Path) -> str:
    wav_path = wav_path.resolve()
    source_markdown = wav_path.with_suffix(".md")
    if not source_markdown.is_file():
        source_markdown = None

    json_path = wav_path.with_suffix(".parakeet.json")
    markdown_path = wav_path.with_suffix(".parakeet.md")
    source = file_fingerprint(wav_path)
    assert source is not None
    diarization_source = file_fingerprint(source_markdown)

    if not args.force and is_current(
        json_path, markdown_path, source, diarization_source
    ):
        return "current"

    payload = run_fluidaudio(
        fluidaudio=args.fluidaudio,
        model_dir=args.model_dir,
        wav_path=wav_path,
        temporary_dir=args.state_dir,
    )
    timeline = parse_speaker_timeline(source_markdown)
    segments = merge_words_with_speakers(payload["wordTimings"], timeline)
    if not segments:
        raise RuntimeError("Parakeet returned no transcript segments")

    generated_at = dt.datetime.now(dt.timezone.utc).isoformat()
    title = parse_title(source_markdown, wav_path.stem.replace("-", " ").title())
    result = {
        "schema_version": SCHEMA_VERSION,
        "pipeline": {
            "name": "minutes-parakeet-postprocess",
            "version": PIPELINE_VERSION,
            "engine": f"fluidaudio/{MODEL_ID}",
            "generated_at": generated_at,
        },
        "source": source,
        "diarization_source": diarization_source,
        "asr": payload,
        "segments": segments,
    }
    markdown = render_markdown(
        title=title,
        wav_path=wav_path,
        source_markdown=source_markdown,
        generated_at=generated_at,
        segments=segments,
    )

    atomic_write_text(
        json_path, json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    )
    atomic_write_text(markdown_path, markdown)
    return "processed"


def discover_wavs(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    result = []
    for path in root.rglob("*.wav"):
        relative_parts = path.relative_to(root).parts
        if any(part.startswith(".") for part in relative_parts):
            continue
        if path.is_file():
            result.append(path)
    return sorted(result)


def acquire_lock(state_dir: Path) -> Any | None:
    state_dir.mkdir(parents=True, exist_ok=True)
    lock_handle = (state_dir / "postprocess.lock").open("w", encoding="utf-8")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_handle.close()
        return None
    lock_handle.write(f"{os.getpid()}\n")
    lock_handle.flush()
    return lock_handle


def parse_args() -> argparse.Namespace:
    home = Path.home()
    parser = argparse.ArgumentParser(
        description="Create Parakeet v3 sidecar transcripts for Minutes WAV files"
    )
    parser.add_argument("--root", type=Path, default=home / "meetings")
    parser.add_argument("--file", type=Path)
    parser.add_argument("--fluidaudio", type=Path, required=True)
    parser.add_argument(
        "--model-dir",
        type=Path,
        default=home
        / "Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3",
    )
    parser.add_argument(
        "--state-dir", type=Path, default=home / ".minutes/parakeet-postprocess"
    )
    parser.add_argument("--settle-seconds", type=int, default=30)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.fluidaudio = args.fluidaudio.resolve()
    args.model_dir = args.model_dir.expanduser().resolve()
    args.state_dir = args.state_dir.expanduser().resolve()

    if not args.fluidaudio.is_file():
        print(f"FluidAudio binary not found: {args.fluidaudio}", file=sys.stderr)
        return 2
    if not args.model_dir.is_dir():
        print(
            "Parakeet v3 model is not installed. Run one explicit "
            "`fluidaudio transcribe <wav> --model-version v3` first. "
            f"Expected: {args.model_dir}",
            file=sys.stderr,
        )
        return 2

    lock_handle = acquire_lock(args.state_dir)
    if lock_handle is None:
        if args.verbose:
            print("another postprocessor instance is already running")
        return 0

    try:
        candidates = [args.file.expanduser()] if args.file else discover_wavs(args.root)
        failures = 0
        for wav_path in candidates:
            if not wav_path.is_file():
                print(f"missing WAV: {wav_path}", file=sys.stderr)
                failures += 1
                continue
            age = time.time() - wav_path.stat().st_mtime
            if not args.force and age < args.settle_seconds:
                if args.verbose:
                    print(f"waiting for stable WAV: {wav_path}")
                continue
            try:
                outcome = process_wav(args, wav_path)
                if outcome == "processed":
                    print(f"processed: {wav_path}")
                elif args.verbose:
                    print(f"up to date: {wav_path}")
            except Exception as error:  # keep one bad meeting from blocking others
                print(f"failed: {wav_path}: {error}", file=sys.stderr)
                failures += 1
        return 1 if failures else 0
    finally:
        lock_handle.close()


if __name__ == "__main__":
    raise SystemExit(main())
