"""Pure Cliptate release-channel decisions shared by build and publication callers.

Callers provide source and publication facts; this module never reads the
environment, opens files, runs commands, or contacts GitHub or Apple.
"""
from urllib.parse import quote


def download_url_prefix(repository: str, tag: str) -> str:
    return f"https://github.com/{repository}/releases/download/{quote(tag, safe='')}/"


def _channel_policy(tag: str, repository: str) -> dict:
    nightly = tag == "nightly"
    return {
        "generate_appcast": not nightly,
        "appcast_path": "" if nightly else "dist/appcast.xml",
        "move_tag": nightly,
        "flags": ["--prerelease", "--latest=false"] if nightly
                 else ["--prerelease=false", "--latest=true"],
        "feed_url": f"https://github.com/{repository}/releases/latest/download/appcast.xml",
    }


def build_plan(ref_type: str, ref_name: str, repository: str,
               run_number: str, run_attempt: str) -> dict:
    """Plan the source, update configuration, and assets for one workflow run."""
    tagged = ref_type == "tag" and ref_name != "nightly"
    tag = ref_name if tagged else "nightly"
    channel = _channel_policy(tag, repository)
    assets = ["Cliptate.dmg", "Cliptate.dmg.sha256"]
    if channel["generate_appcast"]:
        assets.append("appcast.xml")
    return {
        "source_ref": f"refs/tags/{tag}" if tagged else "main",
        "release_tag": tag,
        "generate_appcast": channel["generate_appcast"],
        "appcast_path": channel["appcast_path"],
        "assets": assets,
        "feed_url": channel["feed_url"],
        "build_version": f"{1000 + int(run_number)}.{run_attempt}",
    }


def publication_plan(tag: str, repository: str, signing_status: str,
                     appcast_path: str, release_date: str) -> dict:
    """Plan publication without requiring a feed or notarization for bare assets.

    This preserves direct-script compatibility. The CI caller enforces its
    stronger signing and required-asset checks before invoking publication.
    """
    channel = _channel_policy(tag, repository)
    if appcast_path:
        if not channel["generate_appcast"]:
            raise ValueError("Nightly builds use the latest stable feed and cannot publish their own appcast.")
        if signing_status != "developer-id-notarized":
            raise ValueError("Only notarized Developer ID releases can publish update feeds.")
    descriptions = {
        "developer-id-notarized": "Developer ID signed and Apple-notarized.",
        "ad-hoc": "Release build with ad-hoc signing; not Apple-notarized.",
    }
    if signing_status not in descriptions:
        raise ValueError("Unrecognized signing status.")
    return {
        "move_tag": channel["move_tag"],
        "flags": channel["flags"],
        "title": f"Nightly ({release_date})" if channel["move_tag"] else f"Cliptate {tag}",
        "signing_description": descriptions[signing_status],
        "encoded_tag": quote(tag, safe=""),
        "download_url_prefix": download_url_prefix(repository, tag),
    }
