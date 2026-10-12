"""Compare the code identities macOS records for privacy consent."""

import plistlib
import re
import subprocess


def bundle_identifier(app):
    with (app / "Contents/Info.plist").open("rb") as file:
        return plistlib.load(file)["CFBundleIdentifier"]


def designated_requirement(app):
    result = subprocess.run(["codesign", "-d", "-r-", "--verbose=4", str(app)],
                            capture_output=True, text=True, check=True)
    output = result.stdout + result.stderr
    for line in output.splitlines():
        if line.startswith("designated => "):
            return line.removeprefix("designated => ")
    # Ad-hoc code has an implicit requirement tied to this binary's exact hash.
    match = re.search(r"^CDHash=([a-fA-F0-9]{40})$", output, re.MULTILINE)
    if match:
        return f'cdhash H"{match[1]}"'
    raise ValueError(f"Cannot determine the permission identity of {app}.")


def satisfies(app, requirement):
    return subprocess.run(["codesign", "--verify", "-R", "=" + requirement, str(app)],
                          capture_output=True).returncode == 0


def mutually_compatible(previous, current):
    return (satisfies(current, designated_requirement(previous)) and
            satisfies(previous, designated_requirement(current)))
