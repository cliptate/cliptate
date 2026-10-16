# Home and navigation verification — 2026-10-16

Implemented the requested Spokenly-inspired statistics home, heatmap hover details, removal of the heatmap from History, tab hover feedback, and centered file transcription drop target.

## Changes

- Home is the default destination after setup; existing restored destinations remain respected.
- Three all-time dictation metrics reuse persisted usage totals. Activity and source counts share the same rolling twelve-month interval.
- Heatmap cells expose date and record count through a pointer-following tooltip and accessibility labels.
- History now opens directly into filters and records.
- Sidebar rows, provider filters, and native segmented tabs have hover feedback without changing layout or native selection behavior.
- File transcription uses the available viewport height to center its drop target.
- New strings include English, Simplified Chinese, Japanese, Korean, and German.

## Verification

- Focused navigation and activity tests: 20 tests passed (`/tmp/cliptate-home-focused.log`).
- Full Swift test run passed, including 758 application Swift Testing tests and 34 Core Swift Testing tests, plus existing XCTest suites (`/tmp/cliptate-home-tests.log`).
- Final signed macOS app build passed (`/tmp/cliptate-home-hover-build.log`).
- Final build: all eight destinations reached their expected headings; History has no activity heatmap (`navigation-results.json`).
- User manually verified the heatmap hover tooltip: “小框正常显示”. Native automation clicks did not reliably generate mouse-enter events, so screenshots of hover attempts are not evidence of tooltip display.
- `git diff --check` passed.

## Captures

- `01-home.png`: initial layout before correcting the statistics column count.
- `02-heatmap-hover.png` and `02-user-confirmed-hover.png`: capture attempts without a visible tooltip; manual confirmation above is the hover evidence.
- `03-history.png`: History without the heatmap.
- `04-file-centered.png`: centered transcription drop target.
- `05-home-final.png`: final home layout after the signed build.

Native visual checks used the English light appearance at a 1280 × 801 point window. Captures stay local because they include existing usage data and history.
