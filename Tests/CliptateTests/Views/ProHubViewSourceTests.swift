import Foundation
import Testing

@Suite("Pro hub source")
struct ProHubViewSourceTests {
  @Test("pro hub uses a unified card surface with feature highlights and plan tiers")
  func proHubUsesUnifiedCardWithFeatureHighlightsAndPlanTiers() throws {
    let content = try proHubViewSource()

    // Unified card layout — all content inside one mainCard VStack
    #expect(content.contains("mainCard"))
    // Feature highlights strip is present
    #expect(content.contains("featureHighlightsRow"))
    // Plan tiers section is present
    #expect(content.contains("planTiersSection"))
    // Primary CTA is present
    #expect(content.contains("primaryCTAButton"))
    // Subscription status is embedded inside the card
    #expect(content.contains("proHubEmbedded"))
  }

  @Test("subscription status uses the shared card surface and secondary restore button")
  func subscriptionStatusUsesSharedCardSurfaceAndSecondaryRestoreButton() throws {
    let content = try subscriptionStatusViewSource()

    // Card wrapping is conditional (embedded vs standalone mode)
    #expect(content.contains("OptionalCardModifier"))
    #expect(content.contains(#"Label("Restore Purchases""#))
    #expect(content.contains(".buttonStyle(.borderedProminent)") == false)
  }

  private func proHubViewSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent("Sources/Cliptate/Views/ProHubView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }

  private func subscriptionStatusViewSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent(
      "Sources/Cliptate/Views/SubscriptionStatusView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
