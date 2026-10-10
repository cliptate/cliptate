import AppKit
import Foundation
import SwiftUI

@MainActor
final class MicIndicatorOverlay {
    fileprivate struct Constants {
        enum SurfaceStyle {
            case graphiteHUD
            case liquidGlass
            case ultraThinMaterial
        }

        enum AccessoryStyle {
            case minimalChrome
            case floatingChip
        }

        enum CornerTransparencyStyle {
            case roundedClip
            case hardCutout
            case softFade
        }

        static let width: CGFloat = 224
        static let baseHeight: CGFloat = 52
        static let verticalGap: CGFloat = 140
        static let updateInterval: TimeInterval = 0.5
        static let baselineLevel: CGFloat = 0.05
        static let idleThreshold: CGFloat = 0.16
        static let listeningThreshold: CGFloat = 0.24
        static let waveformBarCount: Int = 9
        static let waveformSideSlotWidth: CGFloat = 56
        static let maxTranscriptLines: Int = 2
        static let panelCornerRadius: CGFloat = 22
        static let transcriptCornerRadius: CGFloat = 14
        static let panelShadowOpacity = 0.46
        static let foregroundContrastShadowOpacity = 0.42
        static let foregroundSecondaryShadowOpacity = 0.40
        static let foregroundIconShadowOpacity = 0.24
        static let backgroundTransparencyOpacityThreshold = 0.88
        static let panelTopOpacity = 0.82
        static let panelBottomOpacity = 0.87
        static let panelHighlightOpacity = 0.14
        static let lineHeight: CGFloat = 20
        static let transcriptLineSpacing: CGFloat = 6
        static let transcriptScrollVerticalPadding: CGFloat = 6
        static let transcriptSectionPadding: CGFloat = 56
        static let transcriptTextOpacity = 0.96
        static let transcriptShadowOpacity = 0.42
        static let transcriptSupportFillOpacity = 0.10
        static let transcriptSupportStrokeOpacity = 0.10
        static let transcriptSupportStrokeWidth: CGFloat = 0.8
        static let processingEllipsisTemplate = "..."
        static let waveformTopAccentRed = 0.48
        static let waveformTopAccentGreen = 0.90
        static let waveformTopAccentBlue = 1.00
        static let waveformTopBaseOpacity = 0.78
        static let waveformTopLevelOpacity = 0.18
        static let waveformBottomAccentRed = 0.19
        static let waveformBottomAccentGreen = 0.57
        static let waveformBottomAccentBlue = 0.95
        static let waveformBottomBaseOpacity = 0.66
        static let waveformBottomLevelOpacity = 0.20
        static let waveformHighlightBaseOpacity = 0.08
        static let waveformHighlightLevelOpacity = 0.12
        static let surfaceStyle: SurfaceStyle = .graphiteHUD
        static let accessoryStyle: AccessoryStyle = .minimalChrome
        static let cornerTransparencyStyle: CornerTransparencyStyle = .roundedClip
        static let cornerCutoutRadius: CGFloat = panelCornerRadius + 6

        // MARK: - Tech theme
        enum TechStyle {
            /// Electric cyan-blue — default neon pulse look
            case pulseBlue
            /// Phosphor green — matrix / terminal aesthetic
            case matrixGreen
            /// Deep space purple — void / holographic aesthetic
            case voidPurple
        }
        static let techStyle: TechStyle = .pulseBlue

        static var panelTopColor: Color {
            switch techStyle {
            // Near-black with a barely-perceptible cool tint — deep space feel
            case .pulseBlue:   return Color(red: 0.03, green: 0.04, blue: 0.08, opacity: panelTopOpacity)
            // Near-black with the faintest green cast
            case .matrixGreen: return Color(red: 0.02, green: 0.05, blue: 0.02, opacity: panelTopOpacity)
            // Near-black with a whisper of violet
            case .voidPurple:  return Color(red: 0.05, green: 0.02, blue: 0.09, opacity: panelTopOpacity)
            }
        }

        static var panelBottomColor: Color {
            switch techStyle {
            // Essentially pure black — makes glowing elements look like real phosphor/neon
            case .pulseBlue:   return Color(red: 0.005, green: 0.005, blue: 0.012, opacity: panelBottomOpacity)
            case .matrixGreen: return Color(red: 0.005, green: 0.008, blue: 0.003, opacity: panelBottomOpacity)
            case .voidPurple:  return Color(red: 0.008, green: 0.003, blue: 0.015, opacity: panelBottomOpacity)
            }
        }

        static var borderTopColor: Color {
            switch techStyle {
            case .pulseBlue:   return Color(red: 0.30, green: 0.88, blue: 1.00).opacity(0.68)
            case .matrixGreen: return Color(red: 0.08, green: 1.00, blue: 0.38).opacity(0.60)
            case .voidPurple:  return Color(red: 0.72, green: 0.22, blue: 1.00).opacity(0.65)
            }
        }

        static var borderMidColor: Color {
            switch techStyle {
            case .pulseBlue:   return Color(red: 0.18, green: 0.52, blue: 1.00).opacity(0.26)
            case .matrixGreen: return Color(red: 0.08, green: 0.62, blue: 0.28).opacity(0.24)
            case .voidPurple:  return Color(red: 0.45, green: 0.12, blue: 0.82).opacity(0.26)
            }
        }

        static var radialHighlightColor: Color {
            switch techStyle {
            // Stronger glow intensity to punch through the near-black surface
            case .pulseBlue:   return Color(red: 0.22, green: 0.72, blue: 1.00).opacity(0.44)
            case .matrixGreen: return Color(red: 0.10, green: 0.90, blue: 0.35).opacity(0.36)
            case .voidPurple:  return Color(red: 0.68, green: 0.16, blue: 0.98).opacity(0.46)
            }
        }

        static var waveformTopColor: Color {
            switch techStyle {
            case .pulseBlue:
                return Color(red: waveformTopAccentRed, green: waveformTopAccentGreen, blue: waveformTopAccentBlue)
            case .matrixGreen:
                return Color(red: 0.18, green: 1.00, blue: 0.42)
            case .voidPurple:
                return Color(red: 0.80, green: 0.22, blue: 1.00)
            }
        }

        static var waveformBottomColor: Color {
            switch techStyle {
            case .pulseBlue:
                return Color(red: waveformBottomAccentRed, green: waveformBottomAccentGreen, blue: waveformBottomAccentBlue)
            case .matrixGreen:
                return Color(red: 0.06, green: 0.62, blue: 0.22)
            case .voidPurple:
                return Color(red: 0.32, green: 0.08, blue: 0.88)
            }
        }

        static var timeTextColor: Color {
            switch techStyle {
            case .pulseBlue:   return Color(red: 0.68, green: 0.94, blue: 1.00)
            case .matrixGreen: return Color(red: 0.40, green: 1.00, blue: 0.58)
            case .voidPurple:  return Color(red: 0.82, green: 0.66, blue: 1.00)
            }
        }

        static var cornerAccentColor: Color {
            switch techStyle {
            case .pulseBlue:   return Color(red: 0.30, green: 0.88, blue: 1.00).opacity(0.55)
            case .matrixGreen: return Color(red: 0.12, green: 0.95, blue: 0.38).opacity(0.50)
            case .voidPurple:  return Color(red: 0.70, green: 0.20, blue: 1.00).opacity(0.58)
            }
        }

        static let scanLineOpacity: Double = 0.032
        static let scanLineSpacing: CGFloat = 3.5
        static let cornerAccentLength: CGFloat = 12
        static let cornerAccentThickness: CGFloat = 1.4
        static let cornerAccentPadding: CGFloat = 8

        static let maxTranscriptViewportHeight: CGFloat = {
            let totalLineHeight = CGFloat(maxTranscriptLines) * lineHeight
            let spacingHeight = CGFloat(max(maxTranscriptLines - 1, 0)) * transcriptLineSpacing
            return totalLineHeight + spacingHeight + transcriptScrollVerticalPadding
        }()
    }

