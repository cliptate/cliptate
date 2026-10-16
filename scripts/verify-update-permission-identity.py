"""Verify update signatures and report the explicit Cliptate bundle-ID transition."""

from pathlib import Path
import subprocess
import sys
import tempfile

from permission_identity import bundle_identifier, designated_requirement, mutually_compatible, satisfies


def verify(previous, current):
    previous_id = bundle_identifier(previous)
    current_id = bundle_identifier(current)
    transition = previous_id == "com.voicepink.voicepinkpro" and current_id == "com.cliptate.app"
    if current_id != "com.cliptate.app" or (previous_id != current_id and not transition):
        raise ValueError("Update identity validation requires production app bundles.")
    for app in [previous, current]:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    if transition:
        for source, target in [(previous, current), (current, previous)]:
            requirement = designated_requirement(source)
            identifier = f'identifier "{bundle_identifier(source)}"'
            if requirement.count(identifier) != 1 or not satisfies(
                target, requirement.replace(identifier, f'identifier "{bundle_identifier(target)}"', 1)
            ):
                raise ValueError("The bundle-ID transition must preserve the release signing authority.")
        return False
    if not mutually_compatible(previous, current):
        raise ValueError("Release signing identity is incompatible with the previous stable app; "
                         "existing macOS privacy permissions would not carry over.")
    return True


def verify_dmg(previous_dmg, current):
    with tempfile.TemporaryDirectory(prefix="cliptate-previous-release-") as directory:
        mount = Path(directory) / "mount"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint",
                        str(mount), str(previous_dmg)], check=True, capture_output=True)
        try:
            return verify(mount / "Cliptate.app", current)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True)


if __name__ == "__main__":
    try:
        if verify_dmg(Path(sys.argv[1]), Path(sys.argv[2])):
            print("Previous stable and new release have compatible privacy identities.")
        else:
            print("Verified the Cliptate bundle-ID transition with the same signing authority. "
                  "Users must grant macOS privacy permissions again for com.cliptate.app.")
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Update permission identity validation failed: {error}")
