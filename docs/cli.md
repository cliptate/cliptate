# Cliptate CLI

The CLI is included in the GitHub/direct-download macOS app. It starts Cliptate
in the background when necessary and uses the application's current model,
language, segmentation, alignment, and custom dictionary. Transcriptions do not
create projects or transcript-history entries. App Store builds do not include
the CLI or start its listener.

## Install

Open Settings → Command Line and copy the installation command into Terminal.
It creates `~/.local/bin/cliptate` as a symlink to the helper inside the app bundle,
without administrator privileges. An existing command is never overwritten.
Move the app to its final location before installing the link.

Add this line to your shell configuration (usually `~/.zshrc`):

```sh
export PATH="$HOME/.local/bin:$PATH"
```

The settings panel also provides an uninstall command that removes only a symlink
pointing to that app's helper. After an app upgrade, restart Cliptate before using
the new CLI. `cliptate --version` prints the app version and protocol version.

For development:

```sh
CLIPTATE_APP_STORE=NO ./scripts/build-and-run.sh build
.build/xcode/Build/Products/Debug/Cliptate.app/Contents/Helpers/cliptate --help
swift build --product cliptate
CLIPTATE_APP=/path/to/Cliptate.app swift run cliptate dictionary list
```

`CLIPTATE_APP` selects a particular app bundle; otherwise the embedded helper uses
its own bundle, and a standalone SwiftPM CLI looks up the installed app.

## Transcribe files

```sh
cliptate transcribe interview.mp3
cliptate transcribe interview.mp4 --format json | jq '.files[].segments[].text'
cliptate transcribe interview.mp3 --format srt --output interview.srt
cliptate transcribe a.wav b.mp4 --format vtt --output-dir subtitles
cliptate transcribe recording.wav --language zh --no-dictionary
cliptate transcribe recording.wav --model qwen3-asr-0.6b-8bit --download
cliptate transcribe -- -recording.wav
```

Use the `ModelVariant` raw model identifier with `--model`. `--language` accepts
the application's language codes, including `auto`. Overrides apply only to the
command and never change saved settings. Missing required models are reported
as errors unless `--download` is present. Download progress goes to stderr.

Output formats are `text` (default, plain transcript), `json`, `srt`, `vtt`, and
`markdown`. Results go to stdout, while errors and progress go to stderr.
Multiple inputs run sequentially. Text and Markdown outputs have filename
headings; JSON always has a `files` array. Multiple SRT/VTT inputs require
`--output-dir`, which writes separate files. `--output` is for one input only.
`--output-dir` also works with other formats, producing one file per input.

Output files must not exist unless `--overwrite` is supplied. Input files cannot
be overwritten, and colliding output basenames are rejected before transcription.
The app uses its existing mono audio pipeline and includes speaker IDs when the
configured pipeline produces them; there are no separate-channel or speaker-name
flags in this version. Only one CLI transcription runs at a time in the app.

JSON example:

```json
{
  "files": [
    {
      "file": "/path/to/interview.wav",
      "model": "model-id",
      "duration": 1.42,
      "segments": [
        {"id": "segment-id", "text": "Hello.", "start": 0, "end": 1.42, "speakerId": 0}
      ]
    },
    {"file": "/path/to/missing.wav", "segments": [], "error": "File not found"}
  ]
}
```

`model`, `duration`, `speakerId`, and `error` are present when available. Segment
times and duration are in seconds. Failures are also printed to stderr. A failed
input does not prevent remaining inputs from running. Ctrl+C or SIGTERM closes
the connection, cancels the active app request cooperatively, and stops later
inputs. Already emitted text and saved files remain available.

Exit status: `0` success; `1` execution/file failure; `2` invalid arguments;
`130` interrupted. CLI startup is limited to 30 seconds; transcription has no
fixed timeout.

## Manage the existing dictionary

```sh
cliptate dictionary list
cliptate dictionary add "Cliptate" "Ada Lovelace"
cliptate dictionary remove "Ada Lovelace"
cliptate dictionary import words.txt
cliptate dictionary import words.json
cliptate dictionary export > words.json
```

List, export, and successful mutations return the current JSON string array.
Import accepts UTF-8 text with one word/phrase per line, or a JSON string array.
Imports append entries and preserve the existing dictionary. The application's
normalization trims entries, drops blanks, and deduplicates case and diacritics
while retaining the first spelling and order. Remove uses the same comparison.
Mutations return only after configuration persistence succeeds. An open dictionary
editor updates to reflect CLI changes. These commands manage recognition vocabulary.

## Local transport and distribution

The direct app listens only on `127.0.0.1`, on port `49152 + uid % 16000`. The CLI
opens a launch URL in the selected app to register a one-use, 60-second credential.
Both peers authenticate using separate HMAC-SHA256 proofs before exchanging a
length-prefixed JSON request. Unauthenticated connections expire after five
seconds; frames are limited to 16 MiB. No filesystem paths or dictionary contents
are placed in the launch URL. File access is passed using an implicit bookmark;
the CLI itself reads dictionary imports and writes output files.

GitHub/direct builds run without App Sandbox, as explicitly selected by
`CLIPTATE_APP_STORE=NO`. App Store builds retain their sandbox and capability policy.
Direct builds copy missing configuration, presets, and history from the previous
sandbox container once, retain originals, and preserve existing direct-build data.
The helper is a native Xcode target, signed before embedding, and covered by the
existing app signature/notarization checks. The production app bundle ID is unchanged.
