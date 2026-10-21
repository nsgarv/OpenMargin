import Foundation

public enum Speaker: String, Codable, Equatable, Sendable {
    case me
    case speakers
    case room

    public var label: String {
        switch self {
        case .me: "You"
        case .speakers: "Speakers"
        case .room: "Room"
        }
    }
}

public enum CaptureMode: String, Codable, Equatable, Sendable, CaseIterable {
    case call
    case inRoom

    public var label: String {
        switch self {
        case .call: "Call"
        case .inRoom: "In the room"
        }
    }
}

public struct TranscriptLine: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var speaker: Speaker
    public var text: String
    public var isFinal: Bool
    public var at: Date

    public init(id: UUID, speaker: Speaker, text: String, isFinal: Bool, at: Date) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
        self.at = at
    }
}

public struct Meeting: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var captureMode: CaptureMode
    public var rawNotes: String
    public var enhancedNote: String?
    public var transcript: [TranscriptLine]
    public var calendarEventID: String?
    public var joinURL: String?
    /// Nil means general, including notes saved before templates existed.
    public var template: NoteTemplate?

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        captureMode: CaptureMode,
        rawNotes: String,
        enhancedNote: String?,
        transcript: [TranscriptLine],
        calendarEventID: String? = nil,
        joinURL: String? = nil,
        template: NoteTemplate? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.captureMode = captureMode
        self.rawNotes = rawNotes
        self.enhancedNote = enhancedNote
        self.transcript = transcript
        self.calendarEventID = calendarEventID
        self.joinURL = joinURL
        self.template = template
    }

    public static func new(now: Date = .now) -> Meeting {
        Meeting(
            id: UUID(),
            title: "New meeting",
            createdAt: now,
            captureMode: .call,
            rawNotes: "",
            enhancedNote: nil,
            transcript: []
        )
    }
}

public enum TranscriptLog {
    public static let mergeWindow: TimeInterval = 8
    public static let mergeCharacterLimit = 400

    public static func ingest(
        _ lines: inout [TranscriptLine],
        speaker: Speaker,
        text: String,
        isFinal: Bool,
        now: Date = .now
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if isFinal {
            lines.removeAll { $0.speaker == speaker && !$0.isFinal }
            if let index = lines.indices.last,
               lines[index].speaker == speaker,
               lines[index].isFinal,
               now.timeIntervalSince(lines[index].at) < mergeWindow,
               lines[index].text.count < mergeCharacterLimit {
                lines[index].text += " " + cleaned
            } else {
                lines.append(TranscriptLine(id: UUID(), speaker: speaker, text: cleaned, isFinal: true, at: now))
            }
        } else if let index = lines.lastIndex(where: { $0.speaker == speaker && !$0.isFinal }) {
            lines[index].text = cleaned
        } else {
            lines.append(TranscriptLine(id: UUID(), speaker: speaker, text: cleaned, isFinal: false, at: now))
        }
    }
}
