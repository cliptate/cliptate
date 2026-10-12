"""Keep release identity changes from silently losing system privacy consent."""

import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("update_identity", ROOT / "scripts/verify-update-permission-identity.py")
update_identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update_identity)


class UpdatePermissionIdentityTests(unittest.TestCase):
    def verify(self, compatible, identifier="com.voicepink.voicepinkpro"):
        with tempfile.TemporaryDirectory() as directory:
            apps = [Path(directory) / "old.app", Path(directory) / "new.app"]
            for app in apps:
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": identifier,
                }))
            with patch.object(update_identity.subprocess, "run") as codesign, \
                    patch.object(update_identity, "mutually_compatible", return_value=compatible):
                update_identity.verify(*apps)
                self.assertEqual(codesign.call_count, 2)
                for call in codesign.call_args_list:
                    self.assertEqual(call.args[0][:4], ["codesign", "--verify", "--deep", "--strict"])
                    self.assertTrue(call.kwargs["check"])

    def test_compatible_update_is_allowed(self):
        self.verify(True)

    def test_identity_change_that_loses_grants_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "privacy permissions"):
            self.verify(False)

    def test_development_app_cannot_be_checked_as_a_production_update(self):
        with self.assertRaisesRegex(ValueError, "production"):
            self.verify(True, "com.cliptate.dev")

    def test_workflow_checks_identity_before_packaging_and_publication(self):
        workflow = (ROOT / ".github/workflows/package.yml").read_text()
        self.assertLess(workflow.index("- name: Verify privacy identity across updates"),
                        workflow.index("- name: Package and verify DMG"))
        self.assertIn("python3 scripts/verify-update-permission-identity.py", workflow)


if __name__ == "__main__":
    unittest.main()
