#!/usr/bin/env python3
"""Adapt release-channel decisions to JSON, shell data, and GitHub settings."""
import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys

from release_policy import build_plan, download_url_prefix, publication_plan


def emit_field(plan: dict, field: str):
    value = plan[field]
    if isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, list):
        print("\n".join(value))
    else:
        print(value)


def github_lines(values: dict) -> str:
    lines = []
    for key, value in values.items():
        if isinstance(value, bool):
            value = "true" if value else "false"
        if "\n" in str(value) or "\r" in str(value):
            raise ValueError("GitHub settings must be single-line values.")
        lines.append(f"{key}={value}\n")
    return "".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="Plan a workflow run from GitHub source facts")
    build.add_argument("--format", choices=["json", "github"], default="json")
    commands.add_parser("configure", help="Validate signing configuration and append build settings")
    publish = commands.add_parser("publication", help="Plan publication from release facts")
    fields = ["move_tag", "flags", "title", "signing_description", "encoded_tag", "download_url_prefix"]
    publish.add_argument("--field", choices=fields)
    field = commands.add_parser("field", help="Read a publication plan field from JSON on stdin")
    field.add_argument("name", choices=fields)
    prefix = commands.add_parser("download-prefix", help="Installer URL prefix for appcast generation")
    prefix.add_argument("repository")
    prefix.add_argument("tag")
    args = parser.parse_args()
    env = os.environ
    if args.command == "field":
        emit_field(json.load(sys.stdin), args.name)
    elif args.command == "download-prefix":
        print(download_url_prefix(args.repository, args.tag))
    elif args.command == "publication":
        plan = publication_plan(
            env["RELEASE_TAG"], env["GITHUB_REPOSITORY"],
            env.get("SIGNING_STATUS") or "ad-hoc", env.get("APPCAST_PATH", ""),
            datetime.now(timezone.utc).date().isoformat(),
        )
        if args.field:
            emit_field(plan, args.field)
        else:
            print(json.dumps(plan))
    elif args.command == "build":
        plan = build_plan(env["GITHUB_REF_TYPE"], env["GITHUB_REF_NAME"],
                          env["GITHUB_REPOSITORY"], env["GITHUB_RUN_NUMBER"], env["GITHUB_RUN_ATTEMPT"])
        if args.format == "github":
            print(github_lines({"release-tag": plan["release_tag"],
                                "generate-appcast": plan["generate_appcast"],
                                "appcast-path": plan["appcast_path"]}), end="")
        else:
            print(json.dumps(plan))
    elif args.command == "configure":
        # Use the release tag selected by the build caller, not a second event classification.
        plan = build_plan("tag", env["RELEASE_TAG"], env["GITHUB_REPOSITORY"],
                          env["GITHUB_RUN_NUMBER"], env["GITHUB_RUN_ATTEMPT"])
        if plan["generate_appcast"] and not env.get("SPARKLE_PRIVATE_KEY"):
            raise ValueError("Configure secrets.SPARKLE_PRIVATE_KEY with the exported signing key")
        key = env.get("SPARKLE_PUBLIC_KEY", "")
        try:
            valid_key = len(base64.b64decode(key, validate=True)) == 32
        except ValueError:
            valid_key = False
        if not valid_key:
            raise ValueError("Configure vars.SPARKLE_PUBLIC_KEY with a 32-byte public Ed25519 key")
        version = plan["build_version"]
        if env.get("ACT") == "true":
            version = env.get("CLIPTATE_LOCAL_BUILD_VERSION", "")
            if not re.fullmatch(r"[0-9]+\.[0-9]+", version):
                raise ValueError("Local packaging requires a numeric CLIPTATE_LOCAL_BUILD_VERSION")
        settings = github_lines({"CLIPTATE_SPARKLE_PUBLIC_KEY": key,
                                 "CLIPTATE_UPDATE_FEED_URL": plan["feed_url"],
                                 "CURRENT_PROJECT_VERSION": version})
        with Path(env["GITHUB_ENV"]).open("a") as output:
            output.write(settings)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError) as error:
        raise SystemExit(str(error)) from None
