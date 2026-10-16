"""Verify bundled identity, channel, update metadata, and signing permissions."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import app_bundle


class BuildChannelTests(unittest.TestCase):
    def test_package_graph_has_no_billing_sdk(self):
        result = subprocess.run(["swift", "package", "dump-package", "--package-path", str(ROOT)],
                                check=True, capture_output=True, text=True)
        manifest = json.loads(result.stdout)
        identities = {dependency["sourceControl"][0]["identity"]
                      for dependency in manifest["dependencies"]}
        self.assertNotIn("purchases-ios-spm", identities)

    def test_debug_and_release_are_free_direct_bundles(self):
        for configuration in ["Debug", "Release"]:
            with self.subTest(configuration=configuration):
                values = self.values(configuration=configuration)
                info = app_bundle.info_plist(values)
                permissions = app_bundle.entitlements(values)
                self.assertFalse(permissions.get("com.apple.security.app-sandbox", False))
                self.assertFalse(info["CFBundleURLTypes"][0]["CFBundleURLSchemes"][0].endswith("-disabled"))

    def values(self, configuration="Debug", **overrides):
        env = {"CONFIGURATION": configuration, **overrides}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config").mkdir()
            (root / "config/app.json").write_bytes((ROOT / "config/app.json").read_bytes())
            return app_bundle.settings(root, env)

    def test_build_configurations_keep_distribution_identity(self):
        for configuration in ["Debug", "Release"]:
            with self.subTest(configuration=configuration):
                values = self.values(configuration)
                info = app_bundle.info_plist(values)
                permissions = app_bundle.entitlements(values)
                self.assertEqual(info["CFBundleIdentifier"], "com.cliptate.dev" if configuration == "Debug"
                                 else "com.cliptate.app")
                self.assertEqual(info["CFBundleExecutable"], "Cliptate Dev" if configuration == "Debug" else "Cliptate")
                scheme = info["CFBundleURLTypes"][0]["CFBundleURLSchemes"][0]
                self.assertEqual(scheme, "cliptate-dev-cli" if configuration == "Debug" else "cliptate-cli")
                self.assertTrue(permissions["com.apple.security.device.audio-input"])
                self.assertEqual(permissions.get("com.apple.security.get-task-allow", False), configuration == "Debug")
                self.assertNotIn("$(", plistlib.dumps(info).decode())
                self.assertNotIn("$(", plistlib.dumps(permissions).decode())

    def test_development_never_enables_production_updates(self):
        values = self.values(CLIPTATE_UPDATES_ENABLED="YES")
        self.assertEqual(app_bundle.info_plist(values)["CliptateUpdatesEnabled"], "NO")

    def test_release_accepts_build_number_and_update_configuration(self):
        values = self.values("Release", CURRENT_PROJECT_VERSION="1042.2",
                             CLIPTATE_SPARKLE_PUBLIC_KEY="public-key")
        info = app_bundle.info_plist(values)
        self.assertEqual(info["CFBundleVersion"], "1042.2")
        self.assertEqual(info["SUPublicEDKey"], "public-key")
        self.assertTrue(info["SUFeedURL"].startswith("https://"))
        self.assertNotIn("com.apple.security.get-task-allow", app_bundle.entitlements(values, helper=True))

    def test_local_configuration_and_environment_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config").mkdir()
            (root / "config/app.json").write_bytes((ROOT / "config/app.json").read_bytes())
            (root / "config/Local.xcconfig").write_text(
                "CLIPTATE_SPARKLE_PUBLIC_KEY = legacy\n"
                "CLIPTATE_UPDATE_FEED_URL = https:/$()/example.com/feed.xml\n")
            (root / "config/Local.json").write_text(json.dumps({"CLIPTATE_SPARKLE_PUBLIC_KEY": "local"}))
            self.assertEqual(app_bundle.settings(root, {})["CLIPTATE_SPARKLE_PUBLIC_KEY"], "local")
            values = app_bundle.settings(root, {"CLIPTATE_SPARKLE_PUBLIC_KEY": "environment"})
            self.assertEqual(values["CLIPTATE_SPARKLE_PUBLIC_KEY"], "environment")
            self.assertEqual(values["CLIPTATE_UPDATE_FEED_URL"], "https://example.com/feed.xml")


class BundleAssemblyTests(unittest.TestCase):
    def test_bundle_omits_resources_left_by_the_removed_billing_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _, _ = self.assemble(directory)
            self.assertFalse((app / "Contents/Resources/RevenueCat_RevenueCat.bundle").exists())

    def test_firebase_configuration_matches_the_bundled_identity(self):
        for configuration in ["Debug", "Release"]:
            with self.subTest(configuration=configuration), tempfile.TemporaryDirectory() as directory:
                app, _, _ = self.assemble(directory, configuration)
                info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                firebase = plistlib.loads((app / "Contents/Resources/GoogleService-Info.plist").read_bytes())
                self.assertEqual(firebase["BUNDLE_ID"], info["CFBundleIdentifier"])
                self.assertEqual(firebase["PROJECT_ID"], "cliptate-9d41b")
                self.assertFalse(info["FirebaseAppDelegateProxyEnabled"])
                self.assertFalse(info["FIREBASE_ANALYTICS_COLLECTION_ENABLED"])

    def assemble(self, directory, configuration="Debug", fail_signing=False):
        work = Path(directory)
        bin_path = work / "bin"
        bin_path.mkdir()
        for name in ["Cliptate", "CliptateCLI"]:
            (bin_path / name).write_bytes(name.encode())
        for name in ["Cliptate_CliptateTests", "Cliptate_CliptateCoreTests", "AudioKit_AudioKit", "mlx-swift_Cmlx", "RevenueCat_RevenueCat"]:
            bundle = bin_path / f"{name}.bundle/Contents/Resources"
            bundle.mkdir(parents=True)
            (bundle / ("default.metallib" if name == "mlx-swift_Cmlx" else "fixture")).write_bytes(b"resource")
        (bin_path / "Sparkle.framework/Versions/B").mkdir(parents=True)
        (bin_path / "Sparkle.framework/Versions/Current").symlink_to("B")
        values = BuildChannelTests().values(configuration)
        destination = work / "output" / (values["PRODUCT_NAME"] + ".app")
        destination.mkdir(parents=True)
        (destination / "previous").touch()
        signed = []
        calls = []

        def command(*arguments, **kwargs):
            args = [str(item) for item in arguments]
            calls.append((args, kwargs))
            if "--show-bin-path" in args:
                return str(bin_path)
            if "show-dependencies" in args:
                return json.dumps({"name": "Cliptate", "dependencies": [
                    {"name": "AudioKit"}, {"name": "mlx-swift"},
                ]})
            if args[0] == "otool":
                return "cmd LC_RPATH\n cmdsize 80\n path /temporary/build (offset 12)"
            if "actool" in args:
                Path(args[args.index("--output-partial-info-plist") + 1]).write_bytes(plistlib.dumps({"CFBundleIconFile": "AppIcon"}))
            if "xcstringstool" in args:
                resources = Path(args[-1])
                (resources / "de.lproj").mkdir()
                (resources / "de.lproj/Localizable.strings").touch()
            if args[0] == "codesign" and "--entitlements" in args:
                signed.append(plistlib.loads(Path(args[args.index("--entitlements") + 1]).read_bytes()))
                if fail_signing:
                    raise ValueError("signing failed")
            return ""

        with patch.object(app_bundle, "run", side_effect=command):
            if fail_signing:
                with self.assertRaisesRegex(ValueError, "signing failed"):
                    app_bundle.build_app(values, destination, "-")
            else:
                app_bundle.build_app(values, destination, "-")
        return destination, signed, calls

    def test_direct_bundle_contains_runtime_resources_helper_and_relative_framework_path(self):
        with tempfile.TemporaryDirectory() as directory:
            app, signed, calls = self.assemble(directory)
            self.assertTrue((app / "Contents/Helpers/cliptate").is_file())
            self.assertEqual((app / "Contents/MacOS/Cliptate Dev").read_bytes(), b"Cliptate")
            self.assertEqual((app / "Contents/Helpers/cliptate").read_bytes(), b"CliptateCLI")
            self.assertTrue((app / "Contents/Resources/de.lproj/Localizable.strings").is_file())
            self.assertTrue((app / "Contents/Resources/AudioKit_AudioKit.bundle").is_dir())
            self.assertFalse((app / "Contents/Resources/Cliptate_CliptateTests.bundle").exists())
            self.assertFalse((app / "Contents/Resources/Cliptate_CliptateCoreTests.bundle").exists())
            self.assertTrue((app / "Contents/Frameworks/Sparkle.framework/Versions/Current").is_symlink())
            self.assertTrue(signed[-1]["com.apple.security.get-task-allow"])
            self.assertFalse(signed[-1].get("com.apple.security.app-sandbox", False))
            self.assertTrue(any("@executable_path/../Frameworks" in args for args, _ in calls))
            products = [args[args.index("--product") + 1] for args, _ in calls if "--product" in args]
            self.assertEqual(products, ["Cliptate", "CliptateCLI"])

    def test_release_includes_helper_without_sandbox_or_debugging_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            app, signed, calls = self.assemble(directory, "Release")
            self.assertTrue((app / "Contents/Helpers/cliptate").is_file())
            self.assertFalse(signed[-1].get("com.apple.security.app-sandbox", False))
            self.assertNotIn("com.apple.security.get-task-allow", signed[-1])
            self.assertTrue(any("strip" in args for args, _ in calls))

    def test_failed_signing_preserves_previous_working_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _, _ = self.assemble(directory, fail_signing=True)
            self.assertTrue((app / "previous").is_file())

    def test_release_app_and_helper_keep_distinct_debug_symbols(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, calls = self.assemble(directory, "Release")
            outputs = [Path(args[args.index("-o") + 1]).name
                       for args, _ in calls if "dsymutil" in args]
            self.assertEqual(len({name.casefold() for name in outputs}), 2)


if __name__ == "__main__":
    unittest.main()
