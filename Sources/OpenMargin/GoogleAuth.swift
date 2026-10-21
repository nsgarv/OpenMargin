import AppKit
import CryptoKit
import Foundation
import Network
import Security

enum GoogleAuthError: LocalizedError {
    case cancelled
    case noEmail
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Google sign-in was cancelled."
        case .noEmail: "Google did not share an email address."
        case .requestFailed(let message): message
        }
    }
}

enum GoogleClient {
    static func current() -> String? {
        if let environment = trimmed(ProcessInfo.processInfo.environment["OPENMARGIN_GOOGLE_CLIENT_ID"]) {
            return environment
        }
        guard let data = try? Data(contentsOf: fileURL()) else { return nil }
        return trimmed(String(data: data, encoding: .utf8))
    }

    static func save(_ clientID: String) throws {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = fileURL()
        if trimmedID.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(trimmedID.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func fileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMargin", isDirectory: true)
            .appendingPathComponent("google-client-id")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum GoogleAuth {
    struct Profile: Codable, Equatable, Sendable {
        var email: String
        var name: String
        var pictureURL: String?
    }

    static func signIn(clientID: String) async throws -> Profile {
        let verifier = randomToken()
        let state = randomToken()
        let callback = Loopback()
        let port = try await callback.start()
        callback.prepare(state: state)
        let redirect = "http://127.0.0.1:\(port)"
        guard let url = authorizeURL(clientID: clientID, redirect: redirect, verifier: verifier, state: state) else {
            throw GoogleAuthError.requestFailed("Could not open Google.")
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw GoogleAuthError.requestFailed("The browser did not open.") }
        let code = try await callback.waitForCode(expectedState: state)
        let accessToken = try await exchange(code: code, verifier: verifier, redirect: redirect, clientID: clientID)
        return try await profile(accessToken: accessToken)
    }

    private static func authorizeURL(clientID: String, redirect: String, verifier: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        return components?.url
    }

    private static func exchange(code: String, verifier: String, redirect: String, clientID: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "client_id": clientID,
            "code_verifier": verifier,
            "redirect_uri": redirect,
            "grant_type": "authorization_code"
        ]
        request.httpBody = form(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw GoogleAuthError.requestFailed("Google did not accept the sign-in.")
        }
        return token
    }

    private static func profile(accessToken: String) async throws -> Profile {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String, !email.isEmpty else {
            throw GoogleAuthError.noEmail
        }
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Profile(
            email: email.lowercased(),
            name: (name?.isEmpty == false ? name! : email),
            pictureURL: json["picture"] as? String
        )
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func form(_ fields: [String: String]) -> Data {
        let encoded = fields.map { key, value in
            "\(key.formEncoded)=\(value.formEncoded)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}

/// Catches Google's redirect on 127.0.0.1. A desktop client may use any port there.
private final class Loopback: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: NWListener?
    private var expectedState = ""
    private var pending: Result<String, Error>?
    private var continuation: CheckedContinuation<String, Error>?

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection)
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                    listener.stateUpdateHandler = nil
                case .failed(let error):
                    continuation.resume(throwing: error)
                    listener.stateUpdateHandler = nil
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func prepare(state: String) {
        lock.lock()
        expectedState = state
        lock.unlock()
    }

    func waitForCode(expectedState: String) async throws -> String {
        prepare(state: expectedState)
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    self.lock.lock()
                    if let pending = self.pending {
                        self.lock.unlock()
                        continuation.resume(with: pending)
                        return
                    }
                    self.continuation = continuation
                    self.lock.unlock()
                }
            }
            group.addTask { [self] in
                try await Task.sleep(for: .seconds(180))
                self.fail(GoogleAuthError.cancelled)
                throw GoogleAuthError.cancelled
            }
            guard let code = try await group.next() else { throw GoogleAuthError.cancelled }
            group.cancelAll()
            stop()
            return code
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            self.lock.lock()
            let expected = self.expectedState
            self.lock.unlock()
            let outcome = Self.code(in: request, expectedState: expected)
            let page = switch outcome {
            case .code: "Signed in. You can close this window and return to OpenMargin."
            case .denied: "Sign-in was cancelled. You can close this window."
            case .ignore: "Waiting for Google."
            }
            let body = "<html><body><p>\(page)</p></body></html>"
            let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            if case .code(let value) = outcome {
                self.finish(value)
            } else if case .denied = outcome {
                self.fail(GoogleAuthError.cancelled)
            }
        }
    }

    private func finish(_ code: String) {
        deliver(.success(code))
    }

    private func fail(_ error: Error) {
        deliver(.failure(error))
    }

    private func deliver(_ result: Result<String, Error>) {
        lock.lock()
        guard pending == nil else {
            lock.unlock()
            return
        }
        pending = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
        stop()
    }

    private func stop() {
        listener?.cancel()
        listener = nil
    }

    private enum Outcome {
        case code(String)
        case denied
        case ignore
    }

    private static func code(in request: String, expectedState: String) -> Outcome {
        guard let line = request.split(whereSeparator: \.isNewline).first else { return .ignore }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return .ignore }
        guard let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return .ignore }
        let items = components.queryItems ?? []
        if let state = items.first(where: { $0.name == "state" })?.value, !expectedState.isEmpty, state != expectedState {
            return .ignore
        }
        if items.contains(where: { $0.name == "error" }) { return .denied }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return .ignore }
        return .code(code)
    }
}
