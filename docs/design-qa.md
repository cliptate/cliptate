# Cliptate main window design QA

## Evidence and state

- Selected visual direction: `/Users/pilot/.codex/generated_images/01a12ff0-cdb4-7da0-81aa-760322fccc3b/exec-e89bfeb1-f51d-427a-9b11-23e4caffc798.png`.
- Original drag target, retained at the user's request: `/tmp/cliptate-design-audit/01-sidebar-expanded.png`.
- Redesign capture before the sidebar contrast follow-up: `/tmp/cliptate-redesign-qa/home.zh-Hans.png`; published README captures: `assets/screenshots/home.{en,zh-Hans,ja,ko,de}.jpg`.
- Full-view comparison: `/tmp/cliptate-redesign-qa/comparison-final.jpg`, with source and implementation in the same image.
- Focused original/restored drag-target comparison: `/tmp/cliptate-redesign-qa/comparison-drop-area.jpg`.
- Sidebar collapsed: `/tmp/cliptate-redesign-qa/sidebar-collapsed.png`.
- Native macOS viewport: 1280 × 800 pt, light appearance, AI Cut empty state. Implementation and original capture: 2560 × 1600 pixels at 2×. Mock: 1586 × 992 pixels. Full-view comparison normalizes each to 1280 × 800. No CSS viewport applies to this native app.

## Comparison history

1. Initial comparison (`home-initial.png`, `comparison-initial.jpg`) found [P2] missing blue selected icons and [P2] undersized page/import headings. Explicit accent color was initially added to selected navigation icons; page headings use the system title style. The later contrast fix below supersedes fixed blue icons in native list rows.
2. The user subsequently requested retaining the original drag area. Its 680 × 340 pt dimensions, download symbol, dashed rounded border, background, shadow, hover/drag highlight, and scale animation were restored. The compact card and separate import button from the mock were removed. Reduce Motion suppresses movement.
3. The final full-view and focused comparisons confirm that earlier findings are resolved. The drag-target heading retains its original headline style as explicitly requested. Copy now separates dropping from clicking and explains multiple selection. Five localized captures were inspected with no visible truncation at this viewport.

## Required fidelity surfaces

- **Typography:** native system fonts and locale fallbacks render cleanly. The page title has a clear hierarchy; original drag-target headline/callout styles are retained. German and Korean helper text fits; all five languages show complete navigation and import labels. English uses “Settings”.
- **Spacing and layout:** the blank native toolbar separates window controls from content. The header has consistent 28 pt horizontal padding. The import region is centered in the available content area without the previous decorative welcome stack or unnecessary scrolling. Settings and Free Access remain pinned to the sidebar bottom. Collapsing the sidebar leaves the page title below the toolbar without overlap.
- **Colors:** selected list and footer icons use accent blue with monochrome rendering, following the latest explicit user preference. Unselected icons remain secondary and hierarchical. Native list backgrounds and footer tint, hover, and selection backgrounds remain unchanged.
- **Assets:** original SF Symbols remain vector-sharp. No decorative raster assets are required. README images are actual app captures, converted to JPEG at quality 90. The macOS screen-control overlay in the top-left corner is a capture artifact.
- **Copy:** the title says where to drop videos; the helper explains clicking and multiple selection; supported formats remain below the target. New strings have Chinese, Japanese, Korean, and German translations. Five READMEs describe import and navigation separately from language selection.

## Intentional differences from the mock

The user's later instructions supersede the mock's drop-zone sizing, icon, and separate button. Bottom-pinned footer destinations follow the approved recommendation. Native window controls, SF Symbols, semantic colors, system typography, and the user's persisted 260 pt sidebar width remain authoritative over mock styling.

## Validation and limits

