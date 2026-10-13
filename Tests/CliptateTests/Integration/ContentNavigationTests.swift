import Foundation
import SwiftUI
import Testing

@testable import Cliptate

@Suite("Content navigation")
struct ContentNavigationTests {
  @Test("sidebar groups keep creation, library, and app destinations together")
  func sidebarGroups() {
    #expect(AppSidebarGroup.create.sections(requiresGettingStarted: false) == [.aiCut, .voiceToText, .ttsStudio])
    #expect(AppSidebarGroup.library.sections(requiresGettingStarted: false) == [.history, .models, .dictionary])
    let appSections: [AppSection] = SubscriptionPolicy.isBillingEnabled ? [.pro, .setting] : [.setting]
    #expect(AppSidebarGroup.app.sections(requiresGettingStarted: false) == appSections)
    #expect(AppSidebarGroup.app.sections(requiresGettingStarted: true) == [.permissions] + appSections)
  }

  @Test("grouped sidebar includes every available destination exactly once", arguments: [false, true])
  func sidebarDestinationCoverage(requiresGettingStarted: Bool) {
    let sections = visibleAppSections(requiresGettingStarted: requiresGettingStarted)
    let expected = AppSection.allCases.filter {
      (requiresGettingStarted || $0 != .permissions)
        && (SubscriptionPolicy.isBillingEnabled || $0 != .pro)
    }
    #expect(Set(sections) == Set(expected))
    #expect(sections.count == Set(sections).count)
  }

  @Test("getting started section label and description are exposed")
  func gettingStartedSectionMetadata() {
    #expect(AppSection.permissions.label == LocalizedStringKey("Getting Started"))
    #expect(AppSection.permissions.description == "Permissions and setup guidance")
  }

  @Test("permissions section is hidden when onboarding guidance is not required")
  func permissionsSectionIsHiddenWhenGuidanceNotRequired() {
    #expect(visibleAppSections(requiresGettingStarted: false).contains(.permissions) == false)
    #expect(visibleAppSections(requiresGettingStarted: true).contains(.permissions))
  }

  @Test("missing permissions force navigation to getting started")
  func missingPermissionsForceGettingStartedNavigation() {
    #expect(resolvedAppSection(currentSection: .aiCut, requiresGettingStarted: true) == .permissions)
    #expect(
      resolvedAppSection(currentSection: .permissions, requiresGettingStarted: false) == .aiCut
    )
    #expect(resolvedAppSection(currentSection: .models, requiresGettingStarted: false) == .models)
  }

  @Test("explicit user navigation can leave getting started while permissions are still missing")
  func explicitUserNavigationCanLeaveGettingStartedWhilePermissionsAreStillMissing() {
    #expect(
      resolvedAppSection(
        currentSection: .voiceToText,
        requiresGettingStarted: true,
        autoOpenGettingStarted: false
      ) == .voiceToText
    )
  }

  @Test("content view refreshes permissions without auto-redirect on app reactivation")
  func contentViewRefreshesPermissionsWithoutAutoRedirectOnAppReactivation() throws {
    let content = try contentViewSource()
    let marker =
      ".onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))"

    guard let range = content.range(of: marker) else {
      Issue.record("Expected didBecomeActiveNotification observer in ContentView")
      return
    }

    let suffix = String(content[range.lowerBound...])
    let observedBlock = String(suffix.prefix(160))

    #expect(observedBlock.contains("permissionStatusManager.refreshAll()"))
    #expect(observedBlock.contains("syncGettingStartedSection()") == false)
  }

  @Test("pro navigation is available only in the billing channel")
  func proSectionIsAvailableInNavigation() {
    #expect(visibleAppSections(requiresGettingStarted: false).contains(.pro) == SubscriptionPolicy.isBillingEnabled)
    #expect(AppSection.pro.icon == "crown")
    #expect(AppSection.pro.description == (SubscriptionPolicy.isBillingEnabled
      ? "Subscription and benefits" : "All features are free"))
  }

  @Test("restored pro selection returns to AI Cut in the free channel")
  func restoredProSelection() {
    #expect(resolvedAppSection(currentSection: .pro, requiresGettingStarted: false)
      == (SubscriptionPolicy.isBillingEnabled ? .pro : .aiCut))
    #expect(resolvedAppSection(currentSection: .pro, requiresGettingStarted: true) == .permissions)
  }

  @Test("pro section notification is available")
  func proSectionNotificationIsAvailable() {
    #expect(Notification.Name.openProSection.rawValue == "Cliptate.openProSection")
  }

  @Test("content view defers shortcut result handling to VoiceToText when that section is active")
  func contentViewDefersShortcutHandlingForVoiceToText() {
    #expect(contentViewShouldHandleShortcutResult(currentSection: .voiceToText) == false)
    #expect(contentViewShouldHandleShortcutResult(currentSection: .aiCut) == true)
  }

  @Test("permissions keyboard shortcut button uses direct content navigation")
  func permissionsKeyboardShortcutButtonUsesDirectContentNavigation() throws {
    let content = try contentViewSource()

    #expect(
      content.contains("PermissionsView(onOpenVoiceToText: { currentSection = .voiceToText })")
    )
  }

  private func contentViewSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent("Sources/Cliptate/Views/ContentView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
