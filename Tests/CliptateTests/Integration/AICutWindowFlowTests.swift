import CliptateCore
import Foundation
import SwiftUI
import Testing

@testable import Cliptate

#if os(macOS)
  import AppKit
#endif

@Suite("AI Cut window flow", .serialized)
@MainActor
struct AICutWindowFlowTests {
  @Test("editor source mode removes import affordances")
  func editorSourceModeRemovesImportAffordances() async throws {
    #expect(AICutEditorSourceMode.editingOnly.showsAddButton == false)
    #expect(AICutEditorSourceMode.editingOnly.showsDropZone == false)
    #expect(AICutEditorSourceMode.importable.showsAddButton == true)
    #expect(AICutEditorSourceMode.importable.showsDropZone == true)
  }

  @Test("window coordinator closes progress before opening editor")
    func windowCoordinatorClosesProgressBeforeOpeningEditor() async throws {
      let coordinator = AICutWindowCoordinator()
      coordinator.markProgressWindowOpenForTesting()
      coordinator.transitionFromProgressToEditorForTesting()
      #expect(coordinator.lastTransitionEvents == [.closeProgressWindow, .openEditorWindow, .activateEditorWindow])
      coordinator.resetForTesting()
      try await Task.sleep(nanoseconds: 50_000_000)
  }

  #if os(macOS)
    @Test("editor window adopts the main app window size during handoff")
    func editorWindowAdoptsMainAppWindowSizeDuringHandoff() async throws {
      let coordinator = AICutWindowCoordinator()
      let appWindow = NSWindow(
        contentRect: NSRect(x: 40, y: 40, width: 1660, height: 1040),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      appWindow.title = "VoiceFlow Pro"
      appWindow.orderOut(nil)
      defer {
        appWindow.contentViewController = nil
        appWindow.contentView = nil
        appWindow.orderOut(nil)
      }

      coordinator.markProgressWindowOpenForTesting(sourceWindow: appWindow)
      coordinator.transitionFromProgressToEditorForTesting()

      // Read the editor window from the coordinator directly to avoid finding
      // a stale "AI Cut Editor" window left open by a previous test.
      let editorWindow = coordinator.editorWindowForTesting
      #expect(editorWindow?.frame.size.width == appWindow.frame.size.width)
      #expect(editorWindow?.frame.size.height == appWindow.frame.size.height)

      coordinator.resetForTesting()
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    @Test("detached session manager opens one independent window per import")
    func detachedSessionManagerOpensIndependentWindowPerImport() async throws {
      let manager = AICutDetachedSessionWindowManager()
      manager.resetForTesting()

      let firstWindow = manager.openSessionWindowForTesting(
        urls: [URL(fileURLWithPath: "/tmp/first.mov")],
        config: AppConfiguration.shared
      )
      let secondWindow = manager.openSessionWindowForTesting(
        urls: [URL(fileURLWithPath: "/tmp/second.mov")],
        config: AppConfiguration.shared
      )

      #expect(firstWindow !== secondWindow)
      #expect(manager.activeDetachedWindowCount == 2)

      manager.resetForTesting()
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  #endif

  @Test("window coordinator runs transition hook before editor window opens")
  func windowCoordinatorRunsTransitionHookBeforeEditorWindowOpens() async throws {
    let coordinator = AICutWindowCoordinator()
    coordinator.markProgressWindowOpenForTesting()

    var didRunBeforeOpen = false
    coordinator.transitionFromProgressToEditorForTesting {
      didRunBeforeOpen = true
    }

    #expect(didRunBeforeOpen)
    #expect(
      coordinator.lastTransitionEvents == [
        .closeProgressWindow,
        .runBeforeOpenAction,
        .openEditorWindow,
        .activateEditorWindow,
      ]
    )
  }

  @Test("window coordinator notifies when editor window closes")
  func windowCoordinatorNotifiesWhenEditorWindowCloses() async throws {
    let coordinator = AICutWindowCoordinator()
    coordinator.markProgressWindowOpenForTesting()

    var didNotifyClose = false
    coordinator.transitionFromProgressToEditorForTesting(
      onEditorClose: {
        didNotifyClose = true
      }
    )

    coordinator.simulateEditorWindowCloseForTesting()

    #expect(didNotifyClose)
    #expect(
      coordinator.lastTransitionEvents == [
        .closeProgressWindow,
        .openEditorWindow,
        .activateEditorWindow,
        .notifyEditorWindowClosed,
      ]
    )
  }

  @Test("import guard blocks while transcription task is still unwinding")
  func importGuardBlocksDuringTranscriptionTeardown() async throws {
    let message = AICutImportGuard.blockingMessage(
      phase: .landing,
      hasPendingTranscriptionTask: true
    )

    #expect(
      message
        == "Please wait for the current File Transcription to finish cancelling before starting another import."
    )
  }

