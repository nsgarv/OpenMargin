import Foundation

public enum NoteTemplate: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case general
    case oneOnOne
    case sales
    case standup
    case interview

    public var label: String {
        switch self {
        case .general: "General"
        case .oneOnOne: "1:1"
        case .sales: "Sales"
        case .standup: "Standup"
        case .interview: "Interview"
        }
    }

    /// Section shape for Enhance. Nil on a meeting means general, so older notes stay unchanged.
    public var instructions: String {
        switch self {
        case .general:
            "When the rough notes have no headings, use only the sections that have something in them: # Summary, # Decisions, # Action items, # Notes."
        case .oneOnOne:
            "Shape the note as a one-to-one. Use only the sections that have something in them: # What they need, # What you committed, # Follow-ups, # Notes. Do not turn it into a sales recap."
        case .sales:
            "Shape the note as a sales call. Use only the sections that have something in them: # What they want, # Objections, # Next step, # Notes."
        case .standup:
            "Shape the note as a standup. Use only the sections that have something in them: # Done, # Doing, # Blocked. Keep it short."
        case .interview:
            "Shape the note as an interview. Use only the sections that have something in them: # Signal, # Concerns, # Questions they asked, # Next step."
        }
    }

    /// A hint from a calendar title. Nil means leave the meeting unset.
    public static func guess(from title: String) -> NoteTemplate? {
        let text = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        if hasPhrase(text, "1:1") || hasPhrase(text, "1-1")
            || hasPhrase(text, "one on one") || hasPhrase(text, "one-on-one") || hasPhrase(text, "one to one") {
            return .oneOnOne
        }
        if hasPhrase(text, "standup") || hasPhrase(text, "stand-up") || hasPhrase(text, "stand up")
            || hasPhrase(text, "daily standup") || hasPhrase(text, "daily stand-up") {
            return .standup
        }
        if hasPhrase(text, "interview") {
            return .interview
        }
        if hasPhrase(text, "sales") || hasPhrase(text, "demo") || hasPhrase(text, "discovery") {
            return .sales
        }
        return nil
    }

    private static func hasPhrase(_ text: String, _ phrase: String) -> Bool {
        let pattern = "(^|[^a-z0-9])\(NSRegularExpression.escapedPattern(for: phrase))([^a-z0-9]|$)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