    struct DisplayLine: Identifiable {
        let id = UUID()
        let text: String
        let isLatest: Bool
    }

    private let viewModel = MicIndicatorViewModel()
    private var panel: NSPanel?
    private var updateTimer: Timer?
    private var lastTranscriptSnapshot: String = ""
    private var transcriptLines: [String] = []
    private var isManuallyPositioned = false
    private var isUpdatingPosition = false
    private var windowMoveObserver: NSObjectProtocol?
    private var currentHeight: CGFloat = Constants.baseHeight
    private var needsPositionRefresh = false
    private var isActive = false
    private var currentTimerInterval: TimeInterval = Constants.updateInterval
    private var dismissGeneration: UInt64 = 0
    /// When true, `updateTranscript` is a no-op — the transcript region will not expand.
    private var isTranscriptFrozen = false

    init() {}

    func startTracking() {
        ensurePanel()
        guard let panel else { return }
        dismissGeneration &+= 1
        if isActive, viewModel.recordingStartDate != nil {
            panel.orderFrontRegardless()
            return
        }

        isActive = true
        isManuallyPositioned = false
        isTranscriptFrozen = false
        needsPositionRefresh = false
        viewModel.level = Constants.baselineLevel
        viewModel.panelHeight = Constants.baseHeight
        currentHeight = Constants.baseHeight
        lastTranscriptSnapshot = ""
        transcriptLines.removeAll(keepingCapacity: false)
        withAnimation(.easeInOut(duration: 0.18)) {
            viewModel.displayLines = []
        }
        viewModel.transcriptViewportHeight = 0
        viewModel.isOverlayActive = true
        viewModel.hasTranscript = false
        viewModel.hasEnteredProcessing = false
        viewModel.inputWarning = nil
        viewModel.overlayStatus = .listening
        viewModel.recordingStartDate = Date()
        viewModel.levelHistory = []
        recalculatePanelHeight()
        panel.orderFrontRegardless()

        if let observer = windowMoveObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.isUpdatingPosition {
                    self.isManuallyPositioned = true
                }
            }
        }

        requestPositionUpdate(immediate: true)
        scheduleTimer()
    }

    func stopTracking() {
        dismissGeneration &+= 1
        guard isActive else { return }
        isActive = false
        updateTimer?.invalidate()
        updateTimer = nil
        
        if let observer = windowMoveObserver {
            NotificationCenter.default.removeObserver(observer)
            windowMoveObserver = nil
        }

        tearDownPanel()
        isManuallyPositioned = false
        needsPositionRefresh = false
        viewModel.level = Constants.baselineLevel
        viewModel.panelHeight = Constants.baseHeight
        currentHeight = Constants.baseHeight
        lastTranscriptSnapshot = ""
        transcriptLines.removeAll(keepingCapacity: false)
        withAnimation(.easeInOut(duration: 0.18)) {
            viewModel.displayLines = []
        }
        viewModel.transcriptViewportHeight = 0
        viewModel.isOverlayActive = false
        viewModel.hasTranscript = false
        viewModel.hasEnteredProcessing = false
        viewModel.overlayStatus = .idle
        viewModel.recordingStartDate = nil
        viewModel.levelHistory = []
    }

    func updateLevel(_ level: CGFloat) {
        guard isActive else { return }
        let clamped = level.clamped(to: 0...1)
        viewModel.level = max(Constants.baselineLevel, clamped)
        // Append to scrolling history
        viewModel.levelHistory.append(clamped)
        if viewModel.levelHistory.count > MicIndicatorViewModel.maxLevelHistory {
            viewModel.levelHistory.removeFirst()
        }
    }

    /// Sets the icon of the external application where dictation output will be delivered.
    func setAppIcon(_ icon: NSImage?) {
        viewModel.appIcon = icon
    }

    /// Update the status displayed on the overlay (Idle/Listening/Transcribing/AI Enhance).
    func updateStatus(_ status: OverlayStatus) {
        // If dictation ends (leaves listening) and transcript was never shown, freeze it.
        if status != .listening, !viewModel.hasTranscript {
            isTranscriptFrozen = true
        }
        if status == .transcribing || status == .aiEnhance {
            viewModel.hasEnteredProcessing = true
        }
        if status == .aiEnhance {
            // Cancel any dismiss that was scheduled after the transcription phase so the
            // overlay stays visible through the full AI enhance lifecycle.
            dismissGeneration &+= 1
            // Restore the elapsed timer in case performDismiss() already cleared it.
            if viewModel.recordingStartDate == nil {
                viewModel.recordingStartDate = Date()
            }
        }
        viewModel.overlayStatus = status
        recalculatePanelHeight(immediatePositioning: true)
    }

    func updateInputWarning(_ message: String?) {
        guard viewModel.inputWarning != message else { return }
        viewModel.inputWarning = message
        recalculatePanelHeight(immediatePositioning: true)
    }

    /// Keep a failed dictation visible long enough to read, including when invoked from another app.
    func showInputWarning(_ message: String) {
        startTracking()
        updateInputWarning(message)
        viewModel.overlayStatus = .idle
        viewModel.recordingStartDate = nil
        viewModel.level = 0
        viewModel.hasEnteredProcessing = false
        dismissGeneration &+= 1
        let generation = dismissGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.dismissGeneration == generation else { return }
            self.performDismiss()
        }
    }

    /// Briefly show a "copied to clipboard" hint, then dismiss. Used when text
    /// injection fell back to the clipboard so the user knows to paste manually.
    func flashCopiedToClipboard() {
        ensurePanel()
        guard let panel else { return }
        isActive = true
        viewModel.isOverlayActive = true
        viewModel.hasEnteredProcessing = false
        if viewModel.recordingStartDate == nil {
            viewModel.recordingStartDate = Date()
        }
        viewModel.overlayStatus = .copiedToClipboard
        recalculatePanelHeight(immediatePositioning: true)
        panel.orderFrontRegardless()

        // Cancel any pending dismiss, then dismiss after the hint has been shown.
        dismissGeneration &+= 1
        let generation = dismissGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.dismissGeneration == generation else { return }
                self.performDismiss()
            }
        }
    }

    /// Finish processing and dismiss the overlay after a brief delay.
    /// Guarded: no-op if processing is still in progress.
    func finishAndDismiss() {
        guard !viewModel.hasEnteredProcessing || viewModel.overlayStatus == .idle else { return }
        performDismiss()
    }

    /// Unconditionally finish and dismiss — call only when processing is truly complete.
    func forceFinishAndDismiss() {
        viewModel.hasEnteredProcessing = false
        performDismiss()
    }

    private func performDismiss() {
        viewModel.overlayStatus = .idle
        // Clear recordingStartDate immediately so the elapsed-time label
        // does not flash back during the 0.5 s dismiss animation.
        viewModel.recordingStartDate = nil
        recalculatePanelHeight(immediatePositioning: true)
        dismissGeneration &+= 1
        let generation = dismissGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                self?.completeScheduledDismiss(generation: generation)
            }
        }
    }

    private func completeScheduledDismiss(generation: UInt64) {
        guard dismissGeneration == generation else { return }
        stopTracking()
    }

    private func recalculatePanelHeight(immediatePositioning: Bool = false) {
        let transcriptHeight = viewModel.hasTranscript
            ? Constants.transcriptSectionPadding + Constants.maxTranscriptViewportHeight
            : 0
        let warningHeight: CGFloat = viewModel.inputWarning == nil ? 0 : 60
        let newHeight = Constants.baseHeight + transcriptHeight + warningHeight
        currentHeight = newHeight
        viewModel.panelHeight = newHeight
        requestPositionUpdate(immediate: immediatePositioning)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: Constants.width, height: Constants.baseHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = TransparentHostingView(
            rootView: MicIndicatorView(viewModel: viewModel, width: Constants.width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        panel.orderOut(nil)
        self.panel = panel
    }

    private func tearDownPanel() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    func updateTranscript(_ text: String?) {
        guard isActive, !isTranscriptFrozen else { return }
        let previousHasTranscript = viewModel.hasTranscript
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            viewModel.displayLines = []
            viewModel.transcriptViewportHeight = 0
            viewModel.hasTranscript = false
            if previousHasTranscript {
                refreshPositionTimerIfNeeded()
            }
            recalculatePanelHeight()
            return
        }

        guard trimmed != lastTranscriptSnapshot else { return }

        let extractedLines = transcriptEntries(from: trimmed)
        transcriptLines = Array(extractedLines.suffix(200))
        lastTranscriptSnapshot = trimmed

        let displayLines = transcriptLines.enumerated().map { index, text in
            DisplayLine(text: text, isLatest: index == transcriptLines.count - 1)
        }

        let visibleTranscriptHeight = displayLines.isEmpty ? 0 : Constants.maxTranscriptViewportHeight

        viewModel.displayLines = displayLines
        viewModel.hasTranscript = !displayLines.isEmpty
        if previousHasTranscript != viewModel.hasTranscript {
            refreshPositionTimerIfNeeded()
        }
        viewModel.transcriptViewportHeight = visibleTranscriptHeight
        recalculatePanelHeight(immediatePositioning: true)
    }

    private func scheduleTimer(interval: TimeInterval? = nil) {
        updateTimer?.invalidate()
        let resolvedInterval = max(0.25, interval ?? desiredTimerInterval())
        currentTimerInterval = resolvedInterval

        let timer = Timer(timeInterval: resolvedInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive, !self.isManuallyPositioned else { return }
                self.requestPositionUpdate()
            }
        }
        timer.tolerance = resolvedInterval * 0.35
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func desiredTimerInterval() -> TimeInterval {
        viewModel.hasTranscript
            ? Constants.updateInterval
            : Constants.updateInterval * 1.6
    }

    private func refreshPositionTimerIfNeeded() {
        guard isActive else { return }
        let desired = desiredTimerInterval()
        guard abs(desired - currentTimerInterval) > 0.05 else { return }
        scheduleTimer(interval: desired)
    }

    private func requestPositionUpdate(immediate: Bool = false) {
        if immediate {
            needsPositionRefresh = false
            performPositionUpdate()
            return
        }

        guard !needsPositionRefresh else { return }
        needsPositionRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.needsPositionRefresh = false
            self.performPositionUpdate()
        }
    }

    private func performPositionUpdate() {
        guard isActive, let panel, !isManuallyPositioned else { return }

        let targetFrame = resolvedFrame()

        if framesApproximatelyEqual(panel.frame, targetFrame) {
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            return
        }

        isUpdatingPosition = true
        panel.setFrame(targetFrame, display: true, animate: false)
        isUpdatingPosition = false
        
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func resolvedFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        return bottomCenterRect(on: targetScreen)
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.5)
        -> Bool
    {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func bottomCenterRect(on screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(x: 0, y: 0, width: Constants.width, height: currentHeight)
        }
        let visible = screen.visibleFrame
        
        // Anchor to the top position of the base state to prevent visualizer jumping
        let fixedTopY = visible.minY + Constants.verticalGap + Constants.baseHeight
        
        let origin = CGPoint(
            x: visible.midX - Constants.width / 2,
            y: fixedTopY - currentHeight
        )
        return CGRect(origin: origin, size: CGSize(width: Constants.width, height: currentHeight))
    }

    private func transcriptEntries(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    #if DEBUG
    /// Test accessor for the current `hasTranscript` state.
    var testHasTranscript: Bool { viewModel.hasTranscript }
    /// Test accessor for `isActive` state.
    var testIsActive: Bool { isActive }
    /// Test accessor for the overlay status.
    var testOverlayStatus: OverlayStatus { viewModel.overlayStatus }
    var testInputWarning: String? { viewModel.inputWarning }
    /// Test accessor for level history.
    var testLevelHistory: [CGFloat] { viewModel.levelHistory }
    /// Test accessor: whether the visualizer uses center alignment.
    var testVisualizerUsesCenterAlignment: Bool {
        Constants.waveformSideSlotWidth > 0 && Constants.width > (Constants.waveformSideSlotWidth * 2)
    }
    /// Test accessor for the overlay width.
    var testPanelWidth: CGFloat { Constants.width }
    /// Test accessor for the current panel height.
    var testCurrentPanelHeight: CGFloat { viewModel.panelHeight }
    /// Test accessor: processing status keeps a reserved ellipsis slot.
    var testProcessingStatusUsesReservedEllipsisSlot: Bool { Constants.processingEllipsisTemplate == "..." }
    /// Test accessor for the leading waveform side slot width.
    var testWaveformLeadingSlotWidth: CGFloat { Constants.waveformSideSlotWidth }
    /// Test accessor for the trailing waveform side slot width.
    var testWaveformTrailingSlotWidth: CGFloat { Constants.waveformSideSlotWidth }
    /// Test accessor: overlay uses the graphite HUD surface.
    var testUsesGraphiteHudSurface: Bool { Constants.surfaceStyle == .graphiteHUD }
    /// Test accessor: overlay styling prefers Liquid Glass where supported.
    var testPrefersLiquidGlassStyling: Bool { Constants.surfaceStyle == .liquidGlass }
    /// Test accessor: fallback styling uses ultra-thin material.
    var testUsesUltraThinMaterialFallback: Bool { Constants.surfaceStyle == .ultraThinMaterial }
    /// Test accessor: accessory styling uses minimal chrome.
    var testAccessoryUsesMinimalChrome: Bool { Constants.accessoryStyle == .minimalChrome }
    /// Test accessor: accessory styling does not use floating chip backgrounds.
    var testAccessoryUsesFloatingChipBackground: Bool { Constants.accessoryStyle == .floatingChip }
    /// Test accessor: overlay corners remain transparent without intruding into the panel body.
    var testUsesTransparentCorners: Bool {
        switch Constants.cornerTransparencyStyle {
        case .roundedClip, .hardCutout:
            true
        case .softFade:
            false
        }
    }
    /// Test accessor: overlay corners use hard cutouts, not radial fades.
    var testUsesHardCornerCutout: Bool { Constants.cornerTransparencyStyle == .hardCutout }
    /// Test accessor: overlay surface uses a higher-transparency treatment.
    var testUsesHigherBackgroundTransparency: Bool {
        Constants.panelTopOpacity < Constants.backgroundTransparencyOpacityThreshold
            || Constants.panelBottomOpacity < Constants.backgroundTransparencyOpacityThreshold
    }
    /// Test accessor: foreground content uses contrast shadowing.
    var testUsesContrastShadowForForeground: Bool {
        Constants.transcriptShadowOpacity == Constants.foregroundContrastShadowOpacity
            && Constants.foregroundSecondaryShadowOpacity > 0
            && Constants.foregroundIconShadowOpacity > 0
    }
    /// Test accessor: transcript keeps a readable support surface.
    var testTranscriptUsesReadableSupportSurface: Bool {
        Constants.transcriptTextOpacity == 0.96
            && Constants.transcriptShadowOpacity == 0.42
            && Constants.transcriptSupportFillOpacity == 0.10
            && Constants.transcriptSupportStrokeOpacity == 0.10
            && Constants.transcriptSupportStrokeWidth == 0.8
    }
    /// Test accessor: waveform keeps restrained graphite HUD accents.
    var testWaveformUsesRestrainedHudAccentPalette: Bool {
        Constants.waveformTopAccentRed == 0.62
            && Constants.waveformTopAccentGreen == 0.76
            && Constants.waveformTopAccentBlue == 0.92
            && Constants.waveformTopBaseOpacity == 0.72
            && Constants.waveformTopLevelOpacity == 0.16
            && Constants.waveformBottomAccentRed == 0.47
            && Constants.waveformBottomAccentGreen == 0.61
            && Constants.waveformBottomAccentBlue == 0.78
            && Constants.waveformBottomBaseOpacity == 0.62
            && Constants.waveformBottomLevelOpacity == 0.14
            && Constants.waveformHighlightBaseOpacity == 0.04
            && Constants.waveformHighlightLevelOpacity == 0.06
    }
    /// Test accessor: waveform keeps the approved 9-bar count.
    var testWaveformBarCount: Int { Constants.waveformBarCount }
    /// Test accessor: smoothed bar levels array.
    var testSmoothedBarLevels: [CGFloat] { viewModel.smoothedBarLevels }
    /// Test accessor for `hasEnteredProcessing` state.
    var testHasEnteredProcessing: Bool { viewModel.hasEnteredProcessing }
    /// Test accessor for `recordingStartDate`.
    var testRecordingStartDate: Date? { viewModel.recordingStartDate }
    static func testEllipsisFrame(step: Int) -> String { ellipsisFrame(step: step) }
    func testScheduleDismissForRestartRace() -> UInt64 {
        dismissGeneration &+= 1
        return dismissGeneration
    }
    func testCompleteScheduledDismiss(token: UInt64) {
        completeScheduledDismiss(generation: token)
    }
    func testCompletePendingDismiss() {
        completeScheduledDismiss(generation: dismissGeneration)
    }
    #endif

}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = MicIndicatorOverlay.Constants.panelCornerRadius
        layer?.masksToBounds = true
    }
}

