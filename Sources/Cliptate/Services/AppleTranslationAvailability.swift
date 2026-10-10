import Foundation

enum AppleTranslationAvailability {
    static let minimumSupportedMajorVersion = 15
    static func isSupported(majorVersion: Int) -> Bool {
        majorVersion >= minimumSupportedMajorVersion
    }
    /// True if the current macOS major version supports Apple Translation.
    /// Unit tests target isSupported(majorVersion:) for deterministic results.
    static var isRuntimeSupported: Bool {
        isSupported(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
    // Keep this key's version in sync with minimumSupportedMajorVersion.
    static var minimumRequirementMessage: String {
        String(localized: "Apple Translation requires macOS 15 or later", comment: "Translation feature system requirement message")
    }
}
