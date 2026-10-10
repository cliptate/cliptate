#!/usr/bin/env python3
"""Read and validate the version document shared by GitHub and Sparkle releases."""
import argparse
from pathlib import Path
import re
from urllib.parse import quote


SECTIONS = ("Highlights", "Changes", "Upgrade notes", "Known limitations", "Validation")


def read_notes(root: Path, tag: str) -> str:
    if tag == "nightly":
        return ""
    # Encode tags as one filename, including tags containing slashes or Unicode.
    path = root / "docs/release-notes" / (quote(tag, safe="") + ".md")
    if not path.is_file():
        raise ValueError(f"Missing release notes: {path}. Write the version document before tagging.")
    notes = path.read_text(encoding="utf-8")
    content = re.sub(r"<!--.*?-->", "", notes, flags=re.DOTALL).strip()
    if not content or content.splitlines()[0] != f"# Cliptate {tag}":
        raise ValueError(f"Invalid release notes: {path} must start with '# Cliptate {tag}'.")
    if re.search(r"\b(?:TODO|TBD)\b", content, flags=re.IGNORECASE):
        raise ValueError(f"Incomplete release notes: {path} still contains TODO/TBD placeholders.")
    headings = list(re.finditer(r"^## (.+)$", content, flags=re.MULTILINE))
    sections = {}
    for index, heading in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(content)
        sections[heading.group(1)] = content[heading.end():end].strip()
    for section in SECTIONS:
        if not sections.get(section, "").strip(" \n\r\t-*#"):
            raise ValueError(f"Incomplete release notes: {path} requires content under '## {section}'.")
    return notes.rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--check", action="store_true", help="Validate without printing the document")
    args = parser.parse_args()
    try:
        notes = read_notes(Path(__file__).resolve().parents[1], args.tag)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"Release notes error: {error}\n")
    if not args.check:
        print(notes, end="")


if __name__ == "__main__":
    main()
