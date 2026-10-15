"""Exercise local launch behavior when production privacy grants already exist."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]


class DevelopmentPermissionIdentityTests(unittest.TestCase):
    def launch(self, compatible=False, mode="run", override=False, installed=True,
               reverse_compatible=True, development=False):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            installed_app = path / "installed/Cliptate.app"
            built_app = path / "build/Build/Products/Debug/Cliptate Dev.app"
            for app in [built_app, *([installed_app] if installed else [])]:
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": ("com.cliptate.dev" if development and app == built_app
                                           else "com.voicepink.voicepinkpro"),
                }))
            commands = {
                "xcrun": "exit 0\n",
                "python3": f'if [[ "$1" == */build-app.py ]]; then exit 0; fi\nexec "{sys.executable}" "$@"\n',
                "open": 'touch "$CLIPTATE_TEST_LAUNCHED"\n',
                "lldb": 'touch "$CLIPTATE_TEST_LAUNCHED"\n',
                "log": "exit 0\n",
                "pgrep": "exit 0\n",
                "sleep": "exit 0\n",
                "codesign": '''
if [[ "$1" == -d ]]; then
  if [[ "$CLIPTATE_TEST_COMPATIBLE" == YES || "$*" == *"/installed/Cliptate.app"* ]]; then
    echo 'designated => identifier "com.voicepink.voicepinkpro" and anchor apple generic'
  else
    echo 'CDHash=0123456789abcdef0123456789abcdef01234567' >&2
  fi
  exit 0
fi
if [[ "$CLIPTATE_TEST_COMPATIBLE" == YES ]]; then
  if [[ "$CLIPTATE_TEST_REVERSE_COMPATIBLE" == YES || "$*" != *"/installed/Cliptate.app"* ]]; then
    exit 0
  fi
fi
echo 'code failed to satisfy specified code requirement(s)' >&2
exit 1
''',
            }
            for command, body in commands.items():
                executable = path / command
                executable.write_text("#!/bin/bash\n" + body)
                executable.chmod(0o755)
            launched = path / "launched"
            environment = os.environ.copy()
            environment.update({
                "PATH": str(path) + os.pathsep + environment["PATH"],
                "CONFIGURATION": "Debug",
                "DERIVED_DATA_PATH": str(path / "build"),
                "CODE_SIGN_IDENTITY": "-",
                "CLIPTATE_INSTALLED_APP": str(installed_app),
                "CLIPTATE_TEST_COMPATIBLE": "YES" if compatible else "NO",
                "CLIPTATE_TEST_REVERSE_COMPATIBLE": "YES" if reverse_compatible else "NO",
                "CLIPTATE_TEST_LAUNCHED": str(launched),
            })
            environment.pop("CLIPTATE_ALLOW_PERMISSION_RESET", None)
            if override:
                environment["CLIPTATE_ALLOW_PERMISSION_RESET"] = "YES"
            result = subprocess.run([str(ROOT / "scripts/build-and-run.sh"), mode],
                                    env=environment, capture_output=True, text=True, timeout=10)
            return result, launched.exists()

    def test_incompatible_local_identity_cannot_replace_production_grants(self):
        result, launched = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(launched)
        self.assertIn("permission", result.stderr.lower())

    def test_isolated_development_app_can_launch_alongside_production(self):
        result, launched = self.launch(development=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(launched)

    def test_every_launch_mode_checks_permission_identity(self):
        for mode in ["--debug", "--logs", "--verify"]:
            with self.subTest(mode=mode):
                result, launched = self.launch(mode=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(launched)

    def test_compatible_signed_identity_can_launch(self):
        result, launched = self.launch(compatible=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(launched)

    def test_switching_back_to_installed_app_must_preserve_grants(self):
        result, launched = self.launch(compatible=True, reverse_compatible=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(launched)

    def test_build_without_launch_still_allows_ad_hoc_signing(self):
        result, launched = self.launch(mode="build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(launched)

    def test_first_install_can_launch(self):
        result, launched = self.launch(installed=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(launched)

    def test_explicit_permission_reset_override_can_launch(self):
        result, launched = self.launch(override=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(launched)


if __name__ == "__main__":
    unittest.main()
