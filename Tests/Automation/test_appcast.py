"""Feed publication guards, without network or signing credentials."""
import base64
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("appcast", ROOT / "scripts/validate-appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    def test_checked_in_feed_is_metadata_or_a_signed_stable_snapshot(self):
        root = ET.parse(ROOT / "appcast.xml").getroot()
        self.assertEqual(root.tag, "rss")
        self.assertEqual(root.get("version"), "2.0")
        self.assertEqual(root.findtext("./channel/title"), "Cliptate")
        self.assertEqual(root.findtext("./channel/link"),
                         "https://github.com/cliptate/cliptate/releases")
        self.assertTrue(root.findtext("./channel/description"))
        items = root.findall("./channel/item")
        if not items:
            return
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertRegex(item.findtext(appcast.SPARKLE + "version"), r"^\d+(?:\.\d+)*$")
        for key in ["title", "pubDate", "description", appcast.SPARKLE + "shortVersionString",
                    appcast.SPARKLE + "minimumSystemVersion"]:
            self.assertTrue(item.findtext(key), key)
        enclosure = item.find("enclosure")
        self.assertIsNotNone(enclosure)
        self.assertRegex(enclosure.get("url"),
                         r"^https://github\.com/cliptate/cliptate/releases/download/v[^/]+/Cliptate-[^/]+\.dmg$")
        self.assertGreater(int(enclosure.get("length")), 0)
        self.assertEqual(len(base64.b64decode(enclosure.get(appcast.SPARKLE + "edSignature"), validate=True)), 64)

    def test_manual_download_entry_cannot_be_published_as_a_signed_release(self):
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "Cliptate.dmg"
            dmg.write_bytes(b"installer")
            tree = ET.parse(ROOT / "appcast.xml")
            channel = tree.getroot().find("channel")
            item = channel.find("item")
            if item is None:
                item = ET.SubElement(channel, "item")
                ET.SubElement(item, appcast.SPARKLE + "version").text = "23"
                ET.SubElement(item, "link").text = "https://github.com/cliptate/cliptate/releases"
            enclosure = item.find("enclosure")
            if enclosure is not None:
                item.remove(enclosure)
            manual_feed = Path(directory) / "appcast.xml"
            tree.write(manual_feed)
            with self.assertRaisesRegex(ValueError, "enclosure"):
                appcast.validate(manual_feed, dmg, "cliptate/cliptate", "nightly")

    def test_generation_removes_previous_items_and_keeps_sparkle_namespace(self):
        script = (ROOT / "scripts/generate-appcast.sh").read_text()
        preparation = script.split("<<'PY'\n", 1)[1].split("\nPY", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            feed = Path(directory) / "appcast.xml"
            subprocess.run(["python3", "-", str(ROOT / "appcast.xml"), str(feed)],
                           input=preparation, text=True, check=True, capture_output=True)
            root = ET.parse(feed).getroot()
            self.assertEqual(root.findtext("./channel/title"), "Cliptate")
            self.assertEqual(root.findall("./channel/item"), [])
            namespaces = [value for _, value in ET.iterparse(feed, events=["start-ns"])]
            self.assertIn(("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle"), namespaces)

    def test_generation_embeds_notes_in_the_feed(self):
        script = (ROOT / "scripts/generate-appcast.sh").read_text()
        self.assertIn("--embed-release-notes", script)

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
