import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildChannelTests(unittest.TestCase):
    def build_arguments(self, channel=None, configuration="Debug", automatic_signing=False):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for command, body in {
                "xcrun": "exit 0\n",
                "xcodebuild": ('printf "%s\\n" "$@" > "$CLIPTATE_TEST_ARGUMENTS"\n'
                               'mkdir -p "$DERIVED_DATA_PATH/Build/Products/Debug/Cliptate Dev.app/Contents/Frameworks/Sparkle.framework"\n'),
                "security": 'echo \'1) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Apple Development: Example (TEAM123456)"\'\n',
                "codesign": 'printf "%s\\n" "$@" >> "$CLIPTATE_TEST_ARGUMENTS"\n',
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
                "DEVELOPMENT_TEAM": "",
                "DERIVED_DATA_PATH": str(path / "derived"),
                "CLIPTATE_TEST_ARGUMENTS": str(arguments_file),
            })
            environment.pop("CLIPTATE_APP_STORE", None)
            if automatic_signing:
                environment.pop("CODE_SIGN_IDENTITY", None)
            if channel is not None:
                environment["CLIPTATE_APP_STORE"] = channel
            subprocess.run([str(ROOT / "scripts/build-and-run.sh"), "build"],
                           env=environment, capture_output=True, check=True)
            return arguments_file.read_text().splitlines()

    def test_default_debug_uses_direct_channel(self):
        arguments = self.build_arguments()
        self.assertIn("CLIPTATE_CHANNEL_CONDITIONS=", arguments)
        self.assertIn("CLIPTATE_ENABLE_APP_SANDBOX=NO", arguments)
        self.assertIn("CLIPTATE_CLI_URL_SCHEME=cliptate-dev-cli", arguments)
        self.assertIn("CLIPTATE_CODE_SIGN_ENTITLEMENTS=" + str(
            ROOT / "Sources/Cliptate/Cliptate-Direct.entitlements"), arguments)

    def test_explicit_app_store_debug_overrides_direct_defaults(self):
        arguments = self.build_arguments("YES")
        self.assertIn("CLIPTATE_CHANNEL_CONDITIONS=APP_STORE", arguments)
        self.assertIn("CLIPTATE_ENABLE_APP_SANDBOX=YES", arguments)
        self.assertIn("CLIPTATE_CLI_URL_SCHEME=cliptate-dev-cli-disabled", arguments)
        self.assertIn("CLIPTATE_CODE_SIGN_ENTITLEMENTS=" + str(
            ROOT / "Sources/Cliptate/Cliptate.entitlements"), arguments)

    def test_debug_selects_dev_scheme_and_passes_detected_identity_to_nested_signing(self):
        arguments = self.build_arguments(automatic_signing=True)
        self.assertIn("Cliptate Dev", arguments)
        self.assertIn("CODE_SIGN_IDENTITY=" + "B" * 40, arguments)
        self.assertIn("DEVELOPMENT_TEAM=TEAM123456", arguments)
        self.assertIn("--sign", arguments)
        self.assertIn("B" * 40, arguments)

    def test_release_keeps_the_production_scheme(self):
        arguments = self.build_arguments(configuration="Release")
        self.assertIn("Cliptate", arguments)
        self.assertNotIn("Cliptate Dev", arguments)
        self.assertFalse(any(arg.startswith("CLIPTATE_CHANNEL_CONDITIONS=") for arg in arguments))

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
        self.assertNotIn("CLIPTATE_CODE_SIGN_ENTITLEMENTS=" + str(direct_path),
                         self.build_arguments("YES"))
        self.assertFalse(any(arg.startswith("CODE_SIGN_ENTITLEMENTS=")
                             for arg in self.build_arguments("NO", "Release")))
        direct = plistlib.loads(direct_path.read_bytes())
        store = plistlib.loads((ROOT / "Sources/Cliptate/Cliptate.entitlements").read_bytes())
        self.assertFalse(direct.get("com.apple.security.app-sandbox", False))
        self.assertTrue(store["com.apple.security.app-sandbox"])
        self.assertTrue(direct["com.apple.security.device.audio-input"])
        self.assertIn("CLIPTATE_ENABLE_APP_SANDBOX=NO", self.build_arguments("NO"))
        self.assertIn("CLIPTATE_CLI_URL_SCHEME=cliptate-dev-cli", self.build_arguments("NO"))
        self.assertIn("CLIPTATE_CLI_URL_SCHEME=cliptate-cli", self.build_arguments("NO", "Release"))
        self.assertIn("CLIPTATE_ENABLE_APP_SANDBOX=YES", self.build_arguments("YES"))

    def test_local_release_can_load_ad_hoc_signed_frameworks(self):
        self.assertIn("ENABLE_HARDENED_RUNTIME=NO",
                      self.build_arguments("NO", "Release"))


if __name__ == "__main__":
    unittest.main()
