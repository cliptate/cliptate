# Cliptate language

These terms complement the application vocabulary in `CONTEXT.md`.

## Language

**Voice completion**:
The final part of a dictation or assistant session, from its final transcript through optional AI processing to text delivery or cancellation. It belongs to the voice session regardless of which page is visible.
_Avoid_: page post-processing, shortcut finalization helper

**CLI request session**:
One authenticated exchange between the Cliptate command and the selected application,
ending in a result, failure, or cancellation. Its progress and terminal outcome
belong to that exchange.
_Avoid_: CLI connection, command job

**Release channel**:
The choice between Cliptate's rolling Nightly prerelease and a stable version release. Both use free direct distribution.
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
