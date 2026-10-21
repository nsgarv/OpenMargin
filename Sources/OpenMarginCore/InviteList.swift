import Foundation

public enum InviteList {
    public static func normalize(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isEmail(email) else { return nil }
        return email
    }

    /// Split a typed or pasted line into addresses. Commas and spaces both separate them.
    public static func emails(in raw: String) -> [String] {
        raw.split { $0 == "," || $0 == ";" || $0.isWhitespace }
            .compactMap { normalize(String($0)) }
    }

    public static func adding(_ raw: String, to list: [String]) -> [String] {
        var next = list
        for email in emails(in: raw) where !next.contains(email) {
            next.append(email)
        }
        return next
    }

    public static func isEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return value.unicodeScalars.allSatisfy { !$0.properties.isWhitespace }
    }
}
