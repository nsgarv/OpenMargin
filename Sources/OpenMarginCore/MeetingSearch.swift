import Foundation

public enum MeetingSearch {
    public struct Hit: Equatable, Sendable, Identifiable {
        public var id: UUID { meetingID }
        public var meetingID: UUID
        public var snippet: String

        public init(meetingID: UUID, snippet: String) {
            self.meetingID = meetingID
            self.snippet = snippet
        }
    }

    /// Every word must appear in the title, rough notes, finished note, or final transcript.
    /// A blank query returns every meeting, in the same order, with an empty snippet.
    public static func hits(in meetings: [Meeting], query: String) -> [Hit] {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { fold(String($0)) }
            .filter { !$0.isEmpty }
        if tokens.isEmpty {
            return meetings.map { Hit(meetingID: $0.id, snippet: "") }
        }
        return meetings.compactMap { meeting in
            let text = searchable(meeting)
            let folded = fold(text)
            guard tokens.allSatisfy({ folded.contains($0) }) else { return nil }
            return Hit(meetingID: meeting.id, snippet: snippet(in: text, matching: tokens[0]))
        }
    }

    private static func searchable(_ meeting: Meeting) -> String {
        var parts = [meeting.title, meeting.rawNotes]
        if let enhanced = meeting.enhancedNote {
            parts.append(EnhancedNote.plain(enhanced))
        }
        let spoken = meeting.transcript.filter(\.isFinal).map(\.text).joined(separator: " ")
        parts.append(spoken)
        return parts.joined(separator: "\n")
    }

    private static func snippet(in text: String, matching token: String) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let range = flat.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flat.prefix(80))
        }
        let start = flat.index(range.lowerBound, offsetBy: -36, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: 48, limitedBy: flat.endIndex) ?? flat.endIndex
        var piece = String(flat[start..<end])
        if start != flat.startIndex { piece = "…" + piece }
        if end != flat.endIndex { piece += "…" }
        return piece
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }
}