  @Test("import guard keeps editing block message when editor is active")
  func importGuardKeepsEditingBlockMessage() async throws {
    let message = AICutImportGuard.blockingMessage(
      phase: .editing,
      hasPendingTranscriptionTask: true
    )

    #expect(message == "Close the current File Transcription editor before importing more videos.")
  }

  @Test("transcription task guard ignores stale finished generations")
  func transcriptionTaskGuardIgnoresStaleFinishedGenerations() async throws {
    #expect(
      AICutTranscriptionTaskGuard.shouldClearActiveTask(
        finishedGeneration: 1,
        activeGeneration: 2
      ) == false
    )
    #expect(
      AICutTranscriptionTaskGuard.shouldClearActiveTask(
        finishedGeneration: 2,
        activeGeneration: 2
      ) == true
    )
  }

  @Test("session guard ignores stale editor session generations")
  func sessionGuardIgnoresStaleEditorSessionGenerations() async throws {
    #expect(
      AICutSessionGuard.shouldApplyUpdate(
        capturedGeneration: 3,
        activeGeneration: 4
      ) == false
    )
    #expect(
      AICutSessionGuard.shouldApplyUpdate(
        capturedGeneration: 4,
        activeGeneration: 4
      ) == true
    )
  }

  @Test("model preparation status includes ETA when available")
  func modelPreparationStatusIncludesETAWhenAvailable() async throws {
    let progress = ModelDownloadProgress(
      currentStep: "Downloading model",
      progress: 0.4,
      estimatedTimeRemaining: 75
    )

    #expect(
      AICutModelPreparationStatus.message(for: progress)
        == "Downloading model (ETA: 1m 15s)"
    )
    #expect(
      AICutModelPreparationStatus.message(
        for: ModelDownloadProgress(currentStep: "Preparing model", progress: 0.9)
      ) == "Preparing model"
    )
  }

  @Test("batch failure status surfaces the underlying preparation error")
  func batchFailureStatusSurfacesUnderlyingPreparationError() async throws {
    let error = NSError(
      domain: "AICut",
      code: 100,
      userInfo: [NSLocalizedDescriptionKey: "Please download Parakeet V3 first."]
    )

    #expect(
      AICutTranscriptionFailureStatus.batchMessage(for: error)
        == "Batch transcription failed: Please download Parakeet V3 first."
    )
  }

  #if os(macOS)
    @Test("editor view constructs with an explicit security scope manager")
    func editorViewRendersWithExplicitSecurityScopeManager() async throws {
      let editor = AICutEditorView(
        securityScopeManager: SecurityScopedURLAccessManager(),
        selectedVideoURLs: .constant([]),
        activeVideoURL: .constant(nil),
        sourceMode: .editingOnly,
        videoStates: [:],
        statusText: "Transcribing...",
        modelDownloadProgress: nil,
        isInitializingModel: false,
        batchTranscriptionProgress: (current: 1, total: 1),
        isTranscribing: true,
        isExporting: false,
        exportProgress: ExportProgressState(),
        isAICorrecting: false,
        isAIEnhancing: false,
        isTranslating: false,
        activeVideoState: nil,
        processedSegments: [],
        translationsVersion: 0,
        currentPlayback: VideoPlaybackCoordinator(),
        previewSegments: [],
        previewEffects: [:],
        onSelectFiles: {},
        onImportURLs: { _ in },
        onTranscribe: {},
        onTranscribeAll: {},
        onCancelTranscription: {},
        onExportAll: { _ in },
        onExportSingle: { _ in },
        onAICorrect: {},
        onAICorrectCurrent: {},
        onRestoreOriginal: {},
        onAIEnhance: {},
        onTranslate: {},
        onPreviewSegmentDelete: { _ in },
        onSegmentUpdate: { _, _ in },
        onTranslationUpdate: { _, _ in },
        onSegmentDelete: { _ in }
      )
      .environmentObject(AppConfiguration.shared)
      _ = editor
    }
  #endif
}
