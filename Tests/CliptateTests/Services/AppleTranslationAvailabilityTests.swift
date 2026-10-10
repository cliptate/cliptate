import Testing
@testable import Cliptate

@Suite("AppleTranslationAvailability")
struct AppleTranslationAvailabilityTests {
    @Test("macOS 15 and later are supported")
    func supportedVersions() {
        #expect(AppleTranslationAvailability.isSupported(majorVersion: 15))
        #expect(AppleTranslationAvailability.isSupported(majorVersion: 26))
    }

    @Test("macOS 14 and earlier are unsupported")
    func unsupportedVersions() {
        #expect(!AppleTranslationAvailability.isSupported(majorVersion: 14))
        #expect(!AppleTranslationAvailability.isSupported(majorVersion: 13))
    }

    @Test("unsupported message names the correct floor")
    func minimumRequirementMessage() {
        let message = AppleTranslationAvailability.minimumRequirementMessage
        #expect(message.contains("macOS"))
        #expect(message.contains(String(AppleTranslationAvailability.minimumSupportedMajorVersion)))
    }
}
