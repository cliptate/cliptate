import AVFoundation
import AppKit
import CoreGraphics
import KeyboardShortcuts
import SwiftUI

private enum PermissionState {
  case granted
  case denied
  case pending
  case unknown

  var label: String {
    switch self {
    case .granted:
      return String(localized: "Granted", comment: "Permission state label")
    case .denied:
      return String(localized: "Denied", comment: "Permission state label")
    case .pending:
      return String(localized: "Pending", comment: "Permission state label")
    case .unknown:
      return String(localized: "Unknown", comment: "Permission state label")
    }
  }

  var tint: Color {
    switch self {
    case .granted: return .green
    case .denied: return .orange
    case .pending: return .yellow
    case .unknown: return .gray
    }
  }

  var symbolName: String {
    switch self {
    case .granted: return "checkmark.seal.fill"
    case .denied: return "xmark.seal.fill"
    case .pending: return "questionmark.diamond.fill"
    case .unknown: return "exclamationmark.triangle.fill"
    }
  }
}

@MainActor
final class PermissionStatusManager: ObservableObject {
  static let shared = PermissionStatusManager()

  @Published var microphoneStatus: AVAuthorizationStatus =
    AVCaptureDevice.authorizationStatus(for: .audio)
  @Published var isAccessibilityEnabled = false
  @Published var isScreenRecordingEnabled = false
  @Published var hasShortcut = false

  var requiresGettingStarted: Bool {
    let requiresCorePermissions = microphoneStatus != .authorized || !isScreenRecordingEnabled
    return requiresCorePermissions || (AccessibilityGate.isSupported && !isAccessibilityEnabled)
  }

  init() {
    refreshAll()
  }

  func refreshAll() {
    refreshMicrophone()
    refreshAccessibility()
    refreshScreenRecording()
    refreshKeyboardShortcut()
  }

  func refreshMicrophone() {
    microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
  }

  func requestMicrophone() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        self.microphoneStatus = granted ? .authorized : .denied
      }
    }
  }

  func refreshAccessibility() {
    isAccessibilityEnabled = AccessibilityGate.isProcessTrusted
  }

  func refreshScreenRecording() {
    isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
  }

  func requestScreenRecording() {
    CGRequestScreenCaptureAccess()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.refreshScreenRecording()
    }
  }

  @MainActor
  func refreshKeyboardShortcut() {
    // Shortcuts are always available (Right ⌘ for dictation, Right ⌘ + Right ⇧ for assistant)
    hasShortcut = true
  }
}

struct PermissionsView: View {
  @ObservedObject private var manager = PermissionStatusManager.shared
  let onOpenVoiceToText: () -> Void

  init(
    onOpenVoiceToText: @escaping () -> Void = {
      NotificationCenter.default.post(name: .openVoiceToText, object: nil)
    }
  ) {
    self.onOpenVoiceToText = onOpenVoiceToText
  }

