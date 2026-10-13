# Cliptate main window design QA

## Evidence and state

- Selected visual direction: `/Users/pilot/.codex/generated_images/01a12ff0-cdb4-7da0-81aa-760322fccc3b/exec-e89bfeb1-f51d-427a-9b11-23e4caffc798.png`.
- Original drag target, retained at the user's request: `/tmp/cliptate-design-audit/01-sidebar-expanded.png`.
- Final implementation: `/tmp/cliptate-redesign-qa/home.zh-Hans.png`; published README captures: `assets/screenshots/home.{en,zh-Hans,ja,ko,de}.jpg`.
- Full-view comparison: `/tmp/cliptate-redesign-qa/comparison-final.jpg`, with source and implementation in the same image.
- Focused original/restored drag-target comparison: `/tmp/cliptate-redesign-qa/comparison-drop-area.jpg`.
- Sidebar collapsed: `/tmp/cliptate-redesign-qa/sidebar-collapsed.png`.
- Native macOS viewport: 1280 × 800 pt, light appearance, AI Cut empty state. Implementation and original capture: 2560 × 1600 pixels at 2×. Mock: 1586 × 992 pixels. Full-view comparison normalizes each to 1280 × 800. No CSS viewport applies to this native app.

## Comparison history

1. Initial comparison (`home-initial.png`, `comparison-initial.jpg`) found [P2] missing blue selected icons and [P2] undersized page/import headings. Explicit accent color was added to selected navigation icons; page headings use the system title style.
2. The user subsequently requested retaining the original drag area. Its 680 × 340 pt dimensions, download symbol, dashed rounded border, background, shadow, hover/drag highlight, and scale animation were restored. The compact card and separate import button from the mock were removed. Reduce Motion suppresses movement.
3. The final full-view and focused comparisons confirm that earlier findings are resolved. The drag-target heading retains its original headline style as explicitly requested. Copy now separates dropping from clicking and explains multiple selection. Five localized captures were inspected with no visible truncation at this viewport.

## Required fidelity surfaces

- **Typography:** native system fonts and locale fallbacks render cleanly. The page title has a clear hierarchy; original drag-target headline/callout styles are retained. German and Korean helper text fits; all five languages show complete navigation and import labels. English uses “Settings”.
- **Spacing and layout:** the blank native toolbar separates window controls from content. The header has consistent 28 pt horizontal padding. The import region is centered in the available content area without the previous decorative welcome stack or unnecessary scrolling. Settings and Free Access remain pinned to the sidebar bottom. Collapsing the sidebar leaves the page title below the toolbar without overlap.
- **Colors:** selected main-list and footer icons use accent blue. Native list selection and semantic secondary/tertiary text colors preserve the app's original appearance; the inactive list's gray selection differs intentionally from the mock. Footer selection was observed with a blue icon and tinted background.
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

final result: passed
