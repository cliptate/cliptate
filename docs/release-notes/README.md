# Version release notes

Each version release has a detailed document committed at
`docs/release-notes/<tag>.md` before its tag is created. For example, `v1.0`
uses [v1.0.md](v1.0.md). Use the exact tag, including the `v` prefix. Tags containing
slashes or Unicode use a URL-encoded filename (`preview/中文+1` becomes
`preview%2F%E4%B8%AD%E6%96%87%2B1.md`). Nightly is a rolling build and uses generated
installation and build information.

## Prepare a release

1. Compare the intended release commit with the previous version tag. For an
   initial release, describe the included product capabilities and distribution
   changes. Account for user-visible additions, fixes, compatibility changes,
   migration requirements, and known limitations in that range.
2. Write the version document using the structure below. Explain what changes for
   users, which workflows are affected, and any action they need to take. Link to
   relevant usage guides, issues, or commits using absolute URLs so the links
   also work on GitHub Release. Keep unreleased changes out of
   historical version documents.
3. Record the checks actually performed and any validation still outstanding.
   Describe signing/notarization as verified only when packaging confirms it;
   publication adds the package's actual signing status automatically.
4. Run `python3 scripts/release-notes.py v1.1 --check` with the intended tag and
   `python3 -m unittest discover -s Tests/Automation -v`. Review the notes alongside
   the version/build settings, then commit them before creating the version tag.

The first line must be `# Cliptate <tag>`. All five sections below require content.
Use explicit statements when no changes or limitations apply; replace every
TODO/TBD placeholder before tagging. Automated checks verify this structure;
review must verify completeness and accuracy against the release's changes.

```markdown
# Cliptate v1.1

Release date: YYYY-MM-DD (Asia/Shanghai)
Previous version: v1.0

## Highlights

Explain the most useful changes and their effect on users.

## Changes

Describe additions, improvements, and fixes with affected workflows and examples.
Use subheadings when several areas changed.

## Upgrade notes

State supported hardware/macOS, installation steps, data/cache compatibility,
and any required migration or permission changes.

## Known limitations

List remaining issues, workarounds, and relevant distribution restrictions.

## Validation

Record completed checks and distinguish remaining manual or hardware checks.
```

## Publication

The package workflow validates the document before building. Both
`publish-release.sh` and `generate-appcast.sh` read it from the checked-out release
source, independently of the working directory. Missing files, mismatched titles,
empty sections, and TODO/TBD placeholders fail before publication.

GitHub Release uses the Markdown document followed by installation, signing,
source-commit, and Actions-run information. Updating an existing release refreshes
its notes too. Sparkle embeds the document as plain text with source and release
links. The workflow publishes generated assets without writing back to `main`.

Historical documentation may be backfilled on `main` without moving published
tags. Such a backfill does not update an already published GitHub Release or
appcast automatically, and rerunning an old tag continues to use its original
source and workflow.

## Version archive

- [v1.1](v1.1.md) — native CLI, dictation reliability, and app lifecycle improvements.
- [v1.0](v1.0.md) — initial open-source, free direct-download release.
- [Model lifecycle migration](model-lifecycle-migration.md) — engineering migration
  reference; version releases use the documents listed above.
