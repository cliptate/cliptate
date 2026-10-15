import CliptateCore
import Foundation
import Testing


@Suite("TranscriptSession history payload fields")
struct TranscriptSessionHistoryTests {

    // MARK: - ttsAudioBookmark round-trip

    @Test
    func ttsAudioBookmarkRoundTrips() throws {
        let bookmarkData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        var session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 1_000_000),
            source: .ttsSynthesis
        )
        session.ttsAudioBookmark = bookmarkData

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: encoded)

        #expect(decoded.ttsAudioBookmark == bookmarkData)
    }

    // MARK: - aiCutSegments round-trip

    @Test
    func aiCutSegmentsRoundTrips() throws {
        let segment = Segment(
            startTime: 0.0,
            endTime: 1.5,
            text: "Hello world",
            words: [],
            speakerId: nil
        )
        var session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 2_000_000),
            source: .fileTranscription
        )
        session.aiCutSegments = [segment]

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: encoded)

        #expect(decoded.aiCutSegments?.count == 1)
        #expect(decoded.aiCutSegments?.first?.text == "Hello world")
        #expect(decoded.aiCutSegments?.first?.startTime == 0.0)
        #expect(decoded.aiCutSegments?.first?.endTime == 1.5)
    }

    @Test
    func aiCutTranslationsRoundTrip() throws {
        let translatedAt = Date(timeIntervalSince1970: 3_000_000)
        var segment = Segment(
            startTime: 0.0,
            endTime: 1.5,
            text: "Hello world",
            words: [],
            speakerId: nil
        )
        segment.translation = SegmentTranslation(
            text: "你好，世界",
            language: .chinese,
            translatedAt: translatedAt
        )
        var session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 2_000_000),
            source: .fileTranscription
        )
        session.aiCutSegments = [segment]
        session.aiCutLastTranslatedLanguage = .chinese

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: encoded)

        #expect(decoded.aiCutSegments?.first?.translation?.text == "你好，世界")
        #expect(decoded.aiCutSegments?.first?.translation?.language == .chinese)
        #expect(decoded.aiCutSegments?.first?.translation?.translatedAt == translatedAt)
        #expect(decoded.aiCutLastTranslatedLanguage == .chinese)
    }

    // MARK: - Backward compatibility: old JSON without new fields decodes cleanly

    @Test
    func backwardCompatibilityMissingNewFields() throws {
        // Simulate a JSON payload that predates ttsAudioBookmark and aiCutSegments.
        let oldJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "startTime": 1000000,
          "lines": [{"id": "00000000-0000-0000-0000-000000000002", "timestamp": 0, "text": "hi"}],
          "source": "fileTranscription"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: oldJSON)

        #expect(decoded.ttsAudioBookmark == nil)
        #expect(decoded.aiCutSegments == nil)
        #expect(decoded.aiCutOriginalSegments == nil)
        #expect(decoded.corrections == nil)
        #expect(decoded.aiCutLastTranslatedLanguage == nil)
        #expect(decoded.source == .fileTranscription)
    }

    // MARK: - Nil fields are omitted from encoded JSON (keeps store compact)

    @Test
    func nilNewFieldsAreAbsentFromJSON() throws {
        let session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 1_000_000),
            source: .voiceDictation
        )
        let encoded = try JSONEncoder().encode(session)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["ttsAudioBookmark"] == nil)
        #expect(json["aiCutSegments"] == nil)
        #expect(json["aiCutOriginalSegments"] == nil)
        #expect(json["corrections"] == nil)
        #expect(json["aiCutLastTranslatedLanguage"] == nil)
    }

    // MARK: - TranscriptLine speakerId

    @Test("TranscriptLine speakerId encodes and decodes correctly")
    func transcriptLineSpeakerIdRoundTrips() throws {
        let line = TranscriptLine(timestamp: 1.5, text: "Hello world", speakerId: 2)
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(TranscriptLine.self, from: data)
        #expect(decoded.speakerId == 2)
        #expect(decoded.text == "Hello world")
        #expect(decoded.timestamp == 1.5)
    }

    @Test("TranscriptLine without speakerId decodes as nil for backward compat")
    func transcriptLineNilSpeakerIdBackwardCompat() throws {
        let json = """
        {"id":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890","timestamp":2.0,"text":"Old line"}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TranscriptLine.self, from: data)
        #expect(decoded.speakerId == nil)
        #expect(decoded.text == "Old line")
    }

    @Test("TranscriptSession speakerFormattedText includes speaker prefixes")
    func combinedTextWithSpeakerPrefixes() {
        var session = TranscriptSession(startTime: Date())
        session.append(text: "Hello", at: 0, speakerId: 1)
        session.append(text: "Hi there", at: 1.5, speakerId: 2)
        session.append(text: "How are you?", at: 3.0, speakerId: 1)

        let combined = session.speakerFormattedText
        #expect(combined.contains("Speaker 1: Hello"))
        #expect(combined.contains("Speaker 2: Hi there"))
        #expect(combined.contains("Speaker 1: How are you?"))
    }

    @Test("TranscriptSession speakerFormattedText omits prefix when speakerId is nil")
    func combinedTextWithoutSpeakerPrefixes() {
        var session = TranscriptSession(startTime: Date())
        session.append(text: "Hello", at: 0)
        session.append(text: "World", at: 1.5)

        let combined = session.speakerFormattedText
        #expect(combined == "Hello\nWorld")
    }

    @Test("formattedText shows both speaker and timestamp when enabled")
    func formattedTextWithSpeakerAndTimestamp() {
        var session = TranscriptSession(startTime: Date())
        session.append(text: "Hello", at: 5, speakerId: 1)
        session.append(text: "World", at: 65, speakerId: 2)

        let text = session.formattedText(showSpeaker: true, showTimestamp: true)
        #expect(text.contains("[00:05] Speaker 1: Hello"))
        #expect(text.contains("[01:05] Speaker 2: World"))
    }

    @Test("formattedText shows only timestamp when speaker disabled")
    func formattedTextTimestampOnly() {
        var session = TranscriptSession(startTime: Date())
        session.append(text: "Hello", at: 90, speakerId: 1)

        let text = session.formattedText(showSpeaker: false, showTimestamp: true)
        #expect(text == "[01:30] Hello")
    }

    @Test("formattedText shows plain text when both disabled")
    func formattedTextPlainWhenBothDisabled() {
        var session = TranscriptSession(startTime: Date())
        session.append(text: "Hello", at: 5, speakerId: 1)
        session.append(text: "World", at: 10)

        let text = session.formattedText(showSpeaker: false, showTimestamp: false)
        #expect(text == "Hello\nWorld")
    }

    // MARK: - aiCutRemovedSegmentIDs round-trip

    @Test("aiCutRemovedSegmentIDs encodes and decodes correctly")
    func aiCutRemovedSegmentIDsRoundTrips() throws {
        let removedIDs: Set<SegmentIdentifier> = [
            SegmentIdentifier(startMillis: 1000, endMillis: 2500),
            SegmentIdentifier(startMillis: 5000, endMillis: 7300)
        ]
        var session = TranscriptSession(
            startTime: Date(timeIntervalSince1970: 2_000_000),
            source: .fileTranscription
        )
        session.aiCutRemovedSegmentIDs = removedIDs

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: encoded)

        #expect(decoded.aiCutRemovedSegmentIDs == removedIDs)
    }

    @Test("aiCutRemovedSegmentIDs nil for old sessions without field")
    func aiCutRemovedSegmentIDsBackwardCompat() throws {
        let oldJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000003",
          "startTime": 1000000,
          "lines": [{"id": "00000000-0000-0000-0000-000000000004", "timestamp": 0, "text": "hi"}],
          "source": "fileTranscription"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: oldJSON)
        #expect(decoded.aiCutRemovedSegmentIDs == nil)
    }
}
