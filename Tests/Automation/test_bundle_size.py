"""Keep bundled runtime resources without duplicate app catalogs or SDK slices."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import app_bundle


class BundleResourceTests(unittest.TestCase):
    def test_app_uses_main_catalogs_and_preserves_dependency_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = root / "products"
            resources = root / "resources"
            resources.mkdir()
            for name in ["Cliptate_Cliptate", "mlx-swift_Cmlx", "KeyboardShortcuts_KeyboardShortcuts"]:
                bundle = products / f"{name}.bundle"
                bundle.mkdir(parents=True)
                (bundle / "resource").write_bytes(b"runtime resource")
            (products / "mlx-swift_Cmlx.bundle/current").symlink_to("resource")

            app_bundle.copy_resources(products, resources)

            self.assertFalse((resources / "Cliptate_Cliptate.bundle").exists())
            for name in ["mlx-swift_Cmlx", "KeyboardShortcuts_KeyboardShortcuts"]:
                self.assertEqual((resources / f"{name}.bundle/resource").read_bytes(), b"runtime resource")
            self.assertTrue((resources / "mlx-swift_Cmlx.bundle/current").is_symlink())

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Requires Xcode resource tools")
    def test_compiled_localizations_are_compact_and_keep_translations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / "resources"
            resources.mkdir()

            app_bundle.compile_resources(resources, root)

            for language, cancel in {"en": "Cancel", "de": "Cancel", "ja": "キャンセル",
                                     "ko": "취소", "zh-Hans": "取消"}.items():
                with self.subTest(language=language):
                    data = (resources / f"{language}.lproj/Localizable.strings").read_bytes()
                    self.assertTrue(data.startswith(b"bplist00"))
                    strings = plistlib.loads(data)
                    if language == "en":
                        self.assertEqual(strings["AI Enhance"], "AI Enhance")
                    else:
                        self.assertEqual(strings["Cancel"], cancel)


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Requires macOS build tools")
class FrameworkSizeTests(unittest.TestCase):
    def test_framework_keeps_native_executables_resources_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "probe.c"
            source.write_text("int main(void) { return 0; }\n")
            fat = root / "universal"
            subprocess.run(["xcrun", "clang", "-arch", "arm64", "-arch", "x86_64",
                            str(source), "-o", str(fat)], check=True)
            framework = root / "Fixture.framework"
            version = framework / "Versions/B"
            version.mkdir(parents=True)
            for name in ["Fixture", "Autoupdate", "XPCServices/Installer.xpc/Contents/MacOS/Installer",
                         "XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
                         "Updater.app/Contents/MacOS/Updater"]:
                binary = version / name
                binary.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(fat, binary)
            (framework / "Versions/Current").symlink_to("B")
            (framework / "Fixture").symlink_to("Versions/Current/Fixture")
            (version / "Resources").mkdir()
            (version / "Resources/fixture.txt").write_bytes(b"updater resource")

            app_bundle.prepare_framework(framework, ["arm64"])

            for binary in version.rglob("*"):
                if binary.is_file() and binary.name != "fixture.txt":
                    self.assertEqual(subprocess.check_output(
                        ["xcrun", "lipo", "-archs", str(binary)], text=True).strip(), "arm64")
                    if shutil.which("arch") and subprocess.check_output(["uname", "-m"], text=True).strip() == "arm64":
                        subprocess.run([str(binary)], check=True)
            self.assertTrue((framework / "Fixture").is_symlink())
            self.assertEqual((version / "Resources/fixture.txt").read_bytes(), b"updater resource")


if __name__ == "__main__":
    unittest.main()
