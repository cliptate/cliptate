"""Release executables retain runtime linkage and dSYMs, without internal symbols."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from app_bundle import prepare_release_binary


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Requires macOS build tools")
class ReleaseBinaryTests(unittest.TestCase):
    def test_release_package_policy_enables_the_actual_linker_optimizer(self):
        manifest = json.loads(subprocess.check_output(
            ["swift", "package", "--package-path", str(ROOT), "dump-package"], text=True))
        target = next(target for target in manifest["targets"] if target["name"] == "Cliptate")
        flags = []
        for setting in target.get("settings", []):
            if (setting["tool"] == "linker"
                    and setting.get("condition", {}).get("config", "release") == "release"):
                flags.extend(setting["kind"].get("unsafeFlags", {}).get("_0", []))
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "probe.swift"
            source.write_text('print("release link optimizer probe")\n')
            driver = subprocess.run(["xcrun", "swiftc", "-###", str(source), *flags,
                                     "-o", str(Path(directory) / "probe")],
                                    capture_output=True, text=True, check=True)
            # Inspect the underlying linker plan, rather than matching a literal
            # manifest flag: swiftc must translate policy into optimized linking.
            self.assertRegex(driver.stdout + driver.stderr, r"(?:\s|\")-O[1-9](?:\s|\")")

    def test_internal_globals_are_removed_without_breaking_execution_or_debug_symbols(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "fixture.c"
            source.write_text(
                "int cliptate_internal_packaging_regression(void) { return 0; }\n"
                "int main(void) { return cliptate_internal_packaging_regression(); }\n")
            binary = root / "fixture"
            object_file = root / "fixture.o"
            symbols = root / "fixture.dSYM"
            subprocess.run(["xcrun", "clang", "-g", "-c", str(source), "-o", str(object_file)], check=True)
            subprocess.run(["xcrun", "clang", str(object_file), "-o", str(binary)], check=True)
            before = subprocess.check_output(["nm", "-gj", str(binary)], text=True)
            self.assertIn("_cliptate_internal_packaging_regression", before)

            prepare_release_binary(binary, symbols)

            after = subprocess.check_output(["nm", "-gj", str(binary)], text=True)
            self.assertNotIn("_cliptate_internal_packaging_regression", after)
            self.assertTrue((symbols / "Contents/Resources/DWARF/fixture").is_file())
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
