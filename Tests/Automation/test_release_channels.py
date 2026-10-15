"""Check workflow wiring; release decisions are tested through release_policy."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from release_policy import build_plan

WORKFLOW = ROOT / ".github/workflows/package.yml"


class ReleaseChannelTests(unittest.TestCase):
    def test_bootstrap_expressions_agree_with_policy(self):
        workflow = WORKFLOW.read_text()
        expression = "github.ref_type == 'tag' && github.ref_name != 'nightly'"
        self.assertIn("ref: ${{ " + expression + " && github.ref || 'main' }}", workflow)
        self.assertIn("group: package-${{ " + expression + " && github.ref_name || 'nightly' }}", workflow)
        for ref_type, name in [("branch", "main"), ("branch", "feature"),
                               ("tag", "nightly"), ("tag", "v1.0")]:
            plan = build_plan(ref_type, name, "cliptate/cliptate", "42", "1")
            tagged = ref_type == "tag" and name != "nightly"
            self.assertEqual(plan["source_ref"], f"refs/tags/{name}" if tagged else "main")
            self.assertEqual(plan["release_tag"], name if tagged else "nightly")

    def test_workflow_consumes_policy_after_checkout_and_passes_appcast_decision(self):
        workflow = WORKFLOW.read_text()
        self.assertIn("python3 scripts/release-policy.py build --format github", workflow)
        self.assertIn("python3 scripts/release-policy.py configure", workflow)
        self.assertIn("appcast-path: ${{ steps.source.outputs.appcast-path }}", workflow)
        self.assertIn("path: ${{ steps.source.outputs.appcast-path }}", workflow)
        self.assertIn("APPCAST_PATH: ${{ needs.build.outputs.appcast-path }}", workflow)
        generation = workflow.split("- name: Generate signed appcast", 1)[1].split("- name:", 1)[0]
        self.assertIn("if: ${{ steps.source.outputs.generate-appcast == 'true' }}", generation)
        upload = workflow.split("- name: Upload appcast", 1)[1].split("- name:", 1)[0]
        self.assertIn("if: ${{ !env.ACT && steps.source.outputs.generate-appcast == 'true' }}", upload)

    def test_source_builds_keep_stable_feed(self):
        configuration = json.loads((ROOT / "config/app.json").read_text())
        self.assertEqual(configuration["CLIPTATE_UPDATE_FEED_URL"],
                         "https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml")

    def test_notes_are_checked_before_building(self):
        workflow = WORKFLOW.read_text()
        self.assertIn('python3 scripts/release-notes.py "$RELEASE_TAG" --check', workflow)
        self.assertLess(workflow.index("- name: Verify version release notes"),
                        workflow.index("- name: Install Developer ID certificate"))

    def test_no_main_feed_publication_step_remains(self):
        self.assertNotIn("publish-main-appcast", WORKFLOW.read_text())


if __name__ == "__main__":
    unittest.main()
