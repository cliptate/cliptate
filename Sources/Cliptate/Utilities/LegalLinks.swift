import Foundation

/// Centralized access to legal document links used across the app.
enum LegalLinks {
  private static let defaultPrivacyPolicy = "https://sysulq.github.io/privacy.txt"
  private static let defaultTermsOfUse =
    "https://www.apple.com/legal/internet-services/itunes/dev/stdeula"

  static var privacyPolicy: URL? {
    url(
      for: "PrivacyPolicyURL",
      fallback: defaultPrivacyPolicy
    )
  }

  static var termsOfUse: URL? {
    url(
      for: "TermsOfUseURL",
      fallback: defaultTermsOfUse
    )
  }

  private static func url(for infoKey: String, fallback: String) -> URL? {
    if let stringValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
      let configuredURL = URL(string: stringValue), !configuredURL.absoluteString.isEmpty
    {
      return configuredURL
    }
    return URL(string: fallback)
  }
}