@MainActor
private final class MicIndicatorViewModel: ObservableObject {
    @Published var level: CGFloat = MicIndicatorOverlay.Constants.baselineLevel
    @Published var displayLines: [MicIndicatorOverlay.DisplayLine] = []
    @Published var panelHeight: CGFloat = MicIndicatorOverlay.Constants.baseHeight
    @Published var transcriptViewportHeight: CGFloat = 0
    @Published var isOverlayActive: Bool = false
    @Published var hasTranscript: Bool = false
    @Published var overlayStatus: OverlayStatus = .idle
    @Published var appIcon: NSImage?
    @Published var recordingStartDate: Date?
    @Published var levelHistory: [CGFloat] = []
    @Published var hasEnteredProcessing: Bool = false
    @Published var inputWarning: String?
    /// Smoothed per-bar levels for the 9-bar bouncing waveform.
    var smoothedBarLevels: [CGFloat] = Array(
        repeating: 0,
        count: MicIndicatorOverlay.Constants.waveformBarCount
    )

    static let maxLevelHistory = 30
}

private struct MicIndicatorView: View {
    @ObservedObject var viewModel: MicIndicatorViewModel
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private let fastInterval: TimeInterval = 1.0 / 30.0
    private let slowInterval: TimeInterval = 1.0 / 8.0

