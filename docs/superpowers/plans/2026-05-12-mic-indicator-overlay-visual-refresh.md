# MicIndicatorOverlay Visual Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `MicIndicatorOverlay` into a compact graphite macOS-style recording HUD with fully transparent corners, stronger separation from light backgrounds, and unchanged behavior.

**Architecture:** Keep the existing left / center / right overlay layout and transcript behavior, but replace the current glass-heavy rendering stack with a darker graphite surface, lighter edge treatment, full-overlay corner cutouts, and stronger foreground contrast rules. Implement the redesign by tightening the existing `MicIndicatorOverlay.swift` surface helpers and updating the focused overlay regression tests in `MicIndicatorOverlayTests.swift`.

**Tech Stack:** SwiftUI, AppKit, Swift Testing, xcodebuild, Swift Package Manager

---

## File Structure

- **Modify:** `Sources/Cliptate/Utilities/MicIndicatorOverlay.swift`
  - Keeps the overlay view model, panel rendering, waveform styling, transcript styling, and DEBUG test accessors.
- **Modify:** `Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift`
  - Holds focused regression tests for waveform structure, overlay styling direction, and contrast rules.
- **Reference only:** `docs/superpowers/specs/2026-05-12-mic-indicator-overlay-visual-refresh-design.md`
  - Approved spec for the graphite HUD direction.

### Task 1: Lock the approved styling direction in tests

**Files:**
- Modify: `Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift`
- Test: `Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
  @Test("overlay styling uses graphite HUD surface instead of liquid glass")
  func overlayStylingUsesGraphiteHudSurface() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testUsesGraphiteHudSurface == true)
    #expect(overlay.testPrefersLiquidGlassStyling == false)
  }

  @Test("overlay styling uses fully transparent corners with a more distinct main panel")
  func overlayStylingUsesTransparentCornersAndDistinctPanel() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testUsesTransparentCorners == true)
    #expect(overlay.testUsesHigherBackgroundTransparency == false)
    #expect(overlay.testUsesContrastShadowForForeground == true)
  }

  @Test("overlay accessories use minimal chrome instead of floating chips")
  func overlayAccessoriesUseMinimalChrome() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testAccessoryUsesMinimalChrome == true)
    #expect(overlay.testAccessoryUsesFloatingChipBackground == false)
  }
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter overlayStylingUsesGraphiteHudSurface`

Expected: FAIL because `MicIndicatorOverlay` still reports Liquid Glass preference or lacks the new graphite-HUD assertion.

- [ ] **Step 3: Run the accessory regression to verify current styling is still covered**

Run: `swift test --filter overlayAccessoriesUseMinimalChrome`

Expected: PASS or FAIL depending on current tree state, but the test must exist before any styling implementation changes continue.

- [ ] **Step 4: Commit the test lock-in**

```bash
git add Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift
git commit -m "test: lock MicIndicatorOverlay visual direction"
```

### Task 2: Replace the glass-led panel with a graphite HUD surface

**Files:**
- Modify: `Sources/Cliptate/Utilities/MicIndicatorOverlay.swift`
- Test: `Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift`

- [ ] **Step 1: Implement the graphite panel surface helpers**

```swift
    @ViewBuilder
    private func panelSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.23, blue: 0.25, opacity: 0.92),
                        Color(red: 0.16, green: 0.17, blue: 0.19, opacity: 0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
    }

    private func panelHighlights(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.025),
                        Color.clear,
                        Color.black.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
```

- [ ] **Step 2: Apply the surface, border, and full-overlay corner cutout in `body`**

```swift
            ZStack(alignment: .top) {
                panelSurface(cornerRadius: panelCornerRadius)
                panelHighlights(cornerRadius: panelCornerRadius)
                panelBorder(cornerRadius: panelCornerRadius)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    waveformSection(visualizerState: visualizerState)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if transcriptVisible {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        transcriptSection(
                            lines: viewModel.displayLines,
                            viewportHeight: transcriptViewportHeight
                        )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: width, height: viewModel.panelHeight, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
            .overlay(
                panelCornerTransparency(cornerRadius: panelCornerRadius)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 10)
```

- [ ] **Step 3: Implement the full transparent-corner helpers**

```swift
    private func panelCornerTransparency(cornerRadius: CGFloat) -> some View {
        let cutoutRadius = cornerRadius + 6

        return ZStack {
            cornerCutout(at: .topLeading, radius: cutoutRadius)
            cornerCutout(at: .topTrailing, radius: cutoutRadius)
            cornerCutout(at: .bottomLeading, radius: cutoutRadius)
            cornerCutout(at: .bottomTrailing, radius: cutoutRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func cornerCutout(at point: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [
                Color.black,
                Color.black.opacity(0.72),
                .clear
            ],
            center: point,
            startRadius: 0,
            endRadius: radius
        )
    }
```

- [ ] **Step 4: Update the DEBUG styling accessors to match the approved direction**

