import Foundation
import Testing

@testable import Cliptate

/// Verifies that TTSPresetSpeaker descriptions and family subtitles are properly
/// localizable — non-empty, English-key-based, and safe to display in any locale.
@Suite("TTSPresetSpeaker – localization")
struct TTSPresetSpeakerLocalizationTests {

    // MARK: - Speaker descriptions

    @Test("All speakers have a non-empty description")
    func allSpeakersHaveDescription() {
        for speaker in TTSPresetSpeaker.all {
            #expect(!speaker.description.isEmpty, "\(speaker.name) has empty description")
        }
    }

    @Test("Speaker descriptions are not raw Chinese keys (no Chinese-only strings for English speakers)")
    func englishSpeakerDescriptionsAreInEnglish() {
        let englishSpeakers = TTSPresetSpeaker.all.filter { $0.language == .english }
        for speaker in englishSpeakers {
            // Description should not consist entirely of CJK characters
            let cjkOnly = speaker.description.unicodeScalars.allSatisfy {
                ($0.value >= 0x4E00 && $0.value <= 0x9FFF) // CJK Unified
                || ($0.value >= 0x3000 && $0.value <= 0x303F) // CJK punctuation
                || $0.value == 0xFF0C // Fullwidth comma
            }
            #expect(!cjkOnly, "\(speaker.name) description appears to be Chinese-only: '\(speaker.description)'")
        }
    }

    @Test("All 9 preset speakers are defined")
    func presetSpeakerCount() {
        #expect(TTSPresetSpeaker.all.count == 9)
    }

    @Test("Each speaker language group has the expected members")
    func speakerLanguageGroups() {
        #expect(TTSPresetSpeaker.speakers(for: .chinese).count == 5)
        #expect(TTSPresetSpeaker.speakers(for: .english).count == 2)
        #expect(TTSPresetSpeaker.speakers(for: .japanese).count == 1)
        #expect(TTSPresetSpeaker.speakers(for: .korean).count == 1)
    }

    // MARK: - nativeLanguage (system-localized)

    @Test("nativeLanguage is non-empty for all speakers")
    func nativeLanguageNonEmpty() {
        for speaker in TTSPresetSpeaker.all {
            #expect(!speaker.nativeLanguage.isEmpty, "\(speaker.name).nativeLanguage is empty")
        }
    }

    // MARK: - TTSModelFamily subtitles

    @Test("All TTSModelFamily subtitles are non-empty")
    func modelFamilySubtitlesNonEmpty() {
        for family in TTSModelFamily.allCases {
            #expect(!family.subtitle.isEmpty, "\(family) has empty subtitle")
        }
    }

    // MARK: - TTSVariantPreference display names

    @Test("All TTSVariantPreference displayNames are non-empty")
    func variantPreferenceDisplayNamesNonEmpty() {
        for variant in TTSVariantPreference.allCases {
            #expect(!variant.displayName.isEmpty, "\(variant) has empty displayName")
        }
    }
}
