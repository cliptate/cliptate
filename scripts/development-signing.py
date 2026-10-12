"""Select stable Apple Development signing for local builds when available."""

import re
import subprocess
import sys


def select_identity(output, team=""):
    identities = re.findall(
        r'\b([A-F0-9]{40}) "Apple Development: .+ \(([A-Z0-9]{10})\)"', output)
    if team:
        identities = [identity for identity in identities if identity[1] == team]
    if len(identities) > 1:
        raise ValueError(
            "Multiple Apple Development signing identities are available. "
            "Set CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM explicitly.")
    return identities[0] if identities else ("-", team)


if __name__ == "__main__":
    try:
        result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                                capture_output=True, text=True, check=True)
        print(" ".join(select_identity(result.stdout, sys.argv[1] if len(sys.argv) > 1 else "")))
    except ValueError as error:
        sys.exit(str(error))
    except (OSError, subprocess.CalledProcessError):
        # Public source builds can still run without an Apple signing certificate.
        print("- " + (sys.argv[1] if len(sys.argv) > 1 else ""))
