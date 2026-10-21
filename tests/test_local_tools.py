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

# The installed qwen wrappers exec Nix's zsh, which is the zsh on PATH inside
# the flake check. macOS's /bin/zsh is only the fallback for manual runs.
ZSH = shutil.which("zsh") or "/bin/zsh"
# Raycast starts the Teams script through `/usr/bin/env bash`, which resolves
# to macOS's bash 3.2 under Raycast's default PATH, so test with that one.
SYSTEM_BASH = "/bin/bash"


def write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o700)


def run_command(
    command: list[str], environment: dict[str, str], cwd: Path = REPO_ROOT
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
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

    def run_wrapper(self, *arguments: str, cwd: Path = REPO_ROOT) -> subprocess.CompletedProcess[str]:
        return run_command([ZSH, str(QWEN), *arguments], self.environment, cwd)

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

    def test_dash_and_serve_file_names_reach_the_asr_as_absolute_paths(self) -> None:
        # The ASR CLI would read "-x.m4a" as an option and "serve" as its
        # server subcommand; an absolute path is neither.
        for name in ("-x.m4a", "serve"):
            with self.subTest(name=name):
                audio = self.home / name
                audio.write_bytes(b"audio")
                result = self.run_wrapper("--no-open", "--", name, cwd=self.home)
                self.assertEqual(result.returncode, 0, result.stderr)
                given = self.asr_args.read_text().splitlines()[0]
                self.assertTrue(given.startswith("/"), given)
                self.assertEqual(Path(given).resolve(), audio.resolve())

    def test_dot_dot_after_a_symlinked_directory_reaches_the_checked_file(self) -> None:
        # "link/../x" means the parent of the link's target. Editing the path
        # as text would drop "link/.." and name a different file.
        real = self.root / "real"
        (real / "recordings").mkdir(parents=True)
        audio = real / "talk.m4a"
        audio.write_bytes(b"audio")
        work = self.root / "work"
        work.mkdir()
        (work / "recordings").symlink_to(real / "recordings")
        result = self.run_wrapper("--no-open", "recordings/../talk.m4a", cwd=work)
        self.assertEqual(result.returncode, 0, result.stderr)
        given = self.asr_args.read_text().splitlines()[0]
        self.assertTrue(given.startswith("/"), given)
        self.assertEqual(Path(given).resolve(), audio.resolve())

    def test_missing_nix_runtime_is_reported_before_any_output(self) -> None:
        self.environment["QWEN_MEETING_ASR"] = ""
        result = self.run_wrapper(str(self.audio))
        self.assertEqual(result.returncode, 3)
        self.assertIn("Nix-Laufzeit", result.stderr)
        self.assertFalse(self.asr_args.exists())
        self.assertFalse(self.output.exists())


class QwenSetupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="qwen-setup-test.")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.runtime = self.home / "runtime"
        self.state = self.home / "state"
        self.fetch_args = self.root / "fetch-args"
        self.fetch_environment = self.root / "fetch-environment"
        self.runtime.mkdir(parents=True)
        (self.runtime / "fetch-models.py").touch()
        python = self.root / "python"
        asr = self.root / "asr"
        write_executable(
            python,
            '#!/bin/bash\nprintf "%s\\n" "$@" > "${FETCH_ARGS_FILE:?}"\n'
            'printf "%s\\n" "${HF_HOME:-}" "${HF_HUB_DISABLE_TELEMETRY:-}"'
            ' "${HF_HUB_DISABLE_IMPLICIT_TOKEN:-}" "${HF_HUB_OFFLINE:-unset}"'
            ' > "${FETCH_ENV_FILE:?}"\n',
        )
        write_executable(asr, '#!/bin/bash\n[[ "$1" == "--doctor" ]]\n')
        self.environment = os.environ.copy()
        for name in ("HF_HOME", "HF_HUB_DISABLE_TELEMETRY", "HF_HUB_DISABLE_IMPLICIT_TOKEN", "HF_HUB_OFFLINE"):
            self.environment.pop(name, None)
        self.environment.update({
            "QWEN_MEETING_RUNTIME": str(self.runtime),
            "QWEN_MEETING_STATE_HOME": str(self.state),
            "QWEN_MEETING_PYTHON": str(python),
            "QWEN_MEETING_ASR": str(asr),
            "FETCH_ARGS_FILE": str(self.fetch_args),
            "FETCH_ENV_FILE": str(self.fetch_environment),
        })

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_setup(self) -> subprocess.CompletedProcess[str]:
        return run_command([ZSH, str(QWEN_SETUP)], self.environment)

    def test_setup_only_fetches_models_with_injected_runtime(self) -> None:
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.fetch_args.read_text().splitlines()
        self.assertEqual(arguments, [str(self.runtime / "fetch-models.py"), "--state-dir", str(self.state)])
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)

    def test_setup_keeps_hugging_face_state_private_and_online(self) -> None:
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.fetch_environment.read_text().splitlines(),
            [str(self.state / "huggingface"), "1", "1", "unset"],
        )

    def test_setup_requires_nix_runtime(self) -> None:
        self.environment["QWEN_MEETING_PYTHON"] = "/nonexistent"
        result = self.run_setup()
        self.assertEqual(result.returncode, 3)
        self.assertFalse(self.fetch_args.exists())

    def test_setup_rejects_insecure_existing_state_without_chmod(self) -> None:
        self.state.mkdir(parents=True)
        self.state.chmod(0o755)
        result = self.run_setup()
        self.assertEqual(result.returncode, 5)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o755)
        self.assertFalse(self.fetch_args.exists())


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

    def run_picker(self, *arguments: str, bash: str = SYSTEM_BASH) -> subprocess.CompletedProcess[str]:
        return run_command([bash, str(TEAMS), *arguments], self.environment)

    def write_contacts(self, content: str, mode: int = 0o600) -> None:
        self.csv.write_text(content, encoding="utf-8")
        self.csv.chmod(mode)

    def fake_picker(self, answer: str) -> None:
        """Records the rows the picker would show and picks `answer`."""
        write_executable(
            self.osascript,
            f"""#!/usr/bin/env bash
printf '%s\\n' "$@" > "$OSASCRIPT_ARGS"
cat >/dev/null
cp "$2" "$OSASCRIPT_ARGS.rows"
printf '{answer}\\n'
""",
        )

    def shown_rows(self) -> list[str]:
        return Path(f"{self.osascript_args}.rows").read_text(encoding="utf-8").splitlines()

    def call_url(self, *arguments: str, bash: str = SYSTEM_BASH) -> str:
        """Places a real (faked) call and returns the deep link it opened."""
        opened = self.root / "opened-url"
        open_command = self.root / "fake-open"
        write_executable(open_command, '#!/usr/bin/env bash\nprintf "%s" "$1" > "$OPENED_URL"\n')
        self.environment.update(
            {
                "TEAMS_CALL_DRY_RUN": "0",
                "TEAMS_CALL_OPEN_CMD": str(open_command),
                "OPENED_URL": str(opened),
            }
        )
        result = self.run_picker(*arguments, bash=bash)
        self.assertEqual(result.returncode, 0, result.stderr)
        return opened.read_text(encoding="utf-8")

    def test_single_contact_discloses_no_email_tenant_or_deep_link(self) -> None:
        self.write_contacts("Private Name,private@example.test,secret-tenant\n")
        self.fake_picker("1")
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

    def test_single_match_is_never_dialled_without_confirmation(self) -> None:
        self.write_contacts("Private Name,private@example.test,secret-tenant\n")
        self.fake_picker("")
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.shown_rows(), ["1\tPrivate Name — private@example.test"])
        self.assertIn("Abgebrochen", result.stdout)
        self.assertNotIn("würde geöffnet", result.stdout)
        self.assertEqual(self.state.joinpath("status").read_text(), "Abgebrochen\n")

    def test_header_row_is_not_a_contact(self) -> None:
        self.write_contacts(
            "name,email,tenantId\nOne,one@example.test,tenant-one\n"
        )
        self.fake_picker("1")
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.shown_rows(), ["1\tOne — one@example.test"])
        self.assertEqual(result.stderr, "")
        # Only the header contains "mail"; it must not become a callable match.
        result = self.run_picker("mail")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Keine passenden Teams-Kontakte", result.stderr)

    def test_quoted_name_with_comma_keeps_its_columns(self) -> None:
        self.write_contacts(
            '"Doe, John",john@example.test,tenant-two\n'
            '"Said ""Bob"" Smith",bob@example.test,tenant-three\n'
        )
        self.fake_picker("1")
        url = self.call_url("john")
        self.assertEqual(self.shown_rows(), ["1\tDoe, John — john@example.test"])
        self.assertIn("users=john%40example.test&", url)
        self.assertIn("tenantId=tenant-two&", url)
        self.fake_picker("1")
        self.call_url("bob")
        self.assertEqual(self.shown_rows(), ['1\tSaid "Bob" Smith — bob@example.test'])

    def test_malformed_rows_are_skipped_by_line_number_only(self) -> None:
        self.write_contacts(
            '"Unterminated,broken@example.test,tenant-x\n'
            "No Address,not-an-email,tenant-y\n"
            "Short Row,short@example.test\n"
            "One,one@example.test,tenant-one\n"
        )
        self.fake_picker("1")
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.shown_rows(), ["1\tOne — one@example.test"])
        for line in (1, 2, 3):
            self.assertIn(f"teams-people.csv:{line}:", result.stderr)
        for secret in ("Unterminated", "broken@", "not-an-email", "Short Row", "tenant-"):
            self.assertNotIn(secret, result.stdout + result.stderr)

    def test_non_ascii_address_is_percent_encoded_as_utf8_in_any_locale(self) -> None:
        shells = {SYSTEM_BASH, shutil.which("bash") or SYSTEM_BASH}
        for bash in sorted(shells):
            for locale in ("C", "en_US.UTF-8"):
                with self.subTest(bash=bash, locale=locale):
                    self.write_contacts("Jürgen,jürgen.łukasz@example.at,tenant-ü\n")
                    self.environment["LC_ALL"] = locale
                    self.fake_picker("1")
                    url = self.call_url(bash=bash)
                    self.assertIn("users=j%C3%BCrgen.%C5%82ukasz%40example.at&", url)
                    self.assertIn("tenantId=tenant-%C3%BC&", url)

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
