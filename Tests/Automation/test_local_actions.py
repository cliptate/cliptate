"""Exercise local release provenance without building or contacting GitHub."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("local_actions", ROOT / "scripts/local-actions.py")
local_actions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_actions)


class LocalSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.root_patch = patch.object(local_actions, "ROOT", self.work)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Automation Test")
        (self.work / "source.swift").write_text("original source")
        self.git("add", ".")
        self.git("commit", "-qm", "test: add fixture")
        self.commit = self.git("rev-parse", "HEAD")
        self.git("tag", "v1.0")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.work, text=True).strip()

    def verify(self, tag="v1.0", *, remote=None, built=None):
        original = local_actions.output

        def output(*args):
            if args[0] == "gh":
                self.endpoint = args[2]
                return self.commit if remote is None else remote
            return original(*args)

        with patch.object(local_actions, "output", side_effect=output):
            return local_actions.verify_source(tag, built)

    def test_clean_version_and_nightly_accept_pushed_commit(self):
        self.assertEqual(self.verify(), self.commit)
        self.assertEqual(self.verify("nightly"), self.commit)
        self.assertTrue(self.endpoint.endswith("/commits/main"))

    def test_untracked_and_modified_sources_are_rejected(self):
        extra = self.work / "extra.swift"
        extra.write_text("untracked")
        with self.assertRaisesRegex(ValueError, "clean checkout"):
            self.verify()
        extra.unlink()
        (self.work / "source.swift").write_text("edited")
        with self.assertRaisesRegex(ValueError, "clean checkout"):
            self.verify()

    def test_local_and_remote_tag_mismatches_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "published"):
            self.verify(remote="b" * 40)
        (self.work / "source.swift").write_text("next source")
        self.git("commit", "-qam", "test: change fixture")
        with self.assertRaisesRegex(ValueError, "identify HEAD"):
            self.verify()

    def test_head_change_after_build_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "HEAD changed"):
            self.verify(built="b" * 40)

    def test_configuration_files_must_exist_outside_checkout(self):
        internal = self.work / ".env.secrets"
        internal.write_text("SECRET=fixture")
        with patch.dict(os.environ, ACT_SECRETS_FILE=str(internal)):
            with self.assertRaisesRegex(ValueError, "outside this checkout"):
                local_actions.configuration_file("ACT_SECRETS_FILE", "unused")

    def test_local_runs_cannot_overlap(self):
        with local_actions.local_lock():
            with self.assertRaisesRegex(ValueError, "Another local Action"):
                with local_actions.local_lock():
                    self.fail("overlapping lock was acquired")


class LocalBuildVersionTests(unittest.TestCase):
    def test_local_configuration_requires_explicit_version_and_cloud_ignores_it(self):
        import base64
        for act, version, expected in [("true", "1042.1770000000", "1042.1770000000"),
                                       ("true", "", None), ("true", "invalid", None),
                                       ("", "1042.1770000000", "1042.1")]:
            with self.subTest(act=act, version=version), tempfile.TemporaryDirectory() as temp:
                destination = Path(temp) / "environment"
                environment = {**os.environ, "ACT": act, "CLIPTATE_LOCAL_BUILD_VERSION": version,
                               "GITHUB_RUN_NUMBER": "42", "GITHUB_RUN_ATTEMPT": "1",
                               "GITHUB_REPOSITORY": "cliptate/cliptate", "RELEASE_TAG": "nightly",
                               "SPARKLE_PUBLIC_KEY": base64.b64encode(b"p" * 32).decode(),
                               "GITHUB_ENV": str(destination)}
                result = subprocess.run(["python3", str(ROOT / "scripts/release-policy.py"), "configure"],
                                        env=environment, text=True, capture_output=True)
                if expected is None:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(destination.exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(f"CURRENT_PROJECT_VERSION={expected}\n", destination.read_text())


class LocalEntryPointTests(unittest.TestCase):
    def test_entry_points_select_existing_jobs_and_publish_only_on_release(self):
        for task in ["ci", "package", "release", "plan"]:
            with self.subTest(task=task), tempfile.TemporaryDirectory() as temp:
                captured = []

                def run(command, **kwargs):
                    event = json.loads(Path(command[command.index("--eventpath") + 1]).read_text())
                    captured.append((command, kwargs["env"], event))

                def output(*command):
                    if command == ("uname", "-s"):
                        return "Darwin"
                    if command == ("uname", "-m"):
                        return "arm64"
                    if command[0] == "gh":
                        return "42"
                    if command[:2] == ("git", "check-ref-format"):
                        return ""
                    raise AssertionError(command)

                with patch.object(local_actions, "ROOT", Path(temp)), \
                     patch.object(local_actions, "output", side_effect=output), \
                     patch.object(local_actions, "verify_source") as verify, \
                     patch.object(local_actions, "configuration_file", return_value="/private/config.fixture"), \
                     patch.object(local_actions.shutil, "which", return_value="/fixture/bin"), \
                     patch.object(local_actions.subprocess, "run", side_effect=run), \
                     patch.object(sys, "argv", ["local-actions.py", task]), \
                     patch.dict(os.environ, {"TAG": "v1.3", "BUILD_VERSION": "", "DEVELOPER_DIR": temp,
                                             "GITHUB_TOKEN": "test-secret-token", "GH_TOKEN": "test-secret-token"}):
                    local_actions.main()
                command, environment, event = captured[0]
                self.assertEqual(event["local_publish"], task == "release")
                self.assertEqual(event["ref"], "refs/tags/v1.3")
                self.assertTrue(event["act"])
                self.assertNotIn("test-secret-token", " ".join(command))
                self.assertEqual(environment["GITHUB_TOKEN"], "test-secret-token")
                self.assertIn(f"CLIPTATE_LOCAL_WORKSPACE={temp}", command)
                if task != "plan":
                    self.assertEqual(command[command.index("--job") + 1],
                                     "macos" if task == "ci" else "release" if task == "release" else "build")
                self.assertTrue(command[command.index("--workflows") + 1].endswith(
                    "ci.yml" if task == "ci" else "package.yml"))
                self.assertEqual(verify.call_count, 1 if task == "release" else 0)
                if task in ["package", "release"]:
                    version = next(value for value in command if value.startswith("CLIPTATE_LOCAL_BUILD_VERSION="))
                    self.assertTrue(version.startswith("CLIPTATE_LOCAL_BUILD_VERSION=1042."))
                if task == "plan":
                    self.assertIn("--list", command)
                    self.assertNotIn("--dryrun", command)


if __name__ == "__main__":
    unittest.main()
