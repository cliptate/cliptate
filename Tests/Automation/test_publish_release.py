"""Exercise release safety with a fake GitHub CLI; never publish test assets."""

import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[2]
COMMIT = "a" * 40
DMG = "Cliptate.dmg"


def version_notes(tag):
    return f"""# Cliptate {tag}

## Highlights

- Transcribe files from the command line using the app's selected model.

## Changes

- Fix startup waiting when the application is launched in the background.

## Upgrade notes

- Restart Cliptate after replacing the application in Applications.

## Known limitations

- Model weights are downloaded separately on first use.

## Validation

- Offline release automation checks passed.
"""


FAKE_GH = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ["FAKE_GH_STATE"])
s = json.loads(p.read_text())
a = sys.argv[1:]
s["calls"].append(a)
code, output = 0, ""
if a[0] == "api":
    endpoint = next(x for x in a[1:] if x.startswith("repos/"))
    method = a[a.index("--method") + 1] if "--method" in a else "GET"
    if method == "GET" and "/git/ref/" in endpoint:
        code = 0 if s["tag_exists"] else 1
    elif method == "GET" and "/commits/" in endpoint:
        output = s["tag_commit"]
    elif method == "POST":
        s["tag_exists"] = True
    elif method == "PATCH":
        s["tag_moved"] = True
    else:
        code = 99
elif a[:2] == ["release", "view"]:
    if not s["release_exists"]:
        code = 1
    elif a[a.index("--json") + 1] == "assets":
        output = "\n".join(s["assets"])
    elif a[a.index("--json") + 1] == "url":
        output = "https://github.com/cliptate/cliptate/releases/tag/" + a[2]
    else:
        output = '{"id": 1}'
elif a[:2] == ["release", "create"]:
    s["release_exists"] = True
    s["notes"] = Path(a[a.index("--notes-file") + 1]).read_text()
elif a[:2] == ["release", "upload"]:
    code = 1 if s["fail_upload"] else 0
elif a[:2] == ["release", "delete-asset"]:
    s["deleted"].append(a[3])
elif a[:2] == ["release", "edit"]:
    if "--notes-file" in a:
        s["notes"] = Path(a[a.index("--notes-file") + 1]).read_text()
else:
    code = 99
p.write_text(json.dumps(s))
if output:
    print(output)
