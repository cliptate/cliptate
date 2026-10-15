# Cliptate CLI

[Agent skills](https://github.com/cliptate/skills)

The CLI is included in the GitHub/direct-download macOS app. It starts Cliptate
in the background when necessary and uses the application's current model,
language, segmentation, alignment, and custom dictionary. Transcriptions do not
create projects or transcript-history entries. App Store builds do not include
the CLI or start its listener.

Run `cliptate --help` for the complete command reference, including input and output
rules, the JSON structure, dictionary behavior, environment variables, exit codes,
and examples. The same reference is available with `cliptate transcribe --help`,
`cliptate tts --help`, `cliptate dictionary --help`, and `cliptate history --help`,
without launching the app.

For AI agents and scripts, prefer `--format json`, capture stdout separately from
stderr, and inspect both the exit status and each `files[].error`. Batch JSON is
emitted after all inputs finish; exit status `1` may still include successful results,
while setup failures can produce no JSON. After interruption, stdout JSON contains
completed inputs and omits the cancelled input. Transcription inputs must be local file paths;
transcription does not accept stdin (TTS accepts `--text-file -`). Pass option
values as separate arguments
(`--format json`, not `--format=json`).

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
".build/app/Build/Products/Debug/Cliptate Dev.app/Contents/Helpers/cliptate" --help
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
flags in this version. Only one CLI transcription or speech-generation request runs at a time in the app.

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
`130` interrupted. After application launch, connection retries have a 30-second
window; an in-flight handshake is limited to two seconds. Transcription has no
fixed timeout. Requests are not retried after authentication, because a lost
response does not imply that a dictionary mutation failed to commit.

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

## Query history and learn dictionary vocabulary

```sh
cliptate history list --corrections-only --limit 50
cliptate history show 00000000-0000-0000-0000-000000000001
cliptate history corrections --source fileTranscription --since 2026-10-01T00:00:00Z
cliptate history corrections --search "Cliptate" > correction-evidence.json
cliptate history corrections --session 00000000-0000-0000-0000-000000000001
cliptate dictionary list > current-dictionary.json
# After an AI analyzes the evidence and selects correct recognition vocabulary:
cliptate dictionary add "Cliptate" "SwiftUI"
cliptate dictionary import selected-terms.json
```

History commands always return JSON (`--format json` is accepted). The shape is
`{ "schemaVersion": 1, "sessions": [], "lines": [], "corrections": [], "nextCursor": "..." }`;
`nextCursor` is omitted on the last page. `list` returns compact session summaries
with ID, source, dates, model/language, line/correction counts, and a 160-character
preview. `show` returns one summary and pages transcript lines followed by correction
records. `corrections` returns correction evidence directly. No recordings, audio
paths, security bookmarks, word timing, or internal editing state are exported.

`list` and `corrections` accept `--source voiceDictation|fileTranscription|ttsSynthesis`,
`--session UUID`, `--since ISO-8601`, `--until ISO-8601`, and `--search TEXT`.
`list --corrections-only` selects sessions with correction evidence. Time bounds are
inclusive and must include a timezone; output dates are UTC ISO-8601 with milliseconds.
Time filters/order use session start for `list`, correction time for `corrections`.
Search covers transcript/filename/pairs for `list`, and pair/context/filename for
`corrections`. `show` accepts only `--limit`, `--cursor`, and `--format json` after its ID.

All three commands accept `--limit 1..200` (default 50) and `--cursor TOKEN`.
Follow `nextCursor` with the same command and filters until it is absent. Changing
filters rejects the cursor; changing the limit is permitted. List/correction
pagination uses time and stable IDs, so newly inserted newer entries do not move
older pages. Show cursors bind to the text snapshot: if the session changes while
paging, restart without a cursor. Responses also have an 8 MiB byte budget and may
contain fewer entries than the count limit. Evidence is never silently truncated;
an individual record larger than the byte budget produces an explicit error.
A missing/expired `show` ID fails with exit status 1; empty list/correction queries
succeed with empty arrays. Invalid arguments return exit status 2.

AI Cut saves only validated word/phrase substitutions that actually changed text,
from both single-file and batch correction. Each record contains `id`, `batchID`,
`sessionID`, `relatedSessionIDs`, `recordedAt`, `kind`, `status`, optional
`statusChangedAt`, `original`, `corrected`, before/after context, target segment ID,
timestamp, and AI provider/model/language. AI-enhanced dictation saves before/after
whole text (`kind: "dictation"`), rather than inventing word pairs. When a shortcut
combines multiple recordings, one event carries all captured originating session
IDs and is emitted once by `corrections`. Assistant answers are not correction records.

`applied` means the edit was applied at that time; it is historical evidence,
not user approval or a guarantee that the present text still contains it.
Restore Original marks applicable evidence `reverted`; new transcription marks
older revision evidence `superseded`. Ordinary edits, translations, deletions, and
app restarts preserve the audit text and provenance. Restore Original and its
baseline now survive history restoration. Old sessions remain readable and have
no fabricated correction records. The History detail page displays these records,
and its dictionary analysis prioritizes applied correction evidence.

An external AI can page through `history corrections`, read `dictionary list`,
analyze proper nouns/technical vocabulary in corrected context, and write selected
terms using the existing `dictionary add/import` commands. Filter out reverted or
superseded evidence; inspect whole-text dictation rewrites rather than treating
style/grammar changes as vocabulary. Deduplicate evidence by event ID, and terms
with the dictionary's normal comparison. Recognition vocabulary remains a string
array, not an incorrect-to-correct replacement map. History queries make no AI calls;
the external agent owns analysis and can automate that workflow.

Correction records follow their parent sessions' deletion and retention:
dictation 24 hours, files/TTS 30 days. Analyze dictation before expiry if it is to
contribute vocabulary. Production and development history/dictionaries remain
separate. Reads use the existing authenticated app service and stay available
while CLI inference is running. CLI transcription/TTS still do not create history.

## Local transport and distribution

The direct app listens only on `127.0.0.1`, on port `49152 + uid % 16000`. The CLI
opens a launch URL in the selected app to register a one-use, 60-second credential.
Both peers authenticate using separate HMAC-SHA256 proofs before exchanging a
length-prefixed JSON request. Unauthenticated connections expire after five
seconds; frames are limited to 16 MiB. Progress is sent before the terminal result
or failure, and callbacks after completion are ignored. Cancelled inference
keeps its admission slot until its work exits. No filesystem paths or dictionary
contents are placed in the launch URL. File access is passed using an implicit bookmark;
the CLI itself reads dictionary imports and writes output files.

GitHub/direct builds run without App Sandbox, as explicitly selected by
`CLIPTATE_APP_STORE=NO`. App Store builds retain their sandbox and capability policy.
Direct builds copy missing configuration, presets, and history from the previous
sandbox container once, retain originals, and preserve existing direct-build data.
The helper is a native Xcode target, signed before embedding, and covered by the
existing app signature/notarization checks. The production app bundle ID is unchanged.

## Development app

Debug builds produce `Cliptate Dev.app` (`com.cliptate.dev`). Its embedded `cliptate`
command connects to that app using `cliptate-dev-cli` and a development-only port
range. Production and development can serve CLI requests at the same time.
Development uses its own configuration and dictionary; it does not import the
production dictionary automatically.

A standalone command defaults to the production installation. To choose development:

```bash
CLIPTATE_APP="/path/to/Cliptate Dev.app" cliptate dictionary list
```

## Generate speech

```sh
cliptate tts --text "你好，欢迎使用 Cliptate。" --language zh -o speech.wav --download
cliptate tts --text-file narration.txt -o narration.wav --format json
printf 'Hello world.' | cliptate tts --text-file - -o hello.wav
cliptate tts --text "Hello!" -o hello.wav \
  --model qwen3-tts-0.6b-customvoice-8bit --voice Ryan --emotion "cheerful" --download
cliptate tts --text "A new sentence." -o cloned.wav \
  --model qwen3-tts-0.6b-base-8bit \
  --reference-audio reference.wav --reference-text "The words spoken in reference.wav."
cliptate tts --text "Welcome." -o designed.wav \
  --model qwen3-tts-1.7b-voicedesign-8bit --voice "A warm, calm narrator" --download
```

Choose exactly one text source: `--text`, `--text-file PATH`, or `--text-file -`
for stdin. Text must be nonempty UTF-8 and no larger than 1 MiB; a leading UTF-8
BOM is accepted. `-o`/`--output` is required and must name a `.wav` file in an
existing directory. The output is mono float32 WAV at the model's native sample
rate. Output files require `--overwrite` if they already exist. Text and reference
audio inputs are protected from overwrite, including symlink aliases. Failed or
cancelled synthesis preserves an existing output.

The command snapshots the app's TTS model, language, variant, and applicable voice
settings. Overrides apply only to this request. `--model` (alias `--tts-model`)
accepts a TTS model ID, its `ModelVariant` identifier, or its Hugging Face repository.
Missing models require `--download`. `--language` accepts `auto`, `en`, `zh`, `ja`,
`ko`, `de`, `fr`, `ru`, `pt`, `es`, and `it`. `--variant` accepts `automatic`, `short`,
and `extended`. These variants follow the existing synthesis runtime's generation
policy; they do not guarantee a fixed audio duration.

Voice parameters must match the selected model family:

- **CustomVoice:** `--voice` selects a named speaker, and `--emotion` supplies an
  optional emotion/style description. Speakers are `Vivian`, `Serena`, `Uncle_Fu`,
  `Dylan`, `Eric`, `Ryan`, `Aiden`, `Ono_Anna`, and `Sohee`.
- **VoiceDesign:** `--voice` supplies a natural-language voice description.
- **Base:** `--reference-audio` and nonempty `--reference-text` together enable voice
  cloning. Base without reference audio uses the model's default voice. Voice and
  emotion flags cannot be combined with cloning.

Saved GUI reference audio is not used implicitly. CLI synthesis does not create
history entries or change saved settings. One CLI transcription or speech-generation
request runs at a time; dictionary requests remain available. Ctrl+C/SIGTERM
cancels the request cooperatively and returns `130`, including while waiting for
stdin. The inference slot remains occupied until cancelled work exits.

On success, stdout contains the absolute output path. With `--format json`, stdout
contains `{ "file": "/absolute/speech.wav", "model": "tts-model-id", "bytes": 123456 }`.
Progress and errors go to stderr. Exit codes match transcription. The app writes
WAV into a private CLI staging directory passed by bookmark; the CLI publishes it
atomically after success and removes staging files. Audio is not carried in JSON
frames, so generated audio can exceed the transport's 16 MiB frame limit.
