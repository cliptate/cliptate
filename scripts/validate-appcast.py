#!/usr/bin/env python3
"""Validate a single-release Sparkle feed before publishing any assets."""
import argparse
import base64
from pathlib import Path
from urllib.parse import quote
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def validate(path: Path, dmg: Path, repository: str, tag: str):
    root = ET.parse(path).getroot()
    items = root.findall("./channel/item")
    if root.tag != "rss" or len(items) != 1:
        raise ValueError("Expected a single-release RSS appcast")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update enclosure")
    expected = f"https://github.com/{repository}/releases/download/{quote(tag, safe='')}/{quote(dmg.name, safe='')}"
    if enclosure.get("url") != expected:
        raise ValueError("Appcast download does not match the release installer")
    if int(enclosure.get("length", "0")) != dmg.stat().st_size:
        raise ValueError("Appcast installer length mismatch")
    signature = base64.b64decode(enclosure.get(SPARKLE + "edSignature", ""), validate=True)
    if len(signature) != 64:
        raise ValueError("Missing or invalid Ed25519 signature")
    version = item.findtext(SPARKLE + "version") or enclosure.get(SPARKLE + "version")
    if not version:
        raise ValueError("Missing Sparkle build version")
    if not item.findtext(SPARKLE + "minimumSystemVersion"):
        raise ValueError("Missing minimum macOS version")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("appcast", type=Path)
    parser.add_argument("dmg", type=Path)
    parser.add_argument("repository")
    parser.add_argument("tag")
    args = parser.parse_args()
    validate(args.appcast, args.dmg, args.repository, args.tag)
