"""Feed publication guards, without network or signing credentials."""
import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("appcast", ROOT / "scripts/validate-appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    def check(self, *, tag="v1.8.0", url=None, length=9, signature=None, version="23", minimum="15.0"):
        with tempfile.TemporaryDirectory() as temp:
            dmg = Path(temp) / "Cliptate-1.8-23-macOS-arm64.dmg"
            dmg.write_bytes(b"installer")
            feed = Path(temp) / "appcast.xml"
            url = url or f"https://github.com/cliptate/cliptate/releases/download/{tag}/{dmg.name}"
            signature = signature if signature is not None else base64.b64encode(b"s" * 64).decode()
            feed.write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
              <sparkle:version>{version}</sparkle:version><sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
              <enclosure url="{url}" length="{length}" sparkle:edSignature="{signature}" />
            </item></channel></rss>''')
            appcast.validate(feed, dmg, "cliptate/cliptate", tag)

    def test_stable_and_nightly(self):
        self.check()
        self.check(tag="nightly")

    def test_rejects_wrong_release_or_installer(self):
        with self.assertRaises(ValueError):
            self.check(url="https://example.com/installer.dmg")

    def test_rejects_stale_length(self):
        with self.assertRaises(ValueError):
            self.check(length=8)

    def test_rejects_missing_signature_version_or_system_requirement(self):
        for options in [{"signature": ""}, {"signature": "bad"}, {"version": ""}, {"minimum": ""}]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.check(**options)