- `swift build`, full `swift test` (759 tests in 114 suites), and the signed Xcode app build passed. Development permission identity verification passed.
- Native UI checks: sidebar collapse/expand, Settings navigation and selected icon color, switching five languages, clicking the restored drop target to open a localized video picker, and cancelling back to the empty state.
- Restored the language preference to System Default after capture.
- File-drop ingestion and transcription were not exercised with user files. Animation timing, reduced-motion behavior, dark appearance, and smaller-window resizing were not manually verified. The existing drop ingestion and animation implementation are retained.

No actionable P0/P1/P2 visual findings remain in the compared viewport and states.

## Sidebar contrast follow-up

The user reported blue selected icons disappearing against the native blue list highlight in both light and dark appearance. Fixed-blue styling now applies only to footer destinations, whose selected background is a low-opacity tint. Native selected rows inherit their foreground from List and use monochrome symbols; unselected rows retain secondary hierarchical symbols.

- Before: `/tmp/cliptate-sidebar-contrast/dark-before.png`.
- After: `/tmp/cliptate-sidebar-contrast/dark-after.png` and `/tmp/cliptate-sidebar-contrast/light-after.png`.
- Focused comparison, all three captures in one image: `/tmp/cliptate-sidebar-contrast/comparison.jpg`.
- Footer checks: `/tmp/cliptate-sidebar-contrast/dark-footer.png` and `/tmp/cliptate-sidebar-contrast/light-footer.png`.
- Captures are 2560 × 1600 pixels at 2×; focused crops retain their original density. Captured native list highlights were gray; the active blue-highlight state could not be forced through automation. No fixed icon foreground remains in native selected rows, so system highlight/foreground adaptation is preserved.
- SwiftPM and signed Xcode builds, 11 navigation regression tests, and development signing identity checks passed. The original dark appearance preference was restored.

## Latest user preference: blue selected icons

The user explicitly requested returning selected icons to blue while retaining the current backgrounds. All selected sidebar icons now use the app accent color with monochrome symbol rendering; unselected icons remain secondary. The native list highlight and footer backgrounds are unchanged. This supersedes the inherited-foreground choice in the contrast follow-up above. Blue icon color across system focus states is an intentional user-requested override. Verified the blue selected icon against the retained dark native highlight in `/tmp/cliptate-sidebar-contrast/blue-selected-dark.png`. SwiftPM and signed Xcode builds and 11 navigation tests passed.

final result: passed

## Shared page colors (2026-10-15)

`AppSurface` now owns page, card, input, subtle, hover, border, and selected-state
colors. The native-style follow-up below replaces the initial fixed surface palette
with macOS semantic window, control, text-background, and separator colors. Text keeps system
primary/secondary styles, and actions use the app accent. Voice statistics and
history actions no longer introduce unrelated purple, orange, or yellow accents.
Semantic status colors, speaker colors, activity intensity, indicator theme previews,
and the existing import target remain intact.

Applied the shared roles to settings, dictation, synthesis, history, model browsing,
dictionary editing, editor configuration, and subscription surfaces. Native sidebar
selection and the explicitly requested blue selected icons are retained.

Validation: SwiftPM build, 44 existing regression tests across seven suites, the
signed development app build, and the development permission identity check passed.
Inspected AI Cut's empty state, Voice To Text, Text To Sound, History, Models,
Dictionary, and Settings in light and dark appearance at 1280 × 800 pt. Also checked
a selected history record and its details in dark appearance. Restored automatic
appearance afterward. The subscription channel and a populated video editor were
not manually exercised; their shared surface substitutions compiled successfully.

## Native editor and presentations follow-up (2026-10-15)

The user's request for a more Apple-native appearance supersedes the fixed light/dark
surface palette above. `AppSurface` now uses macOS window, control, text-background,
and separator colors. Native buttons, segmented controls, focus rings, file dialogs,
and alerts retain system styling. Floating playback/export controls use system
material; editing panels use the same native content surface as other pages.

- Unified the source, preset, configuration, segment, placeholder, import, and progress
  surfaces. Custom text editors share input backgrounds and focus outlines.
- Reduced timeline fill, kept normal foreground text in selected segments, and used
  the accent for selection/keyword emphasis. Rendered subtitle colors and the video
  canvas remain controlled by the existing subtitle/video settings.