```swift
    var testUsesGraphiteHudSurface: Bool { true }
    var testPrefersLiquidGlassStyling: Bool { false }
    var testUsesTransparentCorners: Bool { true }
    var testUsesHigherBackgroundTransparency: Bool { false }
    var testUsesContrastShadowForForeground: Bool { true }
```

- [ ] **Step 5: Run the focused styling test to verify it passes**

Run: `swift test --filter overlayStylingUsesGraphiteHudSurface && swift test --filter overlayStylingUsesTransparentCornersAndDistinctPanel`

Expected: PASS

- [ ] **Step 6: Commit the surface redesign**

```bash
git add Sources/Cliptate/Utilities/MicIndicatorOverlay.swift Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift
git commit -m "feat: redesign MicIndicatorOverlay panel surface"
```

### Task 3: Tune foreground contrast, transcript bed, and waveform color balance

**Files:**
- Modify: `Sources/Cliptate/Utilities/MicIndicatorOverlay.swift`
- Test: `Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift`

- [ ] **Step 1: Strengthen transcript readability against light backgrounds**

```swift
                        Text(line.text)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.96))
                            .shadow(color: Color.black.opacity(0.42), radius: 1.4, x: 0, y: 1)

        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
        )
```

- [ ] **Step 2: Keep icon and timer minimal, but raise their contrast**

```swift
    @ViewBuilder
    private var leadingAccessory: some View {
        if let appIcon = viewModel.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Color.black.opacity(0.24), radius: 2, x: 0, y: 1)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.white.opacity(0.82))
                .shadow(color: Color.black.opacity(0.40), radius: 1.4, x: 0, y: 1)
                .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    private func trailingAccessory(visualizerState: VisualizerState) -> some View {
        if let start = viewModel.recordingStartDate {
            Group {
                if visualizerState == .transcribing || visualizerState == .aiEnhance {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.78))
                        .frame(width: 24, height: 24)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0)) { timeline in
                        let elapsed = Int(timeline.date.timeIntervalSince(start))
                        Text(formatDuration(elapsed))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .shadow(color: Color.black.opacity(0.42), radius: 1.4, x: 0, y: 1)
                    }
                }
            }
            .frame(minWidth: 36, alignment: .trailing)
            .fixedSize()
        } else {
            Color.clear
                .frame(width: 36, height: 24)
        }
    }
```

- [ ] **Step 3: Keep the 9-bar waveform, but tune it toward restrained graphite-HUD accents**

```swift
    /// 9-bar vertical bouncing waveform driven by real-time RMS audio level.
    /// Bar weights [0.28, 0.42, 0.58, 0.78, 1.0, 0.82, 0.64, 0.46, 0.30] create a center-high, sides-low effect.
    private func bouncingWaveform() -> some View {
        let barCount = 9
        let weights: [CGFloat] = [0.28, 0.42, 0.58, 0.78, 1.0, 0.82, 0.64, 0.46, 0.30]
        let barWidth: CGFloat = 5
        let barSpacing: CGFloat = 3
        let minBarHeight: CGFloat = 6
        let maxBarHeight: CGFloat = 38
        let attackCoeff: CGFloat = 0.55
        let releaseCoeff: CGFloat = 0.15
        let jitterRange: CGFloat = 0.06
        let range = maxBarHeight - minBarHeight

        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let target = viewModel.level * weights[index]
                let jitter = CGFloat.random(in: -jitterRange...jitterRange)
                let jitteredTarget = max(0, min(1, target + jitter))

                let _ = updateSmoothedLevel(
                    at: index,
                    target: jitteredTarget,
                    attack: attackCoeff,
                    release: releaseCoeff
                )

                let smoothed = viewModel.smoothedBarLevels[index]
                let barHeight = max(minBarHeight, minBarHeight + range * smoothed)

                let gradient = LinearGradient(
                    colors: [
                        Color(red: 0.62, green: 0.76, blue: 0.92, opacity: 0.72 + Double(smoothed) * 0.16),
                        Color(red: 0.47, green: 0.61, blue: 0.78, opacity: 0.62 + Double(smoothed) * 0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: barHeight)
                    .shadow(color: Color.white.opacity(0.04 + Double(smoothed) * 0.06), radius: 2, x: 0, y: 0)
                    .animation(.easeOut(duration: 0.05), value: smoothed)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .frame(height: maxBarHeight)
    }
```

- [ ] **Step 4: Run the focused overlay suite**

Run: `swift test --filter MicIndicatorOverlay`

Expected: PASS with the styling, bar-count, and layout regressions all green.

- [ ] **Step 5: Run the app build**

Run: `xcodebuild -project Sources/Cliptate.xcodeproj -scheme Cliptate build -quiet`

Expected: `** BUILD SUCCEEDED **` or the usual destination warning plus successful exit status.

- [ ] **Step 6: Commit the finishing pass**

```bash
git add Sources/Cliptate/Utilities/MicIndicatorOverlay.swift Sources/CliptateTests/Utilities/MicIndicatorOverlayTests.swift
git commit -m "feat: finalize MicIndicatorOverlay graphite HUD styling"
```
