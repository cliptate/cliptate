# Gate macOS Accessibility behind a single compile-time seam for App Store builds

Mac App Store review rejected the app under guideline 2.4.5 because it requests
Accessibility solely to drive other apps (focused-field text injection via
`CGEvent`, global Space-key interception via `CGEvent.tapCreate`) — not to
increase accessibility. We funnel every Accessibility-backed capability through a
single `AccessibilityGate` type and strip the real implementation with a
`#if APP_STORE` branch *inside that one file*. The App Store keyboard shortcut
path also avoids `CGEvent.tapCreate` and global `NSEvent` monitors, so an App
Store binary neither requests nor links `AXIsProcessTrusted*`, `CGEvent`,
`kAXTrusted`, direct text injection, or global key-monitor behavior.

## Considered Options

- **Scattered `#if !APP_STORE` at each call site** (3 files, ~6 directives) —
  rejected: removal later means editing every business-logic site.
- **Full protocol + two implementations** — rejected as over-engineered for two
  features.
- **Single-file `AccessibilityGate` enum** — chosen.

## Consequences

- The flag direction is **App Store by default**: Xcode Debug/Release and
  SwiftPM Debug/Release define `APP_STORE`, so local default builds exercise the
  App Store-safe path. Non-App-Store builds must opt out explicitly by removing
  the compilation condition from the selected build entrypoint.
- **Call sites never use `#if`** — they read `AccessibilityGate.isSupported` (a
  plain compile-time bool) or call its methods. Retiring the App Store channel is
  deleting the one `#if APP_STORE` branch and the one Xcode flag; call sites are
  untouched and `isSupported` becomes a constant `true`.
- Default App Store builds fall back to review-safe paths: clipboard copy
  instead of text injection, local-only shortcut monitoring instead of
  `CGEventTap` or global key monitoring, and the Accessibility permission row is
  hidden.
- The "copied to clipboard, press ⌘V" hint keys off the **runtime** fact that
  injection fell back — not the compile flag — so it also helps non-App-Store
  users who haven't granted Accessibility, and carries no `#if`.
