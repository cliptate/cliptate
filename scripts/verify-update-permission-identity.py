"""Reject a release whose signing requirements break existing privacy consent."""

from pathlib import Path
import subprocess
import sys
import tempfile

from permission_identity import bundle_identifier, mutually_compatible


def verify(previous, current):
    for app in [previous, current]:
        if bundle_identifier(app) != "com.voicepink.voicepinkpro":
            raise ValueError("Update identity validation requires production app bundles.")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    if not mutually_compatible(previous, current):
        raise ValueError("Release signing identity is incompatible with the previous stable app; "
                         "existing macOS privacy permissions would not carry over.")


def verify_dmg(previous_dmg, current):
    with tempfile.TemporaryDirectory(prefix="cliptate-previous-release-") as directory:
        mount = Path(directory) / "mount"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint",
                        str(mount), str(previous_dmg)], check=True, capture_output=True)
        try:
            verify(mount / "Cliptate.app", current)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True)


if __name__ == "__main__":
    try:
        verify_dmg(Path(sys.argv[1]), Path(sys.argv[2]))
        print("Previous stable and new release have compatible privacy identities.")
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Update permission identity validation failed: {error}")
