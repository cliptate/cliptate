#!/usr/bin/env python3
"""Run the existing Actions on the local Apple Silicon Mac."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "cliptate/cliptate"


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def verify_source(tag, commit=None):
    """Require publication to describe exactly the clean, pushed source being built."""
    head = output("git", "rev-parse", "HEAD")
    if commit and head != commit:
        raise ValueError("HEAD changed during packaging; rebuild before publishing.")
    if output("git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Local publication requires a clean checkout, including untracked files.")
    ref = "main" if tag == "nightly" else tag
    if tag != "nightly" and output("git", "rev-parse", f"refs/tags/{tag}^{{commit}}") != head:
        raise ValueError("The version tag must identify HEAD.")
    remote = output("gh", "api", f"repos/{REPOSITORY}/commits/{quote(ref, safe='')}", "--jq", ".sha")
    if remote != head:
        raise ValueError(f"HEAD must match the published {ref} source in {REPOSITORY}.")
    return head


@contextmanager
def local_lock():
    # act ignores workflow concurrency; also avoid overlapping local keychain changes.
    directory = ROOT / ".build"
    directory.mkdir(exist_ok=True)
    with (directory / "local-actions.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another local Action is running in this checkout.") from None
        yield


def configuration_file(name, default):
    path = Path(os.environ.get(name) or default).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"Set {name} to an existing file outside Git. See docs/local-actions.md.")
    if path.is_relative_to(ROOT):
        raise ValueError(f"{name} must be outside this checkout.")
    return str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task", choices=["ci", "package", "release", "list", "plan", "verify-source"])
    parser.add_argument("--tag", default=os.environ.get("TAG") or "nightly")
    parser.add_argument("--commit")
    args = parser.parse_args()
    if args.task == "verify-source":
        verify_source(args.tag, args.commit)
        return
    if not shutil.which("act"):
        raise ValueError("Install act first: brew install act")
    if output("uname", "-s") != "Darwin" or output("uname", "-m") != "arm64":
        raise ValueError("These Actions require an Apple Silicon Mac.")
    developer = os.environ.get("DEVELOPER_DIR") or output("xcode-select", "-p")
    if not (Path(developer) / "usr/bin/xcodebuild").is_file():
        candidate = Path("/Applications/Xcode.app/Contents/Developer")
        if not candidate.is_dir():
            raise ValueError("Set DEVELOPER_DIR to a full Xcode installation.")
        developer = str(candidate)
    environment = os.environ.copy()
    # Keep authentication in the environment, never in command arguments or output.
    if not environment.get("GITHUB_TOKEN"):
        token = environment.get("GH_TOKEN")
        if not token and shutil.which("gh"):
            result = subprocess.run(["gh", "auth", "token"], text=True, capture_output=True)
            if result.returncode == 0:
                token = result.stdout.strip()
        if token:
            environment["GITHUB_TOKEN"] = token
    if not environment.get("GH_TOKEN") and environment.get("GITHUB_TOKEN"):
        environment["GH_TOKEN"] = environment["GITHUB_TOKEN"]
    os.environ.update({key: environment[key] for key in ["GH_TOKEN", "GITHUB_TOKEN"] if key in environment})
    publishing = args.task == "release"
    packaging = args.task in ["package", "release"]
    if publishing:
        if not shutil.which("gh"):
            raise ValueError("Install and authenticate GitHub CLI before publishing: brew install gh")
        verify_source(args.tag)
    if args.tag != "nightly":
        output("git", "check-ref-format", f"refs/tags/{args.tag}")
    with local_lock(), tempfile.TemporaryDirectory(prefix="cliptate-act-") as temp:
        event = Path(temp) / "event.json"
        event.write_text(json.dumps({"act": True, "local_publish": publishing,
                                    "ref": "refs/heads/main" if args.tag == "nightly" else f"refs/tags/{args.tag}"}))
        command = ["act", "workflow_dispatch", "--bind", "--eventpath", str(event),
                   "--platform", "macos-26=-self-hosted", "--platform", "ubuntu-24.04=-self-hosted",
                   "--action-offline-mode",
                   "--env", f"CLIPTATE_LOCAL_WORKSPACE={ROOT}",
                   "--env-file", "/dev/null", "--env", f"DEVELOPER_DIR={developer}"]
        if packaging:
            secrets = configuration_file("ACT_SECRETS_FILE", "~/.config/cliptate/act.secrets")
            variables = configuration_file("ACT_VARS_FILE", "~/.config/cliptate/act.vars")
            command += ["--secret-file", secrets, "--var-file", variables]
            version = os.environ.get("BUILD_VERSION")
            if not version:
                # Use the current cloud run's major number; the next cloud run remains newer.
                number = output("gh", "api", f"repos/{REPOSITORY}/actions/workflows/package.yml/runs?per_page=1",
                                "--jq", ".workflow_runs[0].run_number // 0")
                version = f"{1000 + int(number)}.{int(time.time())}"
            if not re.fullmatch(r"[0-9]+\.[0-9]+", version):
                raise ValueError("BUILD_VERSION must be two numeric components, for example 1042.1770000000.")
            command += ["--env", f"CLIPTATE_LOCAL_BUILD_VERSION={version}"]
        else:
            command += ["--secret-file", "/dev/null", "--var-file", "/dev/null"]
        if environment.get("GITHUB_TOKEN"):
            command += ["--secret", "GITHUB_TOKEN"]
        workflows = ["ci.yml", "package.yml"] if args.task == "list" else [
            "ci.yml" if args.task == "ci" else "package.yml"]
        for workflow in workflows:
            run = command + ["--workflows", str(ROOT / ".github/workflows" / workflow)]
            if args.task == "list":
                run += ["--list"]
            elif args.task == "plan":
                # act --dryrun still executes run steps in host mode. Listing is safe.
                run += ["--list"]
            else:
                run += ["--job", "macos" if args.task == "ci" else "release" if publishing else "build"]
            subprocess.run(run, cwd=ROOT, env=environment, check=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
