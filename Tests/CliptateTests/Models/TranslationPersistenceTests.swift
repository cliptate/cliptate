import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("Translation persistence through history")
struct TranslationPersistenceTests {

    // MARK: - Demonstrates the bug: injection fails with split segment IDs

    @Test
    func injectTranslationsFailsWithSplitSegmentIDs() throws {
        // Raw segment has ID "ABC"
        let rawSegment = Segment(
            id: "ABC",
            startTime: 0.0, endTime: 5.0,
            text: "Hello world this is a test"
        )

        // After splitting, child segment has deterministic ID "ABC:0-2500"
        let childId = Segment.deterministicChildId(
            parentId: "ABC", startTime: 0.0, endTime: 2.5)

        // Translation keyed by processed (child) segment ID
        let translations: [String: SegmentTranslation] = [
            childId: SegmentTranslation(text: "你好世界", language: .chinese)
        ]

        // injectTranslations looks up seg.id in translations dict
        let result = VideoState.injectTranslations(translations, into: [rawSegment])

        // BUG: translation is NOT injected because "ABC" != "ABC:0-2500"
        #expect(result.first?.translation == nil,
                "Current behavior: injection fails because raw ID doesn't match split ID")
    }

    // MARK: - processedTranslations round-trip through TranscriptSession

    @Test
    func processedTranslationsRoundTrip() throws {
        let childId = Segment.deterministicChildId(
            parentId: "SEG1", startTime: 0.0, endTime: 2.5)

        let translations: [String: SegmentTranslation] = [
            childId: SegmentTranslation(
                text: "翻译文本",
                language: .chinese,
                translatedAt: Date(timeIntervalSince1970: 5_000_000)
            )
        ]

        var session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 2_000_000),
            source: .fileTranscription
        )
        session.aiCutSegments = [
            Segment(id: "SEG1", startTime: 0.0, endTime: 5.0, text: "Hello")
        ]
        session.aiCutProcessedTranslations = translations
        session.aiCutLastTranslatedLanguage = .chinese

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: encoded)

        #expect(decoded.aiCutProcessedTranslations?.count == 1)
        #expect(decoded.aiCutProcessedTranslations?[childId]?.text == "翻译文本")
        #expect(decoded.aiCutProcessedTranslations?[childId]?.language == .chinese)
        #expect(decoded.aiCutLastTranslatedLanguage == .chinese)
    }

    // MARK: - Backward compat: old JSON without processedTranslations

    @Test
    func backwardCompatMissingProcessedTranslations() throws {
        let oldJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000099",
          "startTime": 1000000,
          "lines": [],
          "source": "fileTranscription",
          "aiCutSegments": [
            {"startTime": 0, "endTime": 5, "text": "Hello"}
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: oldJSON)
        #expect(decoded.aiCutProcessedTranslations == nil)
        #expect(decoded.aiCutSegments?.count == 1)
    }

    // MARK: - Nil processedTranslations omitted from JSON

    @Test
    func nilProcessedTranslationsOmittedFromJSON() throws {
        let session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 1_000_000),
            source: .fileTranscription
        )
        let encoded = try JSONEncoder().encode(session)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["aiCutProcessedTranslations"] == nil)
    }

    // MARK: - Integration: SegmentComputer injects from restored processedTranslations

    @Test @MainActor
    func segmentComputerInjectsRestoredTranslations() throws {
        // Simulate raw segments stored in history
        let rawSegments = [
            Segment(id: "SEG1", startTime: 0.0, endTime: 5.0, text: "Hello world")
        ]

        // Simulate processed translations keyed by the same ID (no splitting case)
        let translations: [String: SegmentTranslation] = [
            "SEG1": SegmentTranslation(text: "你好世界", language: .chinese)
        ]

        let input = SegmentComputer.Input(
            segments: rawSegments,
            totalDuration: 5.0,
            filterSilent: false,
            splitBySentence: false,
            maxCharsPerSegment: 0,
            leftPadMs: 0,
            rightPadMs: 0,
            effectFilterFillerWords: false,
            fillerWords: [],
            dictionaryEntries: [],
            removedSegmentIDs: [],
            processedTranslations: translations
        )

        let result = SegmentComputer.compute(input)
        #expect(result.first?.translation?.text == "你好世界")
    }

    // MARK: - Integration: full save/restore cycle with split segments

    @Test @MainActor
    func fullSaveRestoreCycleWithSplitSegments() throws {
        // 1. Create raw segment
        let rawSegment = Segment(
            id: "PARENT",
            startTime: 0.0, endTime: 5.0,
            text: "Hello world this is a long sentence that will be split"
        )

        // 2. Simulate split child IDs (as SegmentComputer would produce)
        let childId1 = Segment.deterministicChildId(
            parentId: "PARENT", startTime: 0.0, endTime: 2.5)
        let childId2 = Segment.deterministicChildId(
            parentId: "PARENT", startTime: 2.5, endTime: 5.0)

        // 3. Translations keyed by child IDs
        let processedTranslations: [String: SegmentTranslation] = [
            childId1: SegmentTranslation(text: "你好世界", language: .chinese),
            childId2: SegmentTranslation(text: "这是测试", language: .chinese)
        ]

        // 4. Save to TranscriptSession
        var session = TranscriptSession(
            startTime: Date(),
            source: .fileTranscription
        )
        session.aiCutSegments = [rawSegment]
        session.aiCutProcessedTranslations = processedTranslations
        session.aiCutLastTranslatedLanguage = .chinese

        // 5. Encode and decode (simulating disk persistence)
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: encoded)

        // 6. Verify translations survived the round trip
        #expect(decoded.aiCutProcessedTranslations?.count == 2)
        #expect(decoded.aiCutProcessedTranslations?[childId1]?.text == "你好世界")
        #expect(decoded.aiCutProcessedTranslations?[childId2]?.text == "这是测试")
    }

    // MARK: - Factory preserves processedTranslations

    @Test
    func factoryPreservesProcessedTranslations() throws {
        let translations: [String: SegmentTranslation] = [
            "SEG1": SegmentTranslation(text: "测试", language: .chinese)
        ]
        let segment = Segment(id: "SEG1", startTime: 0, endTime: 5, text: "Test")
        let url = URL(fileURLWithPath: "/tmp/test.mp4")

        let session = try FileTranscriptionHistorySessionFactory.makeSession(
            url: url,
            segments: [segment],
            lastTranslatedLanguage: .chinese,
            processedTranslations: translations,
            duration: 5.0,
            transcriberType: .parakeet,
            modelVariant: .parakeetV3,
            language: .english
        )

        #expect(session.aiCutProcessedTranslations?["SEG1"]?.text == "测试")
        #expect(session.aiCutLastTranslatedLanguage == .chinese)
    }

    @Test
    func factoryPreservesProvidedSourceBookmark() throws {
        let bookmark = Data([0x01, 0x02, 0x03])
        let segment = Segment(id: "SEG1", startTime: 0, endTime: 5, text: "Test")
        let url = URL(fileURLWithPath: "/tmp/test.mp4")

        let session = try FileTranscriptionHistorySessionFactory.makeSession(
            url: url,
            segments: [segment],
            sourceURLBookmark: bookmark,
            duration: 5.0,
            transcriberType: .parakeet,
            modelVariant: .parakeetV3,
            language: .english
        )

        #expect(session.sourceURLBookmark == bookmark)
    }

    @Test
    func factoryBuildsTranscriptLinesFromWordTimingsWhenSegmentTextIsBlank() throws {
        let words = [
            WordTiming(word: "Hello", startTime: 0.0, endTime: 0.4),
            WordTiming(word: "world", startTime: 0.4, endTime: 0.9, punctuation: "!")
        ]
        let segment = Segment(
            id: "SEG1",
            startTime: 0,
            endTime: 1,
            text: "   ",
            words: words
        )
        let url = URL(fileURLWithPath: "/tmp/test.mp4")

        let session = try FileTranscriptionHistorySessionFactory.makeSession(
            url: url,
            segments: [segment],
            duration: 1.0,
            transcriberType: .parakeet,
            modelVariant: .parakeetV3,
            language: .english
        )

        #expect(session.lines.count == 1)
        #expect(session.lines.first?.text == "Hello world!")
        #expect(session.combinedText == "Hello world!")
    }
}
