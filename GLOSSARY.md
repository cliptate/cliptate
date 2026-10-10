# Cliptate release language

Release terms complement the application vocabulary in `CONTEXT.md`.

## Language

**Release channel**:
The choice between Cliptate's rolling Nightly prerelease and a stable version release. This is distinct from App Store versus direct-download distribution.
_Avoid_: distribution channel, build flavor

**Release-channel policy**:
The rules connecting a Cliptate Release channel to its source, update feed, build numbering, release assets, and publication status.
_Avoid_: release workflow, packaging process

**Nightly release**:
Cliptate's rolling prerelease built from main, with a movable reserved tag and a current installer/checksum pair. Its installations check the latest stable update feed.
_Avoid_: nightly update channel, daily stable release

**Stable release**:
A Cliptate version release whose tag identifies a fixed source commit and whose publication is marked Latest.
_Avoid_: main release, tagged Nightly
