import AppKit
import Contacts
import Foundation
import Observation
import OpenMarginCore

struct Teammate: Codable, Equatable, Identifiable, Sendable {
    var id: String { email }
    var email: String
    var invitedAt: Date
}

@MainActor
@Observable
final class Workspace {
    var account: GoogleAuth.Profile?
    var teammates: [Teammate] = []
    var signingIn = false
    var status: String?
    var needsClientID = false

    init() {
        account = Self.loadAccount()
        teammates = Self.loadTeammates()
    }

    func signIn() async {
        guard let clientID = GoogleClient.current() else {
            needsClientID = true
            status = "Paste the desktop client ID from Google Cloud. Create an OAuth client of type Desktop, then paste it here."
            return
        }
        needsClientID = false
        signingIn = true
        status = "Waiting for Google…"
        defer { signingIn = false }
        do {
            account = try await GoogleAuth.signIn(clientID: clientID)
            status = nil
            try Self.saveAccount(account)
        } catch {
            status = error.localizedDescription
        }
    }

    func signOut() {
        account = nil
        status = nil
        try? Self.saveAccount(nil)
    }

    func saveClientID(_ clientID: String) throws {
        try GoogleClient.save(clientID)
        needsClientID = GoogleClient.current() == nil
        if !needsClientID {
            status = nil
        }
    }

    func invite(_ emails: [String]) -> String? {
        guard let account else { return "Sign in with Google first." }
        let recipients = emails.filter { InviteList.normalize($0) != nil && $0 != account.email }
        guard !recipients.isEmpty else { return "Add an email address." }
        let body = Self.invitation(from: account)
        guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [body]) else {
            return "Mail isn't available on this Mac."
        }
        service.recipients = recipients
        service.subject = "\(account.name) invited you to OpenMargin"
        service.perform(withItems: [body])
        let now = Date()
        for email in recipients where !teammates.contains(where: { $0.email == email }) {
            teammates.append(Teammate(email: email, invitedAt: now))
        }
        try? Self.saveTeammates(teammates)
        return nil
    }

    static func invitation(from account: GoogleAuth.Profile) -> String {
        """
        \(account.name) (\(account.email)) invited you to take meeting notes in OpenMargin.

        Notes stay on each person's Mac. OpenMargin doesn't join the call.

        https://github.com/nsgarv/OpenMargin
        """
    }

    func suggestions() async -> [(name: String, email: String)] {
        let store = CNContactStore()
        let granted: Bool
        do {
            granted = try await store.requestAccess(for: .contacts)
        } catch {
            return []
        }
        guard granted else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var people: [(name: String, email: String)] = []
        let own = account?.email
        let invited = Set(teammates.map(\.email))
        try? store.enumerateContacts(with: request) { contact, stop in
            guard let address = contact.emailAddresses.first?.value as String?,
                  let email = InviteList.normalize(address),
                  email != own,
                  !invited.contains(email) else { return }
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            people.append((name.isEmpty ? email : name, email))
            if people.count >= 8 { stop.pointee = true }
        }
        return people
    }

    private static func directory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMargin", isDirectory: true)
    }

    private static func loadAccount() -> GoogleAuth.Profile? {
        guard let data = try? Data(contentsOf: directory().appendingPathComponent("account.json")) else { return nil }
        return try? JSONDecoder().decode(GoogleAuth.Profile.self, from: data)
    }

    private static func saveAccount(_ account: GoogleAuth.Profile?) throws {
        let url = directory().appendingPathComponent("account.json")
        if let account {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(account)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func loadTeammates() -> [Teammate] {
        guard let data = try? Data(contentsOf: directory().appendingPathComponent("teammates.json")) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Teammate].self, from: data)) ?? []
    }

    private static func saveTeammates(_ teammates: [Teammate]) throws {
        let url = directory().appendingPathComponent("teammates.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(teammates).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
