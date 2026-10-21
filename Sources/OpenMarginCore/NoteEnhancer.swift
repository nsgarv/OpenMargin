import Foundation

public enum NoteEnhancer {
    public static let model = "grok-4.7"
    public static let endpoint = URL(string: "https://api.x.ai/v1/responses")!
    public static let notesLimit = 20_000
    public static let transcriptLimit = 60_000

    public static func prompt(for meeting: Meeting) -> String {
        let notes = clipped(meeting.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines), limit: notesLimit)
        let transcript = clipped(transcriptText(meeting), limit: transcriptLimit)
        let when = meeting.createdAt.formatted(date: .abbreviated, time: .shortened)
        return """
        You turn rough meeting notes plus a transcript into a finished note.

        Rules:
        - Use only the rough notes and the transcript. Do not invent names, numbers, decisions, or action items.
        - Keep the user's points. Complete them. Do not replace them.
        - Write plain text. A heading line starts with "# ". Separate paragraphs with a blank line.
        - Wrap every sentence the user did not already write in [[added]] and [[/added]]. Do not wrap their words.
        - If the transcript disagrees with a rough note, keep their note and add a short [[added]] line with what the transcript says.
        - When the rough notes have no headings, use only the sections that have something in them: # Summary, # Decisions, # Action items, # Notes.
        - You means the person who took the notes. Speakers means everyone else on the call. Room means one microphone heard everyone in the room.

        Title: \(meeting.title)
        When: \(when)

        Rough notes:
        \(notes.isEmpty ? "(none)" : notes)

        Transcript:
        \(transcript)
        """
    }

    public static func requestBody(for meeting: Meeting) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "input": prompt(for: meeting)
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    public static func enhance(meeting: Meeting, key: String, session: URLSession = .shared) async throws -> String {
        let notesEmpty = meeting.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let transcriptEmpty = meeting.transcript.allSatisfy { !$0.isFinal || $0.text.isEmpty }
        if notesEmpty && transcriptEmpty {
            throw EnhanceError.nothingToEnhance
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(for: meeting)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EnhanceError.requestFailed(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw EnhanceError.requestFailed(ResponsesText.failureMessage(data: data, status: status))
        }
        return try ResponsesText.outputText(in: data)
    }

    private static func transcriptText(_ meeting: Meeting) -> String {
        let lines = meeting.transcript.filter(\.isFinal).map { "[\($0.speaker.label)] \($0.text)" }
        return lines.isEmpty ? "(none)" : lines.joined(separator: "\n")
    }

    private static func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "\n[truncated]"
    }
}
