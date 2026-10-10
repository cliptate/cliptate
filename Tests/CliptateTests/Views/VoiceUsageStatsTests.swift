import Foundation
import Testing

@testable import Cliptate

@Suite("VoiceUsageStats")
struct VoiceUsageStatsTests {

    // MARK: - averageWordsPerMinute

    @Test("averageWPM is zero when no words transcribed")
    func averageWPMZeroWithNoWords() {
        let stats = VoiceUsageStats(totalDuration: 60, sessionCount: 1, totalCharacters: 0, totalWords: 0)
        #expect(stats.averageWordsPerMinute == 0)
    }

    @Test("averageWPM is zero when duration is zero")
    func averageWPMZeroWithZeroDuration() {
        let stats = VoiceUsageStats(totalDuration: 0, sessionCount: 1, totalCharacters: 50, totalWords: 10)
        #expect(stats.averageWordsPerMinute == 0)
    }

    @Test("averageWPM computed correctly")
    func averageWPMComputed() {
        // 120 words in 60 seconds = 120 WPM
        let stats = VoiceUsageStats(totalDuration: 60, sessionCount: 1, totalCharacters: 600, totalWords: 120)
        #expect(abs(stats.averageWordsPerMinute - 120.0) < 0.01)
    }

    // MARK: - savedSeconds

    @Test("savedSeconds is zero when no words")
    func savedSecondsZeroWithNoWords() {
        let stats = VoiceUsageStats(totalDuration: 30, sessionCount: 1, totalCharacters: 0, totalWords: 0)
        #expect(stats.savedSeconds == 0)
    }

    @Test("voice dictation saves time even at low speaking rate")
    func savedSecondsPositiveAtLowSpeakingRate() {
        // 30 words spoken in 60 seconds (30 WPM spoken rate).
        // At the old 40 WPM typing baseline this returned 0.
        // The composition typing baseline (20 WPM) means typing those 30 words
        // would take 90 seconds, so 30 seconds should be saved.
        let stats = VoiceUsageStats(totalDuration: 60, sessionCount: 1, totalCharacters: 150, totalWords: 30)
        #expect(stats.savedSeconds > 0, "Expected positive time saved even at 30 WPM spoken rate")
    }

    @Test("savedSeconds is correct with composition typing baseline of 20 WPM")
    func savedSecondsUsesCompositionTypingBaseline() {
        // 60 words spoken in 60 seconds (60 WPM spoken rate).
        // Typing at 20 WPM takes 60/20*60 = 180 seconds.
        // Saved = 180 - 60 = 120 seconds.
        let stats = VoiceUsageStats(totalDuration: 60, sessionCount: 1, totalCharacters: 300, totalWords: 60)
        #expect(abs(stats.savedSeconds - 120.0) < 0.01)
    }

    @Test("savedSeconds is never negative")
    func savedSecondsNeverNegative() {
        // Extremely long session with very few words (e.g. a 10-minute session producing 5 words).
        let stats = VoiceUsageStats(totalDuration: 600, sessionCount: 1, totalCharacters: 25, totalWords: 5)
        #expect(stats.savedSeconds >= 0)
    }

    // MARK: - voiceTextCharacterCount

    @Test("characterCount includes whitespace")
    func characterCountIncludesSpaces() {
        // "hello world" has 11 characters including the space
        #expect(voiceTextCharacterCount(in: "hello world") == 11)
    }

    @Test("characterCount handles CJK text")
    func characterCountCJK() {
        // Each Chinese character counts as 1
        #expect(voiceTextCharacterCount(in: "你好世界") == 4)
    }

    @Test("characterCount of empty string is zero")
    func characterCountEmpty() {
        #expect(voiceTextCharacterCount(in: "") == 0)
    }

    // MARK: - voiceTextWordCount

    @Test("wordCount counts English words correctly")
    func wordCountEnglish() {
        #expect(voiceTextWordCount(in: "hello world foo") == 3)
    }

    @Test("wordCount handles CJK text with word boundaries")
    func wordCountCJK() {
        // Chinese: "今天天气很好" (The weather is nice today) should tokenize
        // into multiple words, not 1 (the old split-by-whitespace gave 1).
        let count = voiceTextWordCount(in: "今天天气很好")
        #expect(count > 1, "CJK text should be tokenized into multiple words, got \(count)")
    }

    @Test("wordCount handles mixed CJK and English")
    func wordCountMixed() {
        // Mixed text should count both CJK words and English words
        let count = voiceTextWordCount(in: "hello 你好世界")
        #expect(count >= 2, "Mixed text should have at least 2 words, got \(count)")
    }

    @Test("wordCount of empty string is zero")
    func wordCountEmpty() {
        #expect(voiceTextWordCount(in: "") == 0)
    }
}
