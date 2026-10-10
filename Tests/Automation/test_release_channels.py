"""Exercise the workflow's feed configuration without credentials or network access."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/package.yml"


class ReleaseChannelTests(unittest.TestCase):
    def test_nightly_checks_out_main_and_version_releases_check_out_the_tag(self):
        checkout = WORKFLOW.read_text().split("- name: Identify release source", 1)[0]
        self.assertIn("ref: ${{ github.ref_type == 'tag' && github.ref_name != 'nightly' && github.ref || 'main' }}",
                      checkout)

    def configured_feed(self, tag):
        step = WORKFLOW.read_text().split("- name: Configure signed updates", 1)[1]
        script = textwrap.dedent(step.split("python3 - <<'PY'\n", 1)[1].split("\n          PY", 1)[0])
        with tempfile.TemporaryDirectory() as directory:
            environment_file = Path(directory) / "environment"
            environment = os.environ.copy()
            environment.update({
                "SPARKLE_PUBLIC_KEY": base64.b64encode(b"p" * 32).decode(),
                "SPARKLE_PRIVATE_KEY": "test-only-placeholder",
                "RELEASE_TAG": tag,
                "GITHUB_REPOSITORY": "cliptate/cliptate",
                "GITHUB_ENV": str(environment_file),
                "GITHUB_RUN_NUMBER": "42",
                "GITHUB_RUN_ATTEMPT": "1",
            })
            subprocess.run(["python3", "-c", script], env=environment, check=True,
                           capture_output=True)
            settings = dict(line.split("=", 1) for line in environment_file.read_text().splitlines())
            return settings["CLIPTATE_UPDATE_FEED_URL"]

    def test_nightly_uses_the_latest_stable_feed(self):
        self.assertEqual(self.configured_feed("nightly"),
                         "https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml")

    def test_stable_uses_latest_feed_even_when_built_from_a_version_tag(self):
        self.assertEqual(self.configured_feed("v1.0"),
                         "https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml")

    def test_source_builds_use_the_latest_stable_feed(self):
        configuration = (ROOT / "config/Cliptate.xcconfig").read_text()
        self.assertIn("CLIPTATE_UPDATE_FEED_URL = https:/$()/github.com/cliptate/cliptate/releases/latest/download/appcast.xml",
                      configuration)

    def test_no_main_feed_publication_step_remains(self):
        self.assertNotIn("publish-main-appcast", WORKFLOW.read_text())

    def test_only_stable_runs_generate_and_upload_appcast(self):
        workflow = WORKFLOW.read_text()
        for name in ["Generate signed appcast", "Upload appcast"]:
            step = workflow.split(f"- name: {name}", 1)[1].split("- name:", 1)[0]
            self.assertIn("if: ${{ steps.source.outputs.release-tag != 'nightly' }}", step)


if __name__ == "__main__":
    unittest.main()
