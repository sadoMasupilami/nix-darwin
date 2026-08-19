#!/usr/bin/env python3

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
QWEN = REPO_ROOT / "config" / "qwen-meeting" / "qwen-meeting"
QWEN_SETUP = REPO_ROOT / "config" / "qwen-meeting" / "qwen-meeting-setup"
TEAMS = REPO_ROOT / "config" / "raycast" / "teams-video-call.sh"
LOCAL_PRIVATE_TOOLS_MODULE = REPO_ROOT / "modules" / "local-private-tools.nix"


def write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o700)


def run_command(command: list[str], environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )


class QwenWrapperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="qwen-meeting-test.")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.config_home = self.home / ".config"
        self.state = self.home / ".local" / "state" / "qwen-meeting"
        self.output = self.home / "transcripts"
        self.asr = self.root / "fake-asr"
        self.open_command = self.root / "fake-open"
        self.copy_command = self.root / "fake-copy"
        self.asr_args = self.root / "asr-args"
        self.asr_environment = self.root / "asr-environment"
        self.open_args = self.root / "open-args"
        self.copied = self.root / "copied"
        self.audio = self.home / "meeting with spaces.wav"

        for directory in (
            self.config_home / "qwen-meeting",
            self.state,
            self.state / "models",
            self.state / "models" / "asr",
            self.state / "models" / "aligner",
        ):
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            directory.chmod(0o700)
        (self.state / "models" / "asr" / "config.json").write_text("{}")
        (self.state / "models" / "aligner" / "config.json").write_text("{}")
        (self.config_home / "qwen-meeting" / "context.txt").write_text("Kubernetes\n")
        self.audio.write_bytes(b"audio")

        write_executable(
            self.asr,
            """#!/usr/bin/env bash
set -euo pipefail
: > "$ASR_ARGS_FILE"
for argument in "$@"; do printf '%s\\n' "$argument" >> "$ASR_ARGS_FILE"; done
printf '%s\\n' "${HF_HUB_OFFLINE:-}" "${HF_HUB_DISABLE_TELEMETRY:-}" > "$ASR_ENV_FILE"
input="$1"
output=""
while (( $# > 0 )); do
  if [[ "$1" == "-o" ]]; then output="$2"; shift 2; continue; fi
  shift
done
stem="$(basename "${input%.*}")"
printf 'private transcript\\n' > "$output/$stem.txt"
printf '{}\\n' > "$output/$stem.json"
""",
        )
        write_executable(
            self.open_command,
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > \"$OPEN_ARGS_FILE\"\n",
        )
        write_executable(
            self.copy_command,
            "#!/usr/bin/env bash\ncat > \"$COPY_FILE\"\n",
        )

        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.home / ".local" / "state"),
                "QWEN_MEETING_STATE_HOME": str(self.state),
                "QWEN_MEETING_OUTPUT_ROOT": str(self.output),
                "QWEN_MEETING_ASR": str(self.asr),
                "QWEN_MEETING_OPEN_CMD": str(self.open_command),
                "QWEN_MEETING_COPY_CMD": str(self.copy_command),
                "ASR_ARGS_FILE": str(self.asr_args),
                "ASR_ENV_FILE": str(self.asr_environment),
                "OPEN_ARGS_FILE": str(self.open_args),
                "COPY_FILE": str(self.copied),
            }
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_wrapper(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return run_command(["/bin/zsh", str(QWEN), *arguments], self.environment)

    def test_default_is_offline_quiet_private_opens_and_does_not_copy(self) -> None:
        result = self.run_wrapper(str(self.audio))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.copied.exists())
        self.assertTrue(self.open_args.is_file())

        arguments = self.asr_args.read_text().splitlines()
        self.assertEqual(arguments[0], str(self.audio))
        self.assertIn("--quiet", arguments)
        self.assertNotIn("--verbose", arguments)
        self.assertEqual(
            arguments[arguments.index("--model") + 1],
            str((self.state / "models" / "asr").resolve()),
        )
        self.assertEqual(
            arguments[arguments.index("--forced-aligner") + 1],
            str((self.state / "models" / "aligner").resolve()),
        )
        self.assertEqual(self.asr_environment.read_text().splitlines(), ["1", "1"])

        output_directory = Path(self.open_args.read_text().strip())
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(output_directory.stat().st_mode), 0o700)
        transcript = output_directory / "meeting with spaces.txt"
        self.assertEqual(stat.S_IMODE(transcript.stat().st_mode), 0o600)
        self.assertNotIn("private transcript", result.stdout + result.stderr)

    def test_copy_is_opt_in_and_no_open_suppresses_finder(self) -> None:
        result = self.run_wrapper("--copy", "--no-open", str(self.audio), "de")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.open_args.exists())
        self.assertEqual(self.copied.read_text(), "private transcript\n")
        arguments = self.asr_args.read_text().splitlines()
        self.assertEqual(arguments[arguments.index("--language") + 1], "German")

    def test_remote_model_override_is_rejected_before_asr(self) -> None:
        self.environment["QWEN_MEETING_MODEL"] = "Qwen/Qwen3-ASR-1.7B"
        result = self.run_wrapper("--no-open", str(self.audio))
        self.assertEqual(result.returncode, 4)
        self.assertIn("Remote-Modellnamen sind nicht erlaubt", result.stderr)
        self.assertFalse(self.asr_args.exists())

    def test_existing_local_model_overrides_are_accepted(self) -> None:
        custom_asr = self.root / "custom-asr"
        custom_aligner = self.root / "custom-aligner"
        custom_asr.mkdir()
        custom_aligner.mkdir()
        (custom_asr / "config.json").write_text("{}")
        (custom_aligner / "config.json").write_text("{}")
        self.environment["QWEN_MEETING_MODEL"] = str(custom_asr)
        self.environment["QWEN_MEETING_ALIGNER"] = str(custom_aligner)

        result = self.run_wrapper("--no-open", str(self.audio), "en")
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.asr_args.read_text().splitlines()
        self.assertEqual(
            arguments[arguments.index("--model") + 1], str(custom_asr.resolve())
        )
        self.assertEqual(
            arguments[arguments.index("--forced-aligner") + 1],
            str(custom_aligner.resolve()),
        )
        self.assertEqual(arguments[arguments.index("--language") + 1], "English")

    def test_existing_insecure_output_root_is_rejected_not_changed(self) -> None:
        self.output.mkdir(mode=0o755)
        self.output.chmod(0o755)
        result = self.run_wrapper(str(self.audio))
        self.assertEqual(result.returncode, 6)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o755)
        self.assertIn("chmod 700", result.stderr)
        self.assertFalse(self.asr_args.exists())

    def test_existing_insecure_state_root_is_rejected_not_changed(self) -> None:
        self.state.chmod(0o755)
        result = self.run_wrapper(str(self.audio))
        self.assertEqual(result.returncode, 4)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o755)
        self.assertIn("chmod 700", result.stderr)
        self.assertFalse(self.asr_args.exists())

    def test_failed_asr_does_not_copy_or_open(self) -> None:
        write_executable(self.asr, "#!/usr/bin/env bash\nexit 42\n")
        result = self.run_wrapper("--copy", str(self.audio))
        self.assertEqual(result.returncode, 42)
        self.assertFalse(self.copied.exists())
        self.assertFalse(self.open_args.exists())


class QwenSetupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="qwen-setup-test.")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.runtime = self.home / "runtime"
        self.venv = self.home / ".venvs" / "qwen3-asr"
        self.state = self.home / "state"
        self.fake_uv = self.root / "fake-uv"
        self.uv_args = self.root / "uv-args"
        self.fetch_args = self.root / "fetch-args"
        self.runtime.mkdir(parents=True)
        for filename in ("pyproject.toml", "uv.lock", "fetch-models.py"):
            (self.runtime / filename).touch()

        write_executable(
            self.fake_uv,
            """#!/usr/bin/env bash
set -euo pipefail
printf 'UV_PROJECT_ENVIRONMENT=%s\\n' "${UV_PROJECT_ENVIRONMENT:-}" > "$UV_ARGS_FILE"
for argument in "$@"; do printf '%s\\n' "$argument" >> "$UV_ARGS_FILE"; done
mkdir -p "$UV_PROJECT_ENVIRONMENT/bin"
cat > "$UV_PROJECT_ENVIRONMENT/bin/python" <<'PYTHON'
#!/usr/bin/env bash
printf '%s\\n' "$@" > "${FETCH_ARGS_FILE:?}"
PYTHON
cat > "$UV_PROJECT_ENVIRONMENT/bin/mlx-qwen3-asr" <<'ASR'
#!/usr/bin/env bash
[[ "$1" == "--doctor" ]]
ASR
chmod 700 "$UV_PROJECT_ENVIRONMENT/bin/python" "$UV_PROJECT_ENVIRONMENT/bin/mlx-qwen3-asr"
""",
        )
        python = shutil.which("python3.13")
        if python is None:
            self.fail("python3.13 is required for the setup tests")
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.home),
                "QWEN_MEETING_VENV": str(self.venv),
                "QWEN_MEETING_RUNTIME": str(self.runtime),
                "QWEN_MEETING_STATE_HOME": str(self.state),
                "QWEN_MEETING_UV": str(self.fake_uv),
                "QWEN_MEETING_PYTHON": python,
                "UV_ARGS_FILE": str(self.uv_args),
                "FETCH_ARGS_FILE": str(self.fetch_args),
            }
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_setup(self) -> subprocess.CompletedProcess[str]:
        return run_command(["/bin/zsh", str(QWEN_SETUP)], self.environment)

    def test_setup_uses_locked_sync_without_activation_or_python_downloads(self) -> None:
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.uv_args.read_text().splitlines()
        self.assertEqual(arguments[0], f"UV_PROJECT_ENVIRONMENT={self.venv}")
        for required in (
            "sync",
            "--locked",
            "--no-dev",
            "--no-install-project",
            "--no-managed-python",
            "--no-python-downloads",
        ):
            self.assertIn(required, arguments)
        fetch_arguments = self.fetch_args.read_text().splitlines()
        self.assertIn(str(self.runtime / "fetch-models.py"), fetch_arguments)
        self.assertEqual(
            fetch_arguments[fetch_arguments.index("--state-dir") + 1], str(self.state)
        )
        self.assertEqual(stat.S_IMODE(self.venv.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)

    def test_setup_refuses_non_venv_collision_without_modifying_it(self) -> None:
        self.venv.mkdir(parents=True)
        sentinel = self.venv / "sentinel"
        sentinel.write_text("keep\n")
        result = self.run_setup()
        self.assertEqual(result.returncode, 5)
        self.assertEqual(sentinel.read_text(), "keep\n")
        self.assertFalse(self.uv_args.exists())

    def test_setup_rejects_insecure_existing_venv_without_chmod(self) -> None:
        self.venv.mkdir(parents=True)
        (self.venv / "pyvenv.cfg").write_text("home = test\n")
        self.venv.chmod(0o755)
        result = self.run_setup()
        self.assertEqual(result.returncode, 5)
        self.assertEqual(stat.S_IMODE(self.venv.stat().st_mode), 0o755)
        self.assertFalse(self.uv_args.exists())

    def test_setup_rejects_insecure_existing_state_without_chmod(self) -> None:
        self.state.mkdir(parents=True)
        self.state.chmod(0o755)
        result = self.run_setup()
        self.assertEqual(result.returncode, 5)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o755)
        self.assertFalse(self.uv_args.exists())


class TeamsPickerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="teams-call-test.")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.csv = self.home / ".config" / "raycast" / "teams-people.csv"
        self.csv.parent.mkdir(mode=0o700, parents=True)
        self.osascript = self.root / "fake-osascript"
        self.osascript_args = self.root / "osascript-args"
        self.state = self.home / ".local" / "state" / "raycast-teams-call"
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.home),
                "TEAMS_PEOPLE_CSV": str(self.csv),
                "TEAMS_CALL_DRY_RUN": "1",
                "TEAMS_CALL_OSASCRIPT_CMD": str(self.osascript),
                "TEAMS_CALL_STATE_DIR": str(self.state),
                "OSASCRIPT_ARGS": str(self.osascript_args),
            }
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_picker(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return run_command(["/bin/bash", str(TEAMS), *arguments], self.environment)

    def write_contacts(self, content: str, mode: int = 0o600) -> None:
        self.csv.write_text(content, encoding="utf-8")
        self.csv.chmod(mode)

    def test_single_contact_discloses_no_email_tenant_or_deep_link(self) -> None:
        self.write_contacts("Private Name,private@example.test,secret-tenant\n")
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Teams-Videoanruf würde geöffnet", result.stdout)
        for secret in ("private@example.test", "secret-tenant", "msteams://"):
            self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertNotIn(
            "/tmp/raycast-teams-video-call.log", TEAMS.read_text(encoding="utf-8")
        )
        self.assertEqual(self.state.joinpath("status").read_text(), "Anruf gestartet\n")
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.state.joinpath("status").stat().st_mode), 0o600)
        self.assertEqual(len(self.state.joinpath("status").read_text().splitlines()), 1)
        for secret in ("private@example.test", "secret-tenant", "msteams://"):
            self.assertNotIn(secret, self.state.joinpath("status").read_text())

    def test_group_accessible_contact_file_is_rejected(self) -> None:
        self.write_contacts("Private Name,private@example.test,secret-tenant\n", 0o640)
        result = self.run_picker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("chmod 600", result.stderr)
        self.assertNotIn(str(self.root), result.stdout + result.stderr)
        self.assertNotIn("private@example.test", result.stdout + result.stderr)
        self.assertEqual(self.state.joinpath("status").read_text(), "Fehler\n")

    def test_noncanonical_owner_only_contact_modes_are_rejected(self) -> None:
        for mode in (0o400, 0o700):
            with self.subTest(mode=oct(mode)):
                self.csv.unlink(missing_ok=True)
                self.write_contacts(
                    "Private Name,private@example.test,secret-tenant\n", mode
                )
                result = self.run_picker()
                self.assertEqual(result.returncode, 1)
                self.assertIn("Modus 600", result.stderr)
                self.assertEqual(stat.S_IMODE(self.csv.stat().st_mode), mode)
                self.assertNotIn("private@example.test", result.stdout + result.stderr)

    def test_symlink_contact_file_is_rejected(self) -> None:
        contacts = self.root / "contacts.csv"
        contacts.write_text("Private Name,private@example.test,secret-tenant\n")
        contacts.chmod(0o600)
        self.csv.symlink_to(contacts)
        result = self.run_picker()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("private@example.test", result.stdout + result.stderr)
        self.assertEqual(self.state.joinpath("status").read_text(), "Fehler\n")

    def test_multiple_contacts_pass_only_private_filename_to_osascript(self) -> None:
        self.write_contacts(
            "One,one@example.test,tenant-one\nTwo,two@example.test,tenant-two\n"
        )
        write_executable(
            self.osascript,
            """#!/usr/bin/env bash
printf '%s\\n' "$@" > "$OSASCRIPT_ARGS"
cat >/dev/null
printf '2\\n'
""",
        )
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.osascript_args.read_text()
        self.assertEqual(arguments.splitlines()[0], "-")
        self.assertNotIn("one@example.test", arguments)
        self.assertNotIn("tenant-one", arguments)
        self.assertEqual(self.state.joinpath("status").read_text(), "Anruf gestartet\n")

    def test_existing_insecure_config_directory_is_rejected_not_changed(self) -> None:
        self.write_contacts("Private Name,private@example.test,secret-tenant\n")
        self.csv.parent.chmod(0o755)
        result = self.run_picker()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(stat.S_IMODE(self.csv.parent.stat().st_mode), 0o755)
        self.assertIn("chmod 700", result.stderr)
        self.assertNotIn("private@example.test", result.stdout + result.stderr)

    def test_existing_insecure_status_directory_is_rejected_not_changed(self) -> None:
        self.write_contacts("Private Name,private@example.test,secret-tenant\n")
        self.state.mkdir(parents=True)
        self.state.chmod(0o755)
        result = self.run_picker()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o755)
        self.assertFalse(self.state.joinpath("status").exists())


class ConfigurationSafetyTests(unittest.TestCase):
    def test_home_manager_module_has_no_retroactive_cleanup_activation(self) -> None:
        module = LOCAL_PRIVATE_TOOLS_MODULE.read_text(encoding="utf-8")
        self.assertNotIn("home.activation", module)
        self.assertNotIn("chmod", module)
        self.assertNotIn("/tmp/raycast-teams-video-call.log", module)


if __name__ == "__main__":
    unittest.main(verbosity=2)