    init(viewModel: MicIndicatorViewModel, width: CGFloat) {
        self.viewModel = viewModel
        self.width = width
    }

    private var visualizerState: VisualizerState {
        switch viewModel.overlayStatus {
        case .transcribing: return .transcribing
        case .aiEnhance: return .aiEnhance
        case .copiedToClipboard: return .ready
        default: break
        }
        if viewModel.level >= MicIndicatorOverlay.Constants.listeningThreshold {
            return .listening
        } else if viewModel.level >= MicIndicatorOverlay.Constants.idleThreshold {
            return .ready
        } else {
            return .idle
        }
    }

    private var shouldRunFastLoop: Bool {
        viewModel.isOverlayActive
            && (visualizerState != .idle || viewModel.hasTranscript)
    }

    private var timelineInterval: TimeInterval {
        shouldRunFastLoop ? fastInterval : slowInterval
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: timelineInterval)) { timeline in
            let transcriptViewportHeight = viewModel.transcriptViewportHeight
            let transcriptVisible = transcriptViewportHeight > 0
            let panelCornerRadius = MicIndicatorOverlay.Constants.panelCornerRadius

            ZStack(alignment: .top) {
                panelSurface(cornerRadius: panelCornerRadius)
                scanLineOverlay(cornerRadius: panelCornerRadius)
                panelHighlights(cornerRadius: panelCornerRadius)
                panelBorder(cornerRadius: panelCornerRadius)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    waveformSection(visualizerState: visualizerState, timelineDate: timeline.date)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if let warning = viewModel.inputWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .accessibilityElement(children: .combine)
                    }

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
            .shadow(color: Color.black.opacity(MicIndicatorOverlay.Constants.panelShadowOpacity), radius: 20, x: 0, y: 10)
        }
    }

    @ViewBuilder
    private func panelSurface(cornerRadius: CGFloat) -> some View {
        switch MicIndicatorOverlay.Constants.surfaceStyle {
        case .graphiteHUD:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MicIndicatorOverlay.Constants.panelTopColor,
                            MicIndicatorOverlay.Constants.panelBottomColor
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
                                    Color(red: 0.63, green: 0.90, blue: 1.00)
                                        .opacity(MicIndicatorOverlay.Constants.panelHighlightOpacity),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        case .liquidGlass:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        case .ultraThinMaterial:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        }
    }

    private func panelHighlights(cornerRadius: CGFloat) -> some View {
        ZStack {
            // Top-left edge catch — simulates a panel edge catching ambient light
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.13),
                            Color(red: 0.47, green: 0.84, blue: 1.00).opacity(0.07),
                            Color.clear,
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            MicIndicatorOverlay.Constants.radialHighlightColor,
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .blendMode(.screen)
        }
    }

    private func panelBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        MicIndicatorOverlay.Constants.borderTopColor,
                        MicIndicatorOverlay.Constants.borderMidColor,
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                    .blur(radius: 1.2)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                    )
            )
    }

    private func scanLineOverlay(cornerRadius: CGFloat) -> some View {
        Canvas { context, size in
            let spacing = MicIndicatorOverlay.Constants.scanLineSpacing
            let lineCount = Int(size.height / spacing) + 1
            for i in 0..<lineCount {
                let y = CGFloat(i) * spacing
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(Color.white.opacity(MicIndicatorOverlay.Constants.scanLineOpacity)),
                    lineWidth: 0.5
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }

    private func cornerAccentOverlay(cornerRadius: CGFloat) -> some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let len = MicIndicatorOverlay.Constants.cornerAccentLength
            let thick = MicIndicatorOverlay.Constants.cornerAccentThickness
            let pad = MicIndicatorOverlay.Constants.cornerAccentPadding
            let color = MicIndicatorOverlay.Constants.cornerAccentColor
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: pad + len, y: pad))
                    p.addLine(to: CGPoint(x: pad, y: pad))
                    p.addLine(to: CGPoint(x: pad, y: pad + len))
                }.stroke(color, lineWidth: thick)
                Path { p in
                    p.move(to: CGPoint(x: w - pad - len, y: pad))
                    p.addLine(to: CGPoint(x: w - pad, y: pad))
                    p.addLine(to: CGPoint(x: w - pad, y: pad + len))
                }.stroke(color, lineWidth: thick)
                Path { p in
                    p.move(to: CGPoint(x: pad + len, y: h - pad))
                    p.addLine(to: CGPoint(x: pad, y: h - pad))
                    p.addLine(to: CGPoint(x: pad, y: h - pad - len))
                }.stroke(color, lineWidth: thick)
                Path { p in
                    p.move(to: CGPoint(x: w - pad - len, y: h - pad))
                    p.addLine(to: CGPoint(x: w - pad, y: h - pad))
                    p.addLine(to: CGPoint(x: w - pad, y: h - pad - len))
                }.stroke(color, lineWidth: thick)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func panelCornerTransparency(cornerRadius: CGFloat) -> some View {
        switch MicIndicatorOverlay.Constants.cornerTransparencyStyle {
        case .roundedClip:
            Color.clear
        case .hardCutout:
            GeometryReader { geometry in
                ZStack {
                    cornerCutout(
                        center: CGPoint(x: 0, y: 0),
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                    cornerCutout(
                        center: CGPoint(x: geometry.size.width, y: 0),
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                    cornerCutout(
                        center: CGPoint(x: 0, y: geometry.size.height),
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                    cornerCutout(
                        center: CGPoint(x: geometry.size.width, y: geometry.size.height),
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .softFade:
            GeometryReader { geometry in
                ZStack {
                    cornerFade(
                        at: .topLeading,
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                    cornerFade(
                        at: .topTrailing,
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                    cornerFade(
                        at: .bottomLeading,
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                    cornerFade(
                        at: .bottomTrailing,
                        radius: MicIndicatorOverlay.Constants.cornerCutoutRadius
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private func cornerCutout(center: CGPoint, radius: CGFloat) -> some View {
        Circle()
            .fill(Color.black)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }

    private func cornerFade(at point: UnitPoint, radius: CGFloat) -> some View {
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

    private func animatedEllipsis(at date: Date) -> String {
        guard !accessibilityReduceMotion else { return "..." }
        let step = Int((date.timeIntervalSinceReferenceDate / 0.28).rounded(.down))
        return MicIndicatorOverlay.ellipsisFrame(step: step)
    }

    private func transcriptSection(
        lines: [MicIndicatorOverlay.DisplayLine],
        viewportHeight: CGFloat
    ) -> some View {
        let clampedHeight = max(viewportHeight, 0)
        let shouldShowIndicators = lines.count > MicIndicatorOverlay.Constants.maxTranscriptLines
        let textTransition = AnyTransition.move(edge: .bottom).combined(with: .opacity)
        let verticalPadding = MicIndicatorOverlay.Constants.transcriptScrollVerticalPadding / 2

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: shouldShowIndicators) {
                VStack(
                    alignment: .leading,
                    spacing: MicIndicatorOverlay.Constants.transcriptLineSpacing
                ) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(MicIndicatorOverlay.Constants.transcriptTextOpacity))
                            .shadow(color: Color.black.opacity(MicIndicatorOverlay.Constants.transcriptShadowOpacity), radius: 1.4, x: 0, y: 1)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .transition(textTransition)
                    }
                }
                .frame(minHeight: clampedHeight, alignment: .top)
                .padding(.vertical, verticalPadding)
            }
            .frame(height: clampedHeight)
            .onAppear {
                scrollToLatest(proxy: proxy, lineID: lines.last?.id, animated: false)
            }
            .onChange(of: lines.last?.id) { _, newValue in
                scrollToLatest(proxy: proxy, lineID: newValue, animated: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MicIndicatorOverlay.Constants.transcriptCornerRadius, style: .continuous)
                .fill(Color.black.opacity(MicIndicatorOverlay.Constants.transcriptSupportFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: MicIndicatorOverlay.Constants.transcriptCornerRadius, style: .continuous)
                        .stroke(
                            Color.white.opacity(MicIndicatorOverlay.Constants.transcriptSupportStrokeOpacity),
                            lineWidth: MicIndicatorOverlay.Constants.transcriptSupportStrokeWidth
                        )
                )
        )
    }

    private func scrollToLatest(proxy: ScrollViewProxy, lineID: UUID?, animated: Bool) {
        guard let lineID else { return }

        let scrollAction = {
            proxy.scrollTo(lineID, anchor: .bottom)
        }

        if animated {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.22)) {
                    scrollAction()
                }
            }
        } else {
            DispatchQueue.main.async(execute: scrollAction)
        }
    }

    private func waveformSection(
        visualizerState: VisualizerState,
        timelineDate: Date
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            leadingAccessory
                .frame(width: MicIndicatorOverlay.Constants.waveformSideSlotWidth, alignment: .leading)
            bouncingWaveform()
                .frame(maxWidth: .infinity, alignment: .center)
            trailingAccessory(visualizerState: visualizerState, timelineDate: timelineDate)
                .frame(width: MicIndicatorOverlay.Constants.waveformSideSlotWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if let appIcon = viewModel.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Color.black.opacity(MicIndicatorOverlay.Constants.foregroundIconShadowOpacity), radius: 2, x: 0, y: 1)
                .background(accessoryBackground)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.white.opacity(0.82))
                .shadow(color: Color.black.opacity(MicIndicatorOverlay.Constants.foregroundSecondaryShadowOpacity), radius: 1.4, x: 0, y: 1)
                .frame(width: 32, height: 32)
                .background(accessoryBackground)
        }
    }

    @ViewBuilder
    private func trailingAccessory(visualizerState: VisualizerState, timelineDate: Date) -> some View {
        if let start = viewModel.recordingStartDate {
            Group {
                if let processingLabel = viewModel.overlayStatus.processingLabel,
                   visualizerState == .transcribing || visualizerState == .aiEnhance
                     || viewModel.overlayStatus == .copiedToClipboard
                {
                    HStack(spacing: 0) {
                        Text(processingLabel)
                        reservedEllipsisSlot(animatedEllipsis(at: timelineDate))
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .shadow(color: Color.black.opacity(MicIndicatorOverlay.Constants.foregroundContrastShadowOpacity), radius: 1.4, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [
                                Color(red: 0.41, green: 0.88, blue: 1.00).opacity(0.0),
                                Color(red: 0.41, green: 0.88, blue: 1.00).opacity(0.42),
                                Color(red: 0.41, green: 0.88, blue: 1.00).opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1)
                        .offset(y: 6)
                    }
                } else {
                    TimelineView(.animation(minimumInterval: 1.0)) { timeline in
                        let elapsed = Int(timeline.date.timeIntervalSince(start))
                        Text(formatDuration(elapsed))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(MicIndicatorOverlay.Constants.timeTextColor.opacity(0.90))
                            .shadow(color: Color.black.opacity(MicIndicatorOverlay.Constants.foregroundContrastShadowOpacity), radius: 1.4, x: 0, y: 1)
                    }
                }
            }
            .frame(width: MicIndicatorOverlay.Constants.waveformSideSlotWidth, alignment: .trailing)
            .fixedSize()
        } else {
            Color.clear
                .frame(width: MicIndicatorOverlay.Constants.waveformSideSlotWidth, height: 24)
        }
    }

    private func reservedEllipsisSlot(_ ellipsis: String) -> some View {
        Text(MicIndicatorOverlay.Constants.processingEllipsisTemplate)
            .monospaced()
            .hidden()
            .overlay(alignment: .leading) {
                Text(ellipsis)
                    .monospaced()
                    .foregroundStyle(Color(red: 0.66, green: 0.94, blue: 1.00).opacity(0.96))
            }
    }

    private var accessoryBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(accessoryBackgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color(red: 0.38, green: 0.80, blue: 1.00).opacity(0.24),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    private var accessoryBackgroundOpacity: Double {
        switch MicIndicatorOverlay.Constants.accessoryStyle {
        case .minimalChrome:
            0
        case .floatingChip:
            0.14
        }
    }

    /// 9-bar vertical bouncing waveform driven by real-time RMS audio level.
    /// Bar weights [0.28, 0.42, 0.58, 0.78, 1.0, 0.82, 0.64, 0.46, 0.30] create a center-high, sides-low effect.
    /// Smooth envelope (attack 55%, release 15%) with ±6% random jitter per bar.
    private func bouncingWaveform() -> some View {
        let barCount = MicIndicatorOverlay.Constants.waveformBarCount
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
                        MicIndicatorOverlay.Constants.waveformTopColor
                            .opacity(MicIndicatorOverlay.Constants.waveformTopBaseOpacity
                                + Double(smoothed) * MicIndicatorOverlay.Constants.waveformTopLevelOpacity),
                        MicIndicatorOverlay.Constants.waveformBottomColor
                            .opacity(MicIndicatorOverlay.Constants.waveformBottomBaseOpacity
                                + Double(smoothed) * MicIndicatorOverlay.Constants.waveformBottomLevelOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: barHeight)
                    .shadow(
                        color: Color.white.opacity(
                            MicIndicatorOverlay.Constants.waveformHighlightBaseOpacity
                                + Double(smoothed) * MicIndicatorOverlay.Constants.waveformHighlightLevelOpacity
                        ),
                        radius: 2,
                        x: 0,
                        y: 0
                    )
                    .animation(.easeOut(duration: 0.05), value: smoothed)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .frame(height: maxBarHeight)
    }

    @discardableResult
    private func updateSmoothedLevel(at index: Int, target: CGFloat, attack: CGFloat, release: CGFloat) -> Bool {
        let prev = viewModel.smoothedBarLevels[index]
        let isAttack = target > prev
        let coeff = isAttack ? attack : release
        viewModel.smoothedBarLevels[index] = coeff * target + (1 - coeff) * prev
        return true
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private enum VisualizerState: Equatable {
        case idle
        case ready
        case listening
        case transcribing
        case aiEnhance
    }
}

extension MicIndicatorOverlay {
    fileprivate static func ellipsisFrame(step: Int) -> String {
        let frames = [".", "..", "...", ".", "..", "..."]
        let index = abs(step) % frames.count
        return frames[index]
    }
}

extension CGFloat {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGRect {
    fileprivate var isValidRect: Bool {
        !isNull && !isEmpty && origin.x.isFinite && origin.y.isFinite && width.isFinite
            && height.isFinite
    }
}