- Aligned preset and correction sheets, dictionary suggestions, model tools, and update
  presentations. Removed the paywall's decorative background/card gradients and shadows.
- Generated a five-second narrated video in `/tmp/cliptate-editor-color-qa/preview.mp4`
  and transcribed it locally to inspect a populated editor. Inspected the editor and
  preset sheet in both appearances, the dark enhancement/export panels, and the filler
  word editor's focus outline. Inspected import and progress windows in light appearance.
  Cancelled the unsaved preset and restored automatic appearance.
- `swift build`, 60 existing tests across seven suites, the final signed app build,
  and development permission identity verification passed. The final selected-text
  contrast adjustment was compiled in the final app build.

AI correction, dictionary suggestion results, billing, and update presentations were
checked in source and compilation, without configuring accounts or invoking services.

## Native editor structure and SwiftUI components (2026-10-15)

This follow-up implements the user's request for a stronger Apple-native feel in
both layout and interaction, using the existing editor as the visual target.

### Numbered evidence and findings

1. `/tmp/cliptate-native-design-review/01-editor-before.png`: the populated editor
   had nested source/configuration/preset cards, six repeated actions per source,
   and three-line minimum editors that made short subtitle rows unnecessarily tall.
2. `/tmp/cliptate-native-design-review/02-preset-before.png`: the preset name was
   identified only by its placeholder. The sheet had no persistent field label.
3. `/tmp/cliptate-native-design-review/05-editor-after-final.png`: sources now use
   a native selectable List with per-source menus and a context menu. Presets use
   a compact single row. Configuration navigation stays fixed above its own scroll
   region. Transcript rows use separators and content-driven height. The status
   footer meets the inspector divider without a separate floating card.
4. `/tmp/cliptate-native-design-review/04-preset-after.png`: a native Form aligns
   the permanent name label, field, and default checkbox. Save remains disabled
   for an empty/whitespace-only name; Escape dismisses the sheet without saving.
5. `/tmp/cliptate-native-design-review/06-editor-comparison.jpg` and
   `07-preset-comparison.jpg`: saved before/after comparisons were reopened and
   inspected. Editor captures use the same 1280 × 800 pt window, Chinese locale,
   light appearance, three-row restored fixture, and 2× pixels. Sheet comparison
   preserves each sheet's native size; it does not stretch one to match the other.
   Window focus differs between sheet captures, so the focus ring and inactive
   button styling are not treated as a color mismatch.
6. `/tmp/cliptate-native-design-review/08-enhance-inspector.png` and
   `09-editor-dark.png`: the enhancement inspector fits at this viewport and uses
   a native module picker instead of six cramped segments. Dark system surfaces,
   input focus, separators, and text were checked from saved captures.

### Implementation and validation

- Extracted configuration modules, preset management/sheet, source row, segment
  header/row, translation editor, and effect labels into dedicated View types.
  Shared settings still belong to AppConfiguration and ConfigurationRuntime;
  local draft text and focus belong to their editing components. Preset sync is
  debounced and flushed when the preset view disappears.
- Kept per-video selection, operation availability, subtitle styling, segment
  identity, translation placement, editing commits, and export callbacks intact.
  The new completed-transcription accessibility label is localized in English,
  Chinese, Japanese, Korean, and German.
- `swift build` and the signed `./scripts/build-and-run.sh build` passed with full
  Xcode selected. Development permission identity verification and `git diff
  --check` passed. The final focused run passed 61 tests across eight suites;
  log: `/tmp/cliptate-native-layout-final-tests.log`.
- Manually verified transcript search, timestamp visibility, inline editing and
  commit on focus loss, then restored the fixture text. Inspected source menu
  actions/disabled states, preset name validation/cancel, enhancement timing, and
  FCPXML export controls. No preset or remote AI operation was submitted.
