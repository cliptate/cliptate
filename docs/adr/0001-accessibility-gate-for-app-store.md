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

- The flag direction remains **App Store when `APP_STORE` is defined**.
  Release defaults to that condition in SwiftPM. Debug (Cliptate Dev)
  defaults to direct distribution so local development exercises Accessibility,
  the free feature policy, and the embedded CLI without App Sandbox.
  `CLIPTATE_APP_STORE=YES` explicitly selects the App Store channel in the build
  script or SwiftPM; `NO` selects direct distribution. The bundler uses the same
  channel for compilation, CLI embedding, and signing entitlements. The capability
  seam itself is unchanged.
- **Call sites never use `#if`** — they read `AccessibilityGate.isSupported` (a
  plain compile-time bool) or call its methods. Retiring the App Store channel is
  deleting the one `#if APP_STORE` branch and the package compilation flag; call
  sites are untouched and `isSupported` becomes a constant `true`.
- Default App Store builds fall back to review-safe paths: clipboard copy
  instead of text injection, local-only shortcut monitoring instead of
  `CGEventTap` or global key monitoring, and the Accessibility permission row is
  hidden.
- The "copied to clipboard, press ⌘V" hint keys off the **runtime** fact that
  injection fell back — not the compile flag — so it also helps non-App-Store
  users who haven't granted Accessibility, and carries no `#if`.
