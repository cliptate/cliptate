"""Verify notarization publication gates without contacting Apple."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TEAM = "FB4W45V73V"
FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ["FAKE_APPLE_STATE"])
s = json.loads(p.read_text())
tool, args = Path(sys.argv[0]).name, sys.argv[1:]
s["calls"].append([tool, *args])
code = 0
if tool == "codesign" and "-dv" in args:
    print(s["signature"], file=sys.stderr)
elif tool == "xcrun" and args[:2] == ["notarytool", "submit"]:
    print(json.dumps({"status": s["status"], "id": "test-submission"}))
    code = s["submit_exit"]
elif tool == "xcrun" and args[:2] == ["notarytool", "log"]:
    Path(args[-1]).write_text(json.dumps({"issues": [{
        "path": "Cliptate.app/Contents/Helpers/cliptate",
        "message": "The signature does not include a secure timestamp.",
    }]}))
elif tool == "xcrun" and args[:2] == ["stapler", "staple"]:
    with open(args[2], "ab") as image:
        image.write(b"stapled-ticket")
elif tool == "xcrun" and args[:2] == ["stapler", "validate"]:
    code = s["validate_exit"]
elif tool == "spctl":
    code = s["gatekeeper_exit"]
p.write_text(json.dumps(s))
sys.exit(code)
'''


class NotarizeDMGTests(unittest.TestCase):
    def run_notarization(self, *, status="Accepted", submit_exit=0,
                         validate_exit=0, gatekeeper_exit=0, developer_id=True,
                         certificate_team=TEAM, timestamp=True):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            for tool in ["xcrun", "codesign", "spctl", "hdiutil"]:
                path = work / tool
                path.write_text(FAKE_TOOL)
                path.chmod(0o755)
            dmg = work / "Cliptate-test.dmg"
            dmg.write_bytes(b"signed image")
            checksum = work / "Cliptate-test.dmg.sha256"
            checksum.write_text("original checksum")
            state = work / "state.json"
            authority = "Developer ID Application: Qi Li" if developer_id else "Apple Development: Qi Li"
            state.write_text(json.dumps({
                "calls": [], "status": status, "submit_exit": submit_exit,
                "validate_exit": validate_exit, "gatekeeper_exit": gatekeeper_exit,
                "signature": f"Authority={authority}\nTeamIdentifier={certificate_team}\n"
                             + ("Timestamp=now\n" if timestamp else ""),
            }))
            outputs = work / "outputs"
            env = {**os.environ, "PATH": f"{work}{os.pathsep}{os.environ['PATH']}",
                   "FAKE_APPLE_STATE": str(state), "RUNNER_TEMP": str(work),
                   "SIGNING_KEYCHAIN": str(work / "test.keychain-db"),
                   "APPLE_TEAM_ID": TEAM, "APPLE_ID": "test@example.invalid",
                   "APPLE_APP_SPECIFIC_PASSWORD": "test-password", "GITHUB_OUTPUT": str(outputs)}
            result = subprocess.run([str(ROOT / "scripts/notarize-dmg.sh"), str(dmg)],
                                    env=env, text=True, capture_output=True)
            return (result, json.loads(state.read_text()), checksum.read_text(),
                    hashlib.sha256(dmg.read_bytes()).hexdigest(),
                    outputs.read_text() if outputs.exists() else "")

    def test_success_checksum_covers_stapled_bytes(self):
        result, state, checksum, digest, outputs = self.run_notarization()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(checksum.split()[0], digest)
        self.assertEqual(checksum.split()[1], "Cliptate-test.dmg")
        self.assertIn("signing-status=developer-id-notarized", outputs)
        self.assertTrue(any(c[:3] == ["xcrun", "stapler", "validate"] for c in state["calls"]))

    def assert_rejected(self, **options):
        result, state, checksum, _, outputs = self.run_notarization(**options)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, "")
        self.assertEqual(checksum, "original checksum")
        return state

    def test_apple_rejection_blocks_publication_even_if_command_exits_zero(self):
        state = self.assert_rejected(status="Invalid")
        self.assertFalse(any(c[:2] == ["xcrun", "stapler"] for c in state["calls"]))

    def test_apple_rejection_reports_the_submission_issues(self):
        result, state, _, _, outputs = self.run_notarization(status="Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, "")
        self.assertTrue(any(c[:3] == ["xcrun", "notarytool", "log"]
                            and c[3] == "test-submission" for c in state["calls"]))
        self.assertIn("Cliptate.app/Contents/Helpers/cliptate", result.stderr)
        self.assertIn("The signature does not include a secure timestamp.", result.stderr)

    def test_pending_submission_is_not_published_after_timeout(self):
        self.assert_rejected(status="In Progress", submit_exit=1)

    def test_development_certificate_is_not_submitted_for_distribution(self):
        state = self.assert_rejected(developer_id=False)
        self.assertFalse(any(c[0] == "xcrun" for c in state["calls"]))

    def test_different_team_certificate_is_not_submitted(self):
        state = self.assert_rejected(certificate_team="OTHERTEAM1")
        self.assertFalse(any(c[0] == "xcrun" for c in state["calls"]))

    def test_missing_secure_timestamp_is_not_submitted(self):
        state = self.assert_rejected(timestamp=False)
        self.assertFalse(any(c[0] == "xcrun" for c in state["calls"]))

    def test_invalid_stapled_ticket_blocks_publication(self):
        self.assert_rejected(validate_exit=1)

    def test_gatekeeper_rejection_blocks_publication(self):
        self.assert_rejected(gatekeeper_exit=1)


if __name__ == "__main__":
    unittest.main()
