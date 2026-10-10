#!/usr/bin/env python3
"""Copy upstream root license/notice files for the locked SwiftPM graph."""

import argparse
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify without writing files")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    pins = json.loads((root / "Package.resolved").read_text())["pins"]
    checkout_root = root / ".build/checkouts"
    destination = root / "docs/legal/dependencies"
    checkouts = {p.name.lower(): p for p in checkout_root.iterdir() if p.is_dir()}
    rows = []
    expected = {}

    for pin in pins:
        identity = pin["identity"]
        checkout = checkouts.get(identity)
        if checkout is None:
            raise SystemExit(f"Missing {identity} checkout; run swift package resolve first")
        revision = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
        ).strip()
        if revision != pin["state"]["revision"]:
            raise SystemExit(f"{identity} checkout differs from Package.resolved")
        notices = sorted(
            p for p in checkout.iterdir()
            if p.is_file() and p.name.upper().startswith(("LICENSE", "NOTICE", "COPYING"))
        )
        if not notices:
            raise SystemExit(f"No root license/notice found for {identity}; inspect upstream")
        for notice in notices:
            expected[destination / identity / notice.name] = notice.read_bytes()
        version = pin["state"].get("version", revision[:12])
        links = ", ".join(f"[{p.name}]({identity}/{p.name})" for p in notices)
        rows.append(f"| `{identity}` | `{version}` | {links} |")

    index = (
        "# Resolved dependency notices\n\n"
        "Copied from the exact revisions in the root `Package.resolved`. Original notices\n"
        "remain unmodified. Binary components have additional notices in `../binary-dependencies`.\n"
        "Regenerate with `python3 scripts/update-dependency-notices.py` after resolving updates.\n\n"
        "| Package | Selected version/revision | Notice copies |\n"
        "| --- | --- | --- |\n" + "\n".join(rows) + "\n"
    )
    expected[destination / "README.md"] = index.encode()
    for path, contents in expected.items():
        if args.check:
            if not path.exists() or path.read_bytes() != contents:
                raise SystemExit(f"Outdated notice: {path.relative_to(root)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
    print(f"{'Verified' if args.check else 'Copied'} notices for {len(pins)} locked packages")


if __name__ == "__main__":
    main()