  private let microphoneSettingsURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
  private let screenRecordingSettingsURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  private let accessibilitySettingsURL =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack(spacing: 14) {
          PermissionCard(
            icon: "keyboard",
            title: String(localized: "Keyboard Shortcuts", comment: "Getting started card title"),
            message: String(
              localized: "Set up quick toggles for dictation and assistant modes.",
              comment: "Getting started keyboard shortcut guidance"
            ),
            state: manager.hasShortcut ? .granted : .pending,
            buttonTitle: manager.hasShortcut
              ? String(
                localized: "Manage in Voice Dictation",
                comment: "Button to open voice to text settings"
              )
              : String(localized: "Set up shortcut", comment: "Button to configure shortcuts"),
            action: onOpenVoiceToText,
            refresh: { manager.refreshKeyboardShortcut() }
          )

          PermissionCard(
            icon: "mic",
            title: String(localized: "Microphone Access", comment: "Getting started card title"),
            message: String(localized: "Allow Cliptate to capture your voice for live transcription.", comment: "Microphone permission request message"),
            state: microphoneState,
            buttonTitle: microphoneButtonTitle,
            action: handleMicrophoneAction,
            refresh: { manager.refreshMicrophone() }
          )

          if AccessibilityGate.isSupported {
            PermissionCard(
              icon: "doc.on.clipboard",
              title: String(
                localized: "Enable hands-free text insertion",
                comment: "Accessibility permission title"
              ),
              message: [
                String(
                  localized:
                    "This allows Cliptate to insert the text you dictate directly into any app.",
                  comment: "Accessibility permission benefit copy"
                ),
                String(
                  localized: "Without this permission, Cliptate cannot enter the text you speak.",
                  comment: "Accessibility permission missing-permission copy"
                ),
              ].joined(separator: " "),
              state: manager.isAccessibilityEnabled ? .granted : .pending,
              buttonTitle: String(
                localized: "Open Accessibility Settings",
                comment: "Button to open macOS Accessibility settings"
              ),
              action: handleAccessibilityAction,
              refresh: { manager.refreshAccessibility() }
            )
          }

          PermissionCard(
            icon: "rectangle.on.rectangle",
            title: String(localized: "Screen Recording", comment: "Getting started card title"),
            message: String(
              localized: "Allow on-screen text capture to improve assistant context.",
              comment: "Screen recording permission guidance"
            ),
            state: manager.isScreenRecordingEnabled ? .granted : .denied,
            buttonTitle: manager.isScreenRecordingEnabled
              ? String(
                localized: "Open System Settings",
                comment: "Button to open macOS System Settings"
              )
              : String(localized: "Continue", comment: "Button to continue to permission prompt"),
            action: handleScreenRecordingAction,
            refresh: { manager.refreshScreenRecording() }
          )
        }
      }
      .padding(24)
    }
    .background(AppSurface.pageBackground)
    .appPageHeader {
      AppPageHeader {
        header
      }
    }
    .onAppear { manager.refreshAll() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in
      manager.refreshAll()
    }
  }

  private var microphoneState: PermissionState {
    switch manager.microphoneStatus {
    case .authorized: return .granted
    case .denied, .restricted: return .denied
    case .notDetermined: return .pending
    @unknown default: return .unknown
    }
  }

  private var microphoneButtonTitle: String {
    switch manager.microphoneStatus {
    case .notDetermined:
      return String(localized: "Continue", comment: "Button to continue to permission prompt")
    case .authorized:
      return String(
        localized: "Open System Settings",
        comment: "Button to open macOS System Settings"
      )
    default:
      return String(
        localized: "Open System Settings",
        comment: "Button to open macOS System Settings"
      )
    }
  }

  private func handleMicrophoneAction() {
    switch manager.microphoneStatus {
    case .notDetermined:
      manager.requestMicrophone()
    default:
      openSystemSettings(microphoneSettingsURL)
    }
  }

  private func handleAccessibilityAction() {
    openSystemSettings(accessibilitySettingsURL)
  }

  private func handleScreenRecordingAction() {
    if !manager.isScreenRecordingEnabled {
      manager.requestScreenRecording()
    }
    openSystemSettings(screenRecordingSettingsURL)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Getting Started")
        .font(.title2.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      Text("Enable the permissions below to unlock dictation and assistant features.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }

  private func openSystemSettings(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }
}

private struct PermissionCard: View {
  let icon: String
  let title: String
  let message: String
  let state: PermissionState
  let buttonTitle: String
  let action: () -> Void
  let refresh: () -> Void

  @State private var isRefreshing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(state.tint.opacity(0.15))
            .frame(width: 44, height: 44)
          Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(state.tint)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.headline)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()

        HStack(spacing: 8) {
          Button {
            withAnimation(.easeInOut(duration: 0.35)) { isRefreshing = true }
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
              withAnimation(.easeInOut(duration: 0.2)) { isRefreshing = false }
            }
          } label: {
            Image(systemName: "arrow.clockwise")
              .rotationEffect(.degrees(isRefreshing ? 360 : 0))
              .animation(.easeInOut(duration: 0.35), value: isRefreshing)
          }
          .buttonStyle(.borderless)

          Label(state.label, systemImage: state.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(state.tint)
        }
      }

      Button(action: action) {
        HStack {
          Text(buttonTitle)
            .fontWeight(.semibold)
          Spacer()
          Image(systemName: "arrow.right")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(state == .granted ? .accentColor.opacity(0.2) : .accentColor)
      .disabled(state == .granted && buttonTitle.isEmpty)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(AppSurface.cardBackground)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    )
  }
}

#Preview {
  PermissionsView()
    .environmentObject(AppConfiguration.shared)
}