sys.exit(code)
'''


class PublishReleaseTests(unittest.TestCase):
    def run_release(self, tag="nightly", *, existing=True, fail_upload=False,
                    corrupt=False, tag_commit=COMMIT, signing_status="ad-hoc", appcast=False,
                    wrong_feed=False, notes=True, notes_tag=None, notes_content=None):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            # Use an isolated source checkout so fixtures cannot satisfy a missing document.
            source = work / "source"
            shutil.copytree(ROOT / "scripts", source / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
            notes_directory = source / "docs/release-notes"
            notes_directory.mkdir(parents=True)
            if notes:
                document_tag = notes_tag or tag
                (notes_directory / (quote(document_tag, safe="") + ".md")).write_text(
                    version_notes(document_tag) if notes_content is None else notes_content)
            gh = work / "gh"
            gh.write_text(FAKE_GH)
            gh.chmod(0o755)
            dmg = work / DMG
            dmg.write_bytes(b"test installer")
            digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
            checksum = work / (DMG + ".sha256")
            checksum.write_text(f"{digest}  {DMG}\n")
            if corrupt:
                dmg.write_bytes(b"corrupt installer")
            state = work / "state.json"
            state.write_text(json.dumps({
                "tag_exists": existing, "release_exists": existing,
                "tag_commit": tag_commit, "fail_upload": fail_upload,
                "tag_moved": False, "calls": [], "deleted": [],
                "assets": [DMG, DMG + ".sha256", "Cliptate-old.dmg",
                           "Cliptate-old.dmg.sha256", "release-notes.pdf"],
            }))
            env = {**os.environ, "PATH": f"{work}{os.pathsep}{os.environ['PATH']}",
                   "FAKE_GH_STATE": str(state), "RELEASE_TAG": tag,
                   "BUILT_COMMIT": COMMIT, "GITHUB_REPOSITORY": "cliptate/cliptate",
                   "GITHUB_RUN_ID": "123", "GH_TOKEN": "test-token",
                   "GITHUB_STEP_SUMMARY": str(work / "summary.md"), "SIGNING_STATUS": signing_status}
            if appcast:
                feed = work / "appcast.xml"
                signature = base64.b64encode(b"s" * 64).decode()
                feed_tag = "wrong" if wrong_feed else tag
                feed.write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                  <sparkle:version>23</sparkle:version><sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
                  <enclosure url="https://github.com/cliptate/cliptate/releases/download/{feed_tag}/{DMG}"
                    length="{dmg.stat().st_size}" sparkle:edSignature="{signature}" />
                </item></channel></rss>''')
                env["APPCAST_PATH"] = str(feed)
            result = subprocess.run([str(source / "scripts/publish-release.sh"), str(dmg)],
                                    env=env, text=True, capture_output=True, cwd=work)
            return result, json.loads(state.read_text())

    def test_first_nightly_is_created_as_draft_prerelease(self):
        result, state = self.run_release(existing=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(c for c in state["calls"] if c[:2] == ["release", "create"])
        self.assertIn("--draft", create)
        self.assertIn("--prerelease", create)
        self.assertIn("--latest=false", create)
        self.assertTrue(state["tag_moved"])

    def test_nightly_keeps_current_pair_and_unrelated_assets(self):
        result, state = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["deleted"], ["Cliptate-old.dmg", "Cliptate-old.dmg.sha256"])
        calls = state["calls"]
        upload = next(i for i, c in enumerate(calls) if c[:2] == ["release", "upload"])
        move = next(i for i, c in enumerate(calls) if "PATCH" in c)
        self.assertLess(upload, move)

    def test_failed_upload_preserves_nightly_source_and_skips_cleanup(self):
        result, state = self.run_release(fail_upload=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(state["tag_moved"])
        self.assertEqual(state["deleted"], [])

    def test_corrupt_dmg_is_rejected_before_any_github_call(self):
        result, state = self.run_release(corrupt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["calls"], [])

    def test_version_release_never_moves_tags_or_cleans_assets(self):
        for existing in [False, True]:
            with self.subTest(existing=existing):
                result, state = self.run_release(tag="v1.8.0", existing=existing)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(state["tag_moved"])
                self.assertEqual(state["deleted"], [])
                self.assertFalse(any("/git/" in " ".join(c) for c in state["calls"]))

    def test_version_release_publishes_document_for_new_and_existing_releases(self):
        for existing in [False, True]:
            with self.subTest(existing=existing):
                result, state = self.run_release(tag="v1.8.0", existing=existing)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(version_notes("v1.8.0"), state["notes"])
                self.assertIn("Source:", state["notes"])
                self.assertIn("Build:", state["notes"])

    def test_version_release_requires_its_own_notes_before_any_github_call(self):
        for options in [{"notes": False}, {"notes_tag": "v1.7.0"}, {"notes_content": " \n"},
                        {"notes_content": version_notes("v1.7.0")},
                        {"notes_content": version_notes("v1.8.0").replace("## Changes", "## Other")},
                        {"notes_content": version_notes("v1.8.0").replace(
                            "- Fix startup waiting when the application is launched in the background.",
                            "<!-- Describe changes here. -->")},
                        {"notes_content": version_notes("v1.8.0").replace(
                            "- Fix startup waiting when the application is launched in the background.", "TBD")}]:
            with self.subTest(options=options):
                result, state = self.run_release(tag="v1.8.0", **options)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("release notes", result.stderr.lower())
                self.assertEqual(state["calls"], [])

    def test_nightly_does_not_require_version_notes(self):
        result, state = self.run_release(notes=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Source:", state["notes"])
        self.assertNotIn("## Highlights", state["notes"])

    def test_stable_release_is_explicitly_marked_latest(self):
        result, state = self.run_release(tag="v1.0", signing_status="developer-id-notarized", appcast=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        publish = next(c for c in state["calls"] if c[:2] == ["release", "edit"])
        self.assertIn("--latest=true", publish)

    def test_non_semver_tag_is_preserved_in_title_and_encoded_for_source_lookup(self):
        result, state = self.run_release(tag="preview/中文+1", existing=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(c for c in state["calls"] if c[:2] == ["release", "create"])
        self.assertEqual(create[create.index("--title") + 1], "Cliptate preview/中文+1")
        self.assertIn(version_notes("preview/中文+1"), state["notes"])
        self.assertTrue(any("repos/cliptate/cliptate/commits/preview%2F%E4%B8%AD%E6%96%87%2B1" in c
                            for c in state["calls"]))
        self.assertFalse(state["tag_moved"])

    def test_moved_version_tag_is_rejected_before_upload(self):
        result, state = self.run_release(tag="v1.8.0", tag_commit="b" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[:2] == ["release", "upload"] for c in state["calls"]))

    def test_verified_signed_release_notes_describe_notarization(self):
        result, state = self.run_release(signing_status="developer-id-notarized")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Developer ID signed and Apple-notarized.", state["notes"])
        self.assertNotIn("ad-hoc", state["notes"])

    def test_signed_feed_upload_follows_installer_upload(self):
        result, state = self.run_release(tag="v1.0", signing_status="developer-id-notarized", appcast=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        uploads = [c for c in state["calls"] if c[:2] == ["release", "upload"]]
        self.assertEqual(len(uploads), 2)
        self.assertTrue(any(path.endswith(".dmg") for path in uploads[0]))
        self.assertTrue(any(path.endswith("appcast.xml") for path in uploads[1]))

    def test_wrong_feed_is_rejected_before_github_calls(self):
        result, state = self.run_release(tag="v1.0", signing_status="developer-id-notarized", appcast=True, wrong_feed=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["calls"], [])

    def test_adhoc_release_cannot_publish_an_update_feed(self):
        result, state = self.run_release(tag="v1.0", appcast=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["calls"], [])

    def test_nightly_cannot_publish_its_own_update_feed(self):
        result, state = self.run_release(signing_status="developer-id-notarized", appcast=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["calls"], [])

    def test_unknown_signing_status_is_rejected(self):
        result, state = self.run_release(signing_status="unknown")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["calls"], [])


if __name__ == "__main__":
    unittest.main()
