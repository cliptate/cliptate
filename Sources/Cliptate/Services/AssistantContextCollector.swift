import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox
import Vision
import os.log

struct AssistantContextSnapshot {
    let clipboardText: String?
    let screenText: String?

    var hasContext: Bool {
        !(clipboardText?.isEmpty ?? true) || !(screenText?.isEmpty ?? true)
    }
}

/// Gathers contextual text from the clipboard and on-screen content (via the Vision framework).
@MainActor
final class AssistantContextCollector {
    static let shared = AssistantContextCollector()

    private let logger = Logger(subsystem: "com.Cliptate", category: "AssistantContext")

    private init() {}

    func collectContext() async -> AssistantContextSnapshot {
        async let screenText = captureScreenText()
        let clipboard = captureClipboardText()

        let resolvedScreenText = await screenText
        return AssistantContextSnapshot(
            clipboardText: clipboard?.trimmedIfNeeded(),
            screenText: resolvedScreenText?.trimmedIfNeeded()
        )
    }

    private func captureClipboardText() -> String? {
        NSPasteboard.general.string(forType: .string)?.trimmedIfNeeded()
    }

    private func captureScreenText() async -> String? {
        guard ensureScreenCapturePermission() else {
            logger.error(
                "Screen capture permission denied. Enable it in System Settings > Privacy & Security > Screen Recording."
            )
            return nil
        }

        if let activeWindowText = await captureActiveWindowText() {
            return activeWindowText
        }

        do {
            let image = try await captureScreenImage()
            return await recognizeText(in: image)
        } catch {
            logger.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func captureActiveWindowText() async -> String? {
        do {
            guard let image = try await captureActiveWindowImage() else { return nil }
            return await recognizeText(in: image)
        } catch {
            logger.error(
                "Active window capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func captureScreenImage() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let targetDisplay = content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: targetDisplay,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = targetDisplay.width
        configuration.height = targetDisplay.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.queueDepth = 1
        if #available(macOS 13.3, *) {
            configuration.capturesAudio = false
        }

        let collector = ScreenFrameCollector()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(
            collector, type: SCStreamOutputType.screen, sampleHandlerQueue: collector.queue)
        try await stream.startCapture()

        do {
            let image = try await collector.waitForFrame()
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(collector, type: SCStreamOutputType.screen)
            return image
        } catch {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(collector, type: SCStreamOutputType.screen)
            throw error
        }
    }

    private func captureActiveWindowImage() async throws -> CGImage? {
        guard let windowInfo = activeWindowInfo() else { return nil }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        guard
            let targetWindow = content.windows.first(where: { $0.windowID == windowInfo.windowID })
        else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(targetWindow.frame.width) * 2
        configuration.height = Int(targetWindow.frame.height) * 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.queueDepth = 1

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func ensureScreenCapturePermission() -> Bool {
        if #available(macOS 10.15, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }

            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                logger.error(
                    "Screen capture permission not granted. Enable it in System Settings > Privacy & Security > Screen Recording."
                )
            }
            return granted
        }

        return true
    }

    private func activeWindowInfo() -> (windowID: CGWindowID, ownerName: String, title: String)? {
        let windowListInfo =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
            ?? []

        guard
            let frontWindow = windowListInfo.first(where: { info in
                let layer = info[kCGWindowLayer as String] as? Int32 ?? 0
                return layer == 0
            })
        else {
            return nil
        }

        guard
            let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID,
            let ownerName = frontWindow[kCGWindowOwnerName as String] as? String,
            let title = frontWindow[kCGWindowName as String] as? String
        else {
            return nil
        }

        return (windowID: windowID, ownerName: ownerName, title: title)
    }

    private func recognizeText(in image: CGImage) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]
            request.usesLanguageCorrection = true
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                let text = request.results?
                    .flatMap { $0.topCandidates(1) }
                    .map { $0.string }
                    .joined(separator: "\n")
                return text?.trimmedIfNeeded()
            } catch {
                return nil
            }
        }.value
    }
}

private enum ScreenCaptureError: Error {
    case noDisplay
}

private final class ScreenFrameCollector: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "com.cliptate.ScreenFrameCollector")
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var isCompleted = false

    func waitForFrame() async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard !isCompleted, type == SCStreamOutputType.screen,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image else { return }

        isCompleted = true
        continuation?.resume(returning: image)
        continuation = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !isCompleted else { return }
        isCompleted = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension String {
    fileprivate func trimmedIfNeeded() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
