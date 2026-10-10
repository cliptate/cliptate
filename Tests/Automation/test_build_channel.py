import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildChannelTests(unittest.TestCase):
    def build_arguments(self, channel=None, configuration="Debug"):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for command, body in {
                "xcrun": "exit 0\n",
                "xcodebuild": 'printf "%s\\n" "$@" > "$CLIPTATE_TEST_ARGUMENTS"\n',
            }.items():
                executable = path / command
                executable.write_text("#!/bin/bash\n" + body)
                executable.chmod(0o755)
            arguments_file = path / "arguments"
            environment = os.environ.copy()
            environment.update({
                "PATH": str(path) + os.pathsep + environment["PATH"],
                "CONFIGURATION": configuration,
                "CODE_SIGN_IDENTITY": "-",
                "CLIPTATE_TEST_ARGUMENTS": str(arguments_file),
            })
            environment.pop("CLIPTATE_APP_STORE", None)
            if channel is not None:
                environment["CLIPTATE_APP_STORE"] = channel
            subprocess.run([str(ROOT / "scripts/build-and-run.sh"), "build"],
                           env=environment, capture_output=True, check=True)
            return arguments_file.read_text().splitlines()

    def test_default_preserves_project_app_store_conditions(self):
        arguments = self.build_arguments()
        self.assertFalse(any(arg.startswith("CLIPTATE_CHANNEL_CONDITIONS=")
                             for arg in arguments))

    def test_direct_debug_retains_debug_and_removes_app_store(self):
        arguments = self.build_arguments("NO")
        self.assertIn("CLIPTATE_CHANNEL_CONDITIONS=", arguments)
        self.assertFalse(any(arg.startswith("SWIFT_ACTIVE_COMPILATION_CONDITIONS=")
                             for arg in arguments))

    def test_direct_release_removes_app_store(self):
        self.assertIn("CLIPTATE_CHANNEL_CONDITIONS=",
                      self.build_arguments("NO", "Release"))

    def test_direct_builds_disable_sandbox_and_enable_cli(self):
        direct_path = ROOT / "Sources/Cliptate/Cliptate-Direct.entitlements"
        self.assertIn("CLIPTATE_CODE_SIGN_ENTITLEMENTS=" + str(direct_path),
                      self.build_arguments("NO", "Release"))
        self.assertFalse(any(arg.startswith("CLIPTATE_CODE_SIGN_ENTITLEMENTS=")
                             for arg in self.build_arguments()))
        self.assertFalse(any(arg.startswith("CODE_SIGN_ENTITLEMENTS=")
                             for arg in self.build_arguments("NO", "Release")))
        direct = plistlib.loads(direct_path.read_bytes())
        store = plistlib.loads((ROOT / "Sources/Cliptate/Cliptate.entitlements").read_bytes())
        self.assertFalse(direct.get("com.apple.security.app-sandbox", False))
        self.assertTrue(store["com.apple.security.app-sandbox"])
        self.assertTrue(direct["com.apple.security.device.audio-input"])
        self.assertIn("CLIPTATE_ENABLE_APP_SANDBOX=NO", self.build_arguments("NO"))
        self.assertIn("CLIPTATE_CLI_URL_SCHEME=cliptate-cli", self.build_arguments("NO"))
        self.assertFalse(any(arg.startswith("CLIPTATE_ENABLE_APP_SANDBOX=")
                             for arg in self.build_arguments()))

    def test_local_release_can_load_ad_hoc_signed_frameworks(self):
        self.assertIn("ENABLE_HARDENED_RUNTIME=NO",
                      self.build_arguments("NO", "Release"))


if __name__ == "__main__":
    unittest.main()
