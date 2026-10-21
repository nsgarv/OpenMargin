import Foundation
import OpenMarginCore
import XCTest

final class TranscriptLogTests: XCTestCase {
    func testMergesAShortTurnAndSplitsAfterTheWindow() {
        var lines: [TranscriptLine] = []
        let start = Date(timeIntervalSince1970: 1_000)
        TranscriptLog.ingest(&lines, speaker: .me, text: "Hello", isFinal: true, now: start)
        TranscriptLog.ingest(&lines, speaker: .me, text: "there", isFinal: true, now: start.addingTimeInterval(3))
        XCTAssertEqual(lines.map(\.text), ["Hello there"])

        TranscriptLog.ingest(&lines, speaker: .me, text: "later", isFinal: true, now: start.addingTimeInterval(9))
        XCTAssertEqual(lines.map(\.text), ["Hello there", "later"])
    }

    func testVolatileLineBecomesFinalWithoutDuplicating() {
        var lines: [TranscriptLine] = []
        let start = Date(timeIntervalSince1970: 2_000)
        TranscriptLog.ingest(&lines, speaker: .speakers, text: "hel", isFinal: false, now: start)
        TranscriptLog.ingest(&lines, speaker: .speakers, text: "hello room", isFinal: false, now: start.addingTimeInterval(1))
        XCTAssertEqual(lines.count, 1)
        XCTAssertFalse(lines[0].isFinal)

        TranscriptLog.ingest(&lines, speaker: .speakers, text: "hello room", isFinal: true, now: start.addingTimeInterval(2))
        XCTAssertEqual(lines.map(\.text), ["hello room"])
        XCTAssertTrue(lines[0].isFinal)
    }

    func testSpeakersStaySeparate() {
        var lines: [TranscriptLine] = []
        let start = Date(timeIntervalSince1970: 3_000)
        TranscriptLog.ingest(&lines, speaker: .me, text: "I can ship Friday", isFinal: true, now: start)
        TranscriptLog.ingest(&lines, speaker: .speakers, text: "Friday works", isFinal: true, now: start.addingTimeInterval(1))
        XCTAssertEqual(lines.map(\.speaker), [.me, .speakers])
    }
}

final class EnhancedNoteTests: XCTestCase {
    func testParsesHeadingsAndAddedSpans() {
        let source = """
        # Decisions
        Ship Friday.
        [[added]]Alex agreed to send the redlines.[[/added]]

        # Action items
        """
        let blocks = EnhancedNote.parse(source)
        XCTAssertEqual(blocks, [
            .heading("Decisions"),
            .paragraph("Ship Friday.", added: false),
            .paragraph("Alex agreed to send the redlines.", added: true),
            .heading("Action items")
        ])
        XCTAssertEqual(
            EnhancedNote.plain(source),
            "Decisions\n\nShip Friday.\n\nAlex agreed to send the redlines.\n\nAction items"
        )
    }

    func testUnclosedAddedSpanStillShows() {
        let blocks = EnhancedNote.parse("Keep this. [[added]]And this")
        XCTAssertEqual(blocks, [
            .paragraph("Keep this.", added: false),
            .paragraph("And this", added: true)
        ])
    }
}

final class ResponsesTextTests: XCTestCase {
    func testSkipsReasoningAndReadsOutputText() throws {
        let json = """
        {
          "output": [
            {"type": "reasoning", "content": [{"type": "text", "text": "thinking"}]},
            {"type": "message", "content": [{"type": "output_text", "text": "Ship Friday."}]}
          ]
        }
        """.data(using: .utf8)!
        XCTAssertEqual(try ResponsesText.outputText(in: json), "Ship Friday.")
    }

    func testReadsErrorMessage() {
        let json = #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!
        XCTAssertEqual(ResponsesText.failureMessage(data: json, status: 401), "bad key")
    }
}

final class NoteEnhancerTests: XCTestCase {
    func testPromptContainsTheNoteAndTranscript() throws {
        var meeting = Meeting.new(now: Date(timeIntervalSince1970: 1_700_000_000))
        meeting.title = "Pricing"
        meeting.rawNotes = "Hold the price."
        meeting.transcript = [
            TranscriptLine(id: UUID(), speaker: .speakers, text: "We can wait until May.", isFinal: true, at: meeting.createdAt),
            TranscriptLine(id: UUID(), speaker: .me, text: "partial", isFinal: false, at: meeting.createdAt)
        ]
        let prompt = NoteEnhancer.prompt(for: meeting)
        XCTAssertTrue(prompt.contains("Hold the price."))
        XCTAssertTrue(prompt.contains("[Speakers] We can wait until May."))
        XCTAssertFalse(prompt.contains("partial"))

        let body = try JSONSerialization.jsonObject(with: NoteEnhancer.requestBody(for: meeting)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "grok-4.7")
    }
}

final class MeetingLinkTests: XCTestCase {
    func testRecognizesMeetingHosts() {
        XCTAssertEqual(MeetingLink.name(for: URL(string: "https://meet.google.com/abc-defg-hij")!), "Google Meet")
        XCTAssertEqual(MeetingLink.name(for: URL(string: "https://us05web.zoom.us/j/123")!), "Zoom")
        XCTAssertEqual(MeetingLink.name(for: URL(string: "https://teams.microsoft.com/l/meetup-join/x")!), "Teams")
        XCTAssertNil(MeetingLink.name(for: URL(string: "https://example.com")!))
    }

    func testFindsAMeetingLinkInsideNotes() {
        let text = "See you there https://company.webex.com/meet/alex and bring the doc."
        XCTAssertEqual(MeetingLink.firstMeetingURL(in: text)?.host, "company.webex.com")
    }
}

final class MeetingStoreTests: XCTestCase {
    func testLoadsMeetingsSavedBeforeCalendarFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"meetings":[{"captureMode":"call","createdAt":"2026-01-01T00:00:00Z","enhancedNote":null,"id":"11111111-1111-1111-1111-111111111111","rawNotes":"hi","title":"Old","transcript":[]}],"version":1}
        """
        try Data(json.utf8).write(to: store.fileURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.first?.title, "Old")
        XCTAssertNil(loaded.first?.joinURL)
    }

    func testRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingStore(directory: directory)
        var meeting = Meeting.new(now: Date(timeIntervalSince1970: 1_700_000_000))
        meeting.title = "Standup"
        meeting.rawNotes = "Ship the margin."
        try store.save([meeting])
        let loaded = store.load()
        XCTAssertEqual(loaded, [meeting])
    }
}
