"""Keep local launches from replacing an installed app's macOS privacy identity."""

import os
from pathlib import Path
import plistlib
import subprocess
import sys

from permission_identity import bundle_identifier, mutually_compatible


def main():
    if os.environ.get("CLIPTATE_ALLOW_PERMISSION_RESET") == "YES":
        return
    app = Path(sys.argv[1])
    installed_override = os.environ.get("CLIPTATE_INSTALLED_APP")
    installed_apps = ([Path(installed_override)] if installed_override else
                      [directory / name
                       for directory in [Path("/Applications"), Path.home() / "Applications"]
                       for name in ["Cliptate.app", "Cliptate Dev.app"]])
    for installed in installed_apps:
        if not installed.exists() or installed.resolve() == app.resolve():
            continue
        if bundle_identifier(installed) != bundle_identifier(app):
            continue
        # Check both directions: switching back must preserve local grants too.
        if mutually_compatible(installed, app):
            continue
        sys.exit(
            f"Refusing to launch {app}: its signing identity is incompatible with "
            f"{installed}. Running both with the same bundle ID can invalidate "
            "microphone, Accessibility, and screen-recording permissions. "
            "Build with the compatible signing identity described in docs/development.md. "
            "For deliberate permission-reset testing only, set "
            "CLIPTATE_ALLOW_PERMISSION_RESET=YES."
        )


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, ValueError, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        sys.exit(f"Cannot verify development permission identity: {error}")
