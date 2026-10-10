"""Reject debugging permissions before a signed app is packaged for distribution."""

from pathlib import Path
import plistlib
import subprocess
import sys
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/verify-distribution-entitlements.py"


class DistributionEntitlementsTests(unittest.TestCase):
    def verify(self, entitlements):
        return subprocess.run([sys.executable, str(SCRIPT)],
                              input=plistlib.dumps(entitlements), capture_output=True)

    def test_debuggable_application_is_rejected(self):
        result = self.verify({"com.apple.security.app-sandbox": True,
                              "com.apple.security.get-task-allow": True})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"get-task-allow", result.stderr)

    def test_sandboxed_application_without_debugging_permission_is_allowed(self):
        result = self.verify({"com.apple.security.app-sandbox": True,
                              "com.apple.security.network.client": True})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicitly_disabled_debugging_permission_is_allowed(self):
        result = self.verify({"com.apple.security.get-task-allow": False})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unreadable_entitlements_are_rejected(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], input=b"invalid plist",
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
