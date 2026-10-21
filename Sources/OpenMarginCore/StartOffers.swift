import Foundation

public struct StartCandidate: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case event
        case liveApp
    }

    public var id: String
    public var title: String
    public var kind: Kind

    public var promptTitle: String {
        switch kind {
        case .event: title
        case .liveApp: "\(title) is open"
        }
    }

    public static func event(id: String, title: String) -> StartCandidate {
        StartCandidate(id: id, title: title, kind: .event)
    }

    public static func live(name: String) -> StartCandidate {
        StartCandidate(id: "live:\(name)", title: name, kind: .liveApp)
    }
}

public enum StartOffers {
    /// While listening, or after this id was accepted or dismissed, there is nothing to ask.
    /// A meeting that is happening now wins over a detected app, and a dismissed event does not fall through to the app.
    public static func next(
        listening: Bool,
        handled: Set<String>,
        happeningNow: StartCandidate?,
        liveApp: StartCandidate?
    ) -> StartCandidate? {
        guard !listening else { return nil }
        if let happeningNow {
            guard !handled.contains(happeningNow.id) else { return nil }
            guard !happeningNow.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return happeningNow
        }
        if let liveApp, !handled.contains(liveApp.id) {
            guard !liveApp.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return liveApp
        }
        return nil
    }
}
