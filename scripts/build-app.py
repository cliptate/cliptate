#!/usr/bin/env python3
"""Compile and assemble Cliptate.app without an Xcode project."""
import argparse
import fcntl
import os
from pathlib import Path
import subprocess

from app_bundle import ROOT, build_app, run, settings


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        values = settings()
        identity = os.environ.get("CODE_SIGN_IDENTITY") or None
        team = os.environ.get("DEVELOPMENT_TEAM") or values.get("CLIPTATE_DEVELOPMENT_TEAM", "")
        if identity is None and values["CONFIGURATION"] == "Debug":
            selected = run("python3", ROOT / "scripts/development-signing.py", team,
                           capture=True).strip().split()
            identity, team = selected[0], selected[1] if len(selected) > 1 else ""
        identity = identity or "-"
        if identity != "-" and not team:
            raise ValueError("DEVELOPMENT_TEAM is required when CODE_SIGN_IDENTITY is set")
        # SwiftPM locks individual commands; hold the bundle transaction across
        # app/CLI builds and resource copying when two bundlers share .build.
        (ROOT / ".build").mkdir(exist_ok=True)
        with (ROOT / ".build/app-bundle.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            build_app(values, args.output, identity)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
