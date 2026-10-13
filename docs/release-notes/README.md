# Version release notes

Each version release has a concise, complete document committed at
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
2. Use the template below and the concise style of [v1.1](v1.1.md). Describe
   user-visible results and required upgrade actions. Link to usage guides for
   command syntax and technical details, using absolute URLs that work on GitHub.
   Keep the summary around 150–300 words, excluding the commit list; expand it
   when a compatibility change or migration needs explanation.
3. Record the checks actually performed and any validation still outstanding.
   Describe signing/notarization as verified only when packaging confirms it;
   publication adds the package's actual signing status automatically.
4. Add commit titles and links in the collapsed commit section. Use the previous
   tag through the intended source commit (`HEAD` before tagging, the version tag
   after publication). Preserve the actual commit titles and hashes; historical
   notes include only commits in that version's range. Include a compare link.
5. Run `python3 scripts/release-notes.py v1.1 --check` with the intended tag and
   `python3 -m unittest discover -s Tests/Automation -v`. Review the notes alongside
   the version/build settings, then commit them before creating the version tag.

The first line must be `# Cliptate <tag>`. The five summary sections below require content.
Use explicit statements when no changes or limitations apply; replace every
TODO/TBD placeholder before tagging. Automated checks verify this structure;
review must verify completeness and accuracy against the release's changes.
The commit section is included when a previous version exists. Replace the
example version, date, commit entries, and text before using this template.

```markdown
# Cliptate v1.2

Release date: YYYY-MM-DD (Asia/Shanghai)
Previous version: [v1.1](https://github.com/cliptate/cliptate/releases/tag/v1.1)

## Highlights

One sentence naming the main improvements.

## Changes

- **Feature:** Describe the user-visible result and link to its usage guide.
- **Fix:** Describe the affected workflow and the corrected behavior.
- **Improvement:** Describe the practical benefit.

## Upgrade notes

- Requires Apple Silicon and macOS 15+. Update in the app or replace it using the DMG.
- State data/cache compatibility and any required migration or permission action.

## Known limitations

One short paragraph covering relevant limitations and workarounds, or an explicit
statement that no new limitations apply.

## Validation

One short paragraph summarizing completed builds/tests and outstanding manual
checks. Report signing and notarization as verified only after packaging succeeds.

## Commits

<details>
<summary>Commits since v1.1</summary>

- [SHORT_SHA](https://github.com/cliptate/cliptate/commit/FULL_SHA) Actual commit title

[Full comparison](https://github.com/cliptate/cliptate/compare/v1.1...v1.2)

</details>
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

- [v1.2](v1.2.md) — more transcription engines, CLI speech/history workflows, and workspace improvements.
- [v1.1](v1.1.md) — native CLI, dictation reliability, and app lifecycle improvements.
- [v1.0](v1.0.md) — initial open-source, free direct-download release.
- [Model lifecycle migration](model-lifecycle-migration.md) — engineering migration
  reference; version releases use the documents listed above.
