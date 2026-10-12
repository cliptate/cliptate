import Foundation
import Testing

@Suite("Permissions view source")
struct PermissionsViewSourceTests {
  @Test("accessibility permission copy uses hands-free insertion wording")
  func accessibilityPermissionCopyUsesHandsFreeInsertionWording() throws {
    let content = try permissionsViewSource()

    #expect(content.contains("#if !APP_STORE"))
    #expect(content.contains(#""Enable hands-free text insertion""#))
    #expect(
      content.contains(
        #""This allows Cliptate to insert the text you dictate directly into any app.""#
      )
    )
    #expect(
      content.contains(#""Without this permission, Cliptate cannot enter the text you speak.""#)
    )
    #expect(content.contains(#""Open Accessibility Settings""#))
  }

  @Test("permission prompt buttons use continue wording")
  func permissionPromptButtonsUseContinueWording() throws {
    let content = try permissionsViewSource()

    #expect(content.contains(#"String(localized: "Continue", comment: "Button to continue to permission prompt")"#))
    #expect(content.contains(#""Request permission""#) == false)
  }

  @Test("permissions view localizes all user-facing onboarding copy")
  func permissionsViewLocalizesAllUserFacingOnboardingCopy() throws {
    let content = try permissionsViewSource()

    #expect(content.contains(#"title: String(localized: "Keyboard Shortcuts""#))
    #expect(content.contains(#"localized: "Set up quick toggles for dictation and assistant modes.""#))
    #expect(content.contains(#"title: String(localized: "Microphone Access""#))
    #expect(content.contains(#"title: String(localized: "Screen Recording""#))
    #expect(content.contains(#"localized: "Allow on-screen text capture to improve assistant context.""#))
    #expect(content.contains(#"Text("Getting Started")"#))
    #expect(
      content.contains(#"Text("Enable the permissions below to unlock dictation and assistant features.")"#)
    )
    #expect(content.contains(#"title: "Keyboard Shortcuts""#) == false)
    #expect(content.contains(#"title: "Microphone Access""#) == false)
    #expect(content.contains(#"title: "Screen Recording""#) == false)
  }

  @Test("accessibility permission check never requests the system prompt")
  func accessibilityPermissionCheckNeverRequestsTheSystemPrompt() throws {
    // The Accessibility trust check lives behind AccessibilityGate; verify there
    // that it uses the non-prompting variant and never the prompting one.
    let content = try accessibilityGateSource()

    #expect(content.contains("return AXIsProcessTrusted()"))
    #expect(content.contains("AXIsProcessTrustedWithOptions") == false)
    #expect(
      content.contains(
        #"[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary"#
      ) == false
    )
  }

  @Test("accessibility gate keeps protected frameworks out of app store compilation")
  func accessibilityGateKeepsProtectedFrameworksOutOfAppStoreCompilation() throws {
    let content = try accessibilityGateSource()

    #expect(content.contains("#if !APP_STORE\n  import ApplicationServices\n  import CoreGraphics\n#endif"))
  }

  @Test("mic overlay does not import accessibility framework")
  func micOverlayDoesNotImportAccessibilityFramework() throws {
    let content = try micOverlaySource()

    #expect(content.contains("import ApplicationServices") == false)
  }

  @Test("permissions view checks accessibility through the gate, not AX directly")
  func permissionsViewChecksAccessibilityThroughTheGate() throws {
    let content = try permissionsViewSource()

    #expect(content.contains("AccessibilityGate.isProcessTrusted"))
    #expect(content.contains("AccessibilityGate.isSupported"))
    #expect(content.contains("AXIsProcessTrustedWithOptions") == false)
    #expect(content.contains("requestAccessibility()") == false)
  }

  @Test("Xcode defaults Dev to direct distribution and Release to App Store")
  func defaultXcodeBuildChannels() throws {
    let content = try xcodeProjectSource()

    #expect(content.contains(#"SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited) $(CLIPTATE_CHANNEL_CONDITIONS)";"#))
    #expect(content.contains(#"SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) $(CLIPTATE_CHANNEL_CONDITIONS)";"#))
    let configuration = try projectFileSource("config/Cliptate.xcconfig")
    #expect(configuration.contains("CLIPTATE_CHANNEL_CONDITIONS = APP_STORE"))
    #expect(configuration.contains("CLIPTATE_CHANNEL_CONDITIONS[config=Debug] =\n"))
    #expect(configuration.contains("CLIPTATE_ENABLE_APP_SANDBOX[config=Debug] = NO"))
    #expect(configuration.contains("CLIPTATE_CODE_SIGN_ENTITLEMENTS[config=Debug] = $(SRCROOT)/Sources/Cliptate/Cliptate-Direct.entitlements"))
    #expect(configuration.contains("CLIPTATE_CLI_URL_SCHEME[config=Debug] = cliptate-dev-cli\n"))
  }

  @Test("generated Xcode app Info.plist declares no non-exempt encryption")
  func generatedXcodeAppInfoPlistDeclaresNoNonExemptEncryption() throws {
    let content = try xcodeProjectSource()
    let declaration = "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;"

    #expect(content.contains(declaration))
    #expect(content.components(separatedBy: declaration).count - 1 == 2)
  }

  @Test("Swift package defaults only Release to App Store and supports explicit overrides")
  func defaultSwiftPackageBuildChannels() throws {
    let content = try packageManifestSource()

    #expect(content.contains(#".define("APP_STORE")"#))
    #expect(content.contains(#".define("APP_STORE", .when(configuration: .release))"#))
    #expect(content.contains(#"case "NO": channelSwiftSettings = []"#))
  }

  @Test("Swift package keeps macOS app entry point out of raw executable builds")
  func swiftPackageKeepsMacOSAppEntryPointOutOfRawExecutableBuilds() throws {
    let content = try packageManifestSource()

    #expect(content.contains(".library("))
    #expect(content.contains(".target("))
    #expect(content.contains(#""Cliptate.swift","#))
    // A lightweight CLI is allowed; the SwiftUI app entry still belongs to Xcode.
  }

  private func permissionsViewSource() throws -> String {
    try projectFileSource("Sources/Cliptate/Views/PermissionsView.swift")
  }

  private func accessibilityGateSource() throws -> String {
    try projectFileSource("Sources/Cliptate/Utilities/AccessibilityGate.swift")
  }

  private func micOverlaySource() throws -> String {
    try projectFileSource("Sources/Cliptate/Utilities/MicIndicatorOverlay.swift")
  }

  private func xcodeProjectSource() throws -> String {
    try projectFileSource("Cliptate.xcodeproj/project.pbxproj")
  }

  private func packageManifestSource() throws -> String {
    try projectFileSource("Package.swift")
  }

  private func projectFileSource(_ relativePath: String) throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
