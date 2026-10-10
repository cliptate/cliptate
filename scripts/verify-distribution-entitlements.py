"""Validate the signed app's entitlement plist read from codesign on stdin."""

import plistlib
import sys


try:
    entitlements = plistlib.loads(sys.stdin.buffer.read())
except (plistlib.InvalidFileException, ValueError):
    sys.exit("Cannot read the signed application's entitlements.")
if not isinstance(entitlements, dict):
    sys.exit("Signed application entitlements must be a dictionary.")
if entitlements.get("com.apple.security.get-task-allow", False):
    sys.exit("Distribution app must not enable com.apple.security.get-task-allow.")