- The native computer-use connection terminated during the video-export module
  check and remained unavailable after reconnect/reset. Smaller-window layout,
  a dark preset sheet, and the remaining module interactions are not confirmed
  by this pass. The test appearance remains dark because the connection failed
  before it could be restored to the original automatic preference. The app's
  system palette adaptation itself was observed in both light and dark modes.

Result: implemented and validated within the recorded coverage; the additional
manual checks above remain pending because the native UI connection is unavailable.

## Compact windows and dark sheets follow-up (2026-10-15)

1. **Compact editor — fixed.** In the native quarter-window layout (1280 × 654 pt,
   2× capture), the waveform originally overlapped the bottom of the preview:
   `/tmp/cliptate-native-compact-qa/03-editor-quarter-before.png`. Video and subtitles
   now fit within a dedicated canvas above the waveform/transport region, rather
   than sharing an overlay. The transport remains visible during playback.
   `07-editor-compact-after.png` and `09-compact-comparison.jpg` show the new space
   allocation. Player readiness differs between these two paused captures; use
   this comparison for layout, not frame/subtitle-rendering fidelity.
2. **Narrow transport — passed.** Set native split dividers to a 260 pt preview
   column and inspected the two-row transport: `11-narrow-preview-after.png` and
   its unscaled focused crop, `12-narrow-transport-detail.png`. Play/skip controls
   sit above the scrubber and timestamps. The inspector text partially failed to
   repaint during this AX-driven divider stress check; that full capture is not
   accepted as inspector fidelity evidence. Restoring the normal 360/598 pt
   dividers restored its text. The focused transport region rendered correctly.
   Play, pause, and the enabled skip controls were exercised in the final build.
3. **Dark preset sheets — passed.** Inspected native creation and rename forms in
   `04-preset-dark-before.png` and `05-preset-rename-dark.png`. Verified initial
   name/focus, the checkbox's creation-only visibility, empty/whitespace validation,
   a valid name enabling Save, Escape cancellation, and rename prefilling Default.
   Cancelled all drafts. No preset was created or renamed.
4. **Automatic appearance — restored.** Selected Auto and inspected the selected
   control and system-light rendering in `08-automatic-appearance-restored.png`.
   Restarted the final build afterward and observed that the automatic appearance
   remained active. Restored the regular editor split widths after stress testing.

Additional polish uses native menu pickers for audio/video export formats, removes
extra opacity applied on top of native disabled styling in enhancement/export
controls, restores normal secondary contrast for segment durations, and lets the
export progress panel shrink within narrow preview panes. Dedicated
EditorVideoCanvas and EditorPlaybackControls keep layout separate from playback
lifecycle, scrubbing, segment processing, and subtitle style settings.

Validation: SwiftPM build, signed development app build, development permission
identity verification, and whitespace checks passed. The focused regression run
passed 75 tests across 14 suites (`/tmp/cliptate-native-compact-final-tests.log`).
Final app build: `/tmp/cliptate-native-compact-final-verified-app.log`.

Remaining evidence limit: entering the video-export configuration repeatedly
terminated the native inspection tool's pipe, including after a development-process
restart. The app process remained running. That panel's changed controls compiled,
but its final rendered state is not claimed as verified. This is an inspection
failure; an application crash was not observed. Restarting the development test
process recovered inspection and allowed automatic appearance to be restored.

Follow-up after the user returned to the main window: isolated the module click
from observation. The Video module click completed successfully; the subsequent
`getScreenshot` call terminated the native inspection pipe. A two-second process
sample (`/tmp/cliptate-video-export-sample.txt`) showed the main thread primarily
waiting in the normal AppKit event loop, rather than a busy layout loop. This
sample does not establish the cause of the inspection failure or verify the
panel's appearance. Restarted only the verified development test process to
recover inspection, returned to Settings, and saved/reopened
`/tmp/cliptate-native-compact-qa/14-auto-appearance-reconfirmed.png`: Auto remained
selected after restart. No further application code or preferences changed in
this follow-up; the video-export visual check remains unverified.
