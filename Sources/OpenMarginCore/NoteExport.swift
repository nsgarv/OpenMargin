import Foundation

public enum NoteExport {
    /// Title, date, the finished note (enhanced text with model markers removed, otherwise the rough note), then the transcript.
    public static func document(for meeting: Meeting) -> String {
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = title.isEmpty ? "Untitled" : title
        let when = meeting.createdAt.formatted(date: .abbreviated, time: .shortened)
        let body = finishedNote(meeting)
        let lines = meeting.transcript.filter(\.isFinal).map { "- [\($0.speaker.label)] \($0.text)" }
        let transcript = lines.isEmpty ? "(none)" : lines.joined(separator: "\n")
        return """
        # \(heading)
        \(when)

        \(body)

        # Transcript
        \(transcript)
        """
    }

    public static func subject(for meeting: Meeting) -> String {
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Meeting notes" : title
    }

    public static func filename(for meeting: Meeting) -> String {
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title.isEmpty ? "Meeting" : title
        let cleaned = String(base.map { character in
            if character.isLetter || character.isNumber || character == " " || character == "-" {
                return character
            }
            return "-"
        })
        let squashed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "\(squashed.isEmpty ? "Meeting" : squashed).md"
    }

    private static func finishedNote(_ meeting: Meeting) -> String {
        if let enhanced = meeting.enhancedNote?.trimmingCharacters(in: .whitespacesAndNewlines), !enhanced.isEmpty {
            return EnhancedNote.plain(enhanced)
        }
        let rough = meeting.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return rough.isEmpty ? "(no notes)" : rough
    }
}
