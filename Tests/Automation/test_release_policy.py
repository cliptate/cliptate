"""Exercise release decisions and local adapters without credentials or network access."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from release_policy import build_plan, publication_plan

CLI = ROOT / "scripts/release-policy.py"
REPOSITORY = "cliptate/cliptate"
FEED = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"


class ReleasePolicyTests(unittest.TestCase):
    def build(self, ref_type="branch", ref_name="main", *, attempt="1"):
        return build_plan(ref_type, ref_name, REPOSITORY, "42", attempt)

    def test_branch_and_reserved_tag_builds_use_main_and_nightly(self):
        for ref_type, name in [("branch", "main"), ("branch", "feature"), ("tag", "nightly")]:
            with self.subTest(ref_type=ref_type, name=name):
                plan = self.build(ref_type, name)
                self.assertEqual(plan["source_ref"], "main")
                self.assertEqual(plan["release_tag"], "nightly")
                self.assertFalse(plan["generate_appcast"])
                self.assertEqual(plan["appcast_path"], "")
                self.assertEqual(plan["assets"], ["Cliptate.dmg", "Cliptate.dmg.sha256"])

    def test_version_tag_preserves_source_and_includes_feed(self):
        plan = self.build("tag", "v1.0")
        self.assertEqual(plan["source_ref"], "refs/tags/v1.0")
        self.assertEqual(plan["release_tag"], "v1.0")
        self.assertTrue(plan["generate_appcast"])
        self.assertEqual(plan["appcast_path"], "dist/appcast.xml")
        self.assertEqual(plan["assets"], ["Cliptate.dmg", "Cliptate.dmg.sha256", "appcast.xml"])

    def test_all_channels_share_stable_feed_and_monotonic_run_numbering(self):
        for ref_type, name in [("branch", "main"), ("tag", "v1.0")]:
            plan = self.build(ref_type, name, attempt="2")
            self.assertEqual(plan["feed_url"], FEED)
            self.assertEqual(plan["build_version"], "1042.2")
        self.assertEqual(build_plan("branch", "main", REPOSITORY, "43", "1")["build_version"], "1043.1")

    def test_nightly_publication_moves_tag_and_remains_prerelease(self):
        plan = publication_plan("nightly", REPOSITORY, "ad-hoc", "", "2026-10-10")
        self.assertTrue(plan["move_tag"])
        self.assertEqual(plan["flags"], ["--prerelease", "--latest=false"])
        self.assertEqual(plan["title"], "Nightly (2026-10-10)")

    def test_stable_adhoc_publication_without_feed_remains_supported(self):
        plan = publication_plan("v1.0", REPOSITORY, "ad-hoc", "", "2026-10-10")
        self.assertFalse(plan["move_tag"])
        self.assertEqual(plan["flags"], ["--prerelease=false", "--latest=true"])
        self.assertEqual(plan["title"], "Cliptate v1.0")
        self.assertIn("ad-hoc", plan["signing_description"])

    def test_signed_stable_feed_is_allowed(self):
        plan = publication_plan("v1.0", REPOSITORY, "developer-id-notarized", "dist/appcast.xml", "2026-10-10")
        self.assertEqual(plan["signing_description"], "Developer ID signed and Apple-notarized.")

    def test_feed_constraints_and_unknown_signing_status_remain_rejected(self):
        for tag, signing, feed, message in [
            ("nightly", "developer-id-notarized", "dist/appcast.xml", "Nightly"),
            ("v1.0", "ad-hoc", "dist/appcast.xml", "notarized"),
            ("v1.0", "unknown", "", "signing status"),
        ]:
            with self.subTest(tag=tag, signing=signing), self.assertRaisesRegex(ValueError, message):
                publication_plan(tag, REPOSITORY, signing, feed, "2026-10-10")

    def test_non_semver_tags_are_preserved_and_download_urls_are_encoded(self):
        tag = "preview/中文+1"
        self.assertEqual(self.build("tag", tag)["release_tag"], tag)
        plan = publication_plan(tag, "owner/fork", "ad-hoc", "", "2026-10-10")
        self.assertEqual(plan["encoded_tag"], "preview%2F%E4%B8%AD%E6%96%87%2B1")
        self.assertEqual(plan["download_url_prefix"],
                         "https://github.com/owner/fork/releases/download/" + plan["encoded_tag"] + "/")


class ReleasePolicyAdapterTests(unittest.TestCase):
    def environment(self, tag="nightly"):
        env = os.environ.copy()
        env.update({"GITHUB_REF_TYPE": "tag" if tag != "nightly" else "branch",
                    "GITHUB_REF_NAME": tag if tag != "nightly" else "main",
                    "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_RUN_NUMBER": "42",
                    "GITHUB_RUN_ATTEMPT": "2", "RELEASE_TAG": tag,
                    "SPARKLE_PUBLIC_KEY": base64.b64encode(b"p" * 32).decode(),
                    "SPARKLE_PRIVATE_KEY": "test-only-placeholder"})
        env.pop("APPCAST_PATH", None)
        env.pop("SIGNING_STATUS", None)
        return env

    def run_cli(self, *args, env=None):
        return subprocess.run([sys.executable, str(CLI), *args], env=env,
                              text=True, capture_output=True, cwd="/tmp")

    def test_build_json_and_github_outputs_describe_same_plan(self):
        for tag in ["nightly", "v1.0"]:
            with self.subTest(tag=tag):
                env = self.environment(tag)
                result = self.run_cli("build", env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                plan = json.loads(result.stdout)
                result = self.run_cli("build", "--format", "github", env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs = dict(line.split("=", 1) for line in result.stdout.splitlines())
                self.assertEqual(outputs["release-tag"], plan["release_tag"])
                self.assertEqual(outputs["generate-appcast"], "false" if tag == "nightly" else "true")
                self.assertEqual(outputs["appcast-path"], plan["appcast_path"])

    def test_configuration_writes_both_channels_without_leaking_private_key(self):
        for tag in ["nightly", "v1.0"]:
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "environment"
                env = self.environment(tag)
                env["GITHUB_ENV"] = str(output)
                result = self.run_cli("configure", env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                settings = dict(line.split("=", 1) for line in output.read_text().splitlines())
                self.assertEqual(settings["CLIPTATE_UPDATE_FEED_URL"], FEED)
                self.assertEqual(settings["CURRENT_PROJECT_VERSION"], "1042.2")
                self.assertEqual(settings["CLIPTATE_SPARKLE_PUBLIC_KEY"], env["SPARKLE_PUBLIC_KEY"])
                self.assertNotIn(env["SPARKLE_PRIVATE_KEY"], output.read_text() + result.stdout + result.stderr)

    def test_private_key_only_required_for_stable_configuration(self):
        for tag in ["nightly", "v1.0"]:
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "environment"
                env = self.environment(tag)
                env.update(SPARKLE_PRIVATE_KEY="", GITHUB_ENV=str(output))
                result = self.run_cli("configure", env=env)
                self.assertEqual(result.returncode == 0, tag == "nightly")
                self.assertEqual(output.exists(), tag == "nightly")

    def test_invalid_public_key_does_not_write_partial_configuration(self):
        for key in ["", "invalid", base64.b64encode(b"p" * 31).decode()]:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "environment"
                env = self.environment()
                env.update(SPARKLE_PUBLIC_KEY=key, GITHUB_ENV=str(output))
                result = self.run_cli("configure", env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_publication_fields_are_data_even_for_shell_metacharacters(self):
        env = self.environment("v$(touch should-not-exist)")
        result = self.run_cli("publication", "--field", "title", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Cliptate v$(touch should-not-exist)")
        result = self.run_cli("publication", "--field", "flags", env=env)
        self.assertEqual(result.stdout.splitlines(), ["--prerelease=false", "--latest=true"])

    def test_appcast_generation_uses_encoded_download_prefix(self):
        result = self.run_cli("download-prefix", "owner/fork", "preview/中文+1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(),
                         "https://github.com/owner/fork/releases/download/preview%2F%E4%B8%AD%E6%96%87%2B1/")


if __name__ == "__main__":
    unittest.main()
